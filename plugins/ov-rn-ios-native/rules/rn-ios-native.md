# React Native iOS bridge rules

Opinionated rules for the Swift / Obj-C / Obj-C++ code that participates in the React Native bridge on iOS — TurboModules, legacy NativeModules, Fabric ComponentView, legacy ViewManager, AppDelegate bridge wiring, and Podfile surface. Not pure iOS app code, not JS/TS.

## Review behavior

Applies to any tool that reads this file via CLAUDE.md — `/pr-review-toolkit:review-pr`, `/security-review`, `/simplify`, `/code-review:code-review`, and our `/ov-rn-ios-native-review-deep` orchestrator.

**Scope:** Only report findings for React Native iOS bridge code (Swift/Obj-C/Obj-C++ that participates in the RN bridge — TurboModules, legacy NativeModules, Fabric ComponentView, legacy ViewManager, AppDelegate RN-bridge setup, Podfile changes). Ignore findings about pure iOS app code (covered by the sibling `ios` plugin), React Native JavaScript/TypeScript code (covered by the `rn-typescript` plugin), or Android bridge code.

**In-scope findings (report):**
- Correctness bugs (logic errors, race conditions, crashes, data corruption)
- Security issues (Keychain misuse, insecure transport in native module, secret exposure in bundle/Info.plist, deep-link validation in AppDelegate)
- Bridge-specific concerns (method signature hazards, multi-resolve of Promises, memory across the bridge, thread hopping, TurboModule / Fabric spec correctness, codegen drift)
- Explicit rule violations from this file

**Out-of-scope (drop, do not report):**
- Pure style, whitespace, blank lines, import order, trailing commas
- Comment/docstring formatting
- Anything a linter/formatter/compiler catches (SwiftLint, SwiftFormat, clang-format, Xcode warnings)
- Pedantic naming, "could be shorter" suggestions
- Pre-existing issues on lines not in the diff
- Findings about pure iOS app code, Android bridge code, or JS/TS code
- Findings duplicated by the sibling `ios` plugin's rules (SwiftUI state, pure-app architecture)

**Confidence gate:** Report only findings you are >=80% confident are real. When in doubt, drop. Prefer false negatives over noise.

## Architecture

- **New Architecture (TurboModules + Fabric) is the baseline.** New modules and components must be TurboModules / Fabric ComponentView with a codegen-backed TypeScript spec. Do not introduce a new `RCTBridgeModule` subclass or a new `RCTViewManager` in a codebase that has already migrated. If the project is still on Legacy, call that out in the PR rather than silently registering legacy and new in the same diff.
- **One module per class, one class per file.** A single `@objc(MyModule)` or `RCT_EXPORT_MODULE(MyModule)` per `.swift`/`.mm`. Do not register two JS names from one class — discovery collisions surface only at runtime as "Module X was already registered."
- **Module name is load-bearing.** The string in `RCT_EXPORT_MODULE(Name)` / `@objc(Name)` is the JS import key and must match the codegen spec name exactly (and the TS-side `TurboModuleRegistry.getEnforcing<Spec>('Name')`). A mismatch is a silent `nil` return and a JS-side null-pointer crash — not a compile error.
- **Autolinking is the default; manual linking is the exception.** Rely on `use_react_native!` + `use_native_modules!` in the Podfile. If a Pod must be added manually, do it in the app's `Podfile`, not by editing the Pods project or copying sources into the app target — that breaks `pod install` reproducibility.
- **AppDelegate: minimal, RN-only setup lives in bridge code.** `- (BOOL)application:didFinishLaunchingWithOptions:` must create the `RCTAppDelegate`-derived root (or call `super`), register Expo modules if on Expo, and return. Don't perform feature-specific work (analytics init, SDK bootstrapping) ahead of the bridge; that runs on the UI thread and blocks first paint. Hook into `[bridge onSetupRootView]` / `applicationDidBecomeActive` for deferred work instead.
- **Do not add native dependencies inside `packages/*` that aren't also listed in the app's `Podfile.lock`.** Autolinking scans the app target's `node_modules`; a shared-library dep that's not in the app package will link on one build and vanish on the next CI machine.

## Swift / Obj-C interop

- **Module classes must inherit from `NSObject`.** TurboModule and legacy-module registration is discovered via the Obj-C runtime, even in Swift under the new architecture. A plain `final class` with no parent will not be found; the JS-side call returns `null` and throws. Inherit from `NSObject` and mark the class `@objc(JSName)`.
- **Prefer `RCT_EXTERN_MODULE` + `RCT_EXTERN_METHOD` for Swift TurboModules under the legacy bridge.** A separate `.m` file with `RCT_EXTERN_MODULE(MyModule, NSObject)` and explicit `RCT_EXTERN_METHOD` lines gives you control over the Obj-C method signature seen by JS. `RCT_EXPORT_MODULE()` in a `.swift` extension of an Obj-C class is brittle and hides the exported signatures. Under the new architecture, follow the codegen-generated spec pattern (conform the class to `NativeFooSpec`).
- **Only types that bridge to Obj-C can cross the boundary.** Swift types exposed to JS must be `NSNumber *`, `NSString *`, `NSDictionary *`, `NSArray *`, `BOOL` (as `NSNumber`), or blocks typed as `RCTResponseSenderBlock` / `RCTPromiseResolveBlock` / `RCTPromiseRejectBlock`. `Int`, `Double`, `String` work in Swift source, but the compiler bridges them; do not expose Swift-only types (`enum` without `@objc`, struct, tuple, generic) — they cannot be represented in Obj-C and fail to register.
- **Wrap primitives as `NSNumber *` at the Obj-C boundary.** JS can pass `null` for any parameter, and `null` bridges to `nil`. Declaring a method with a primitive `BOOL`, `NSInteger`, or `double` parameter crashes when JS passes `null` — the Obj-C dispatcher hits an unboxing failure. Accept `NSNumber *`, then coerce inside the method: `BOOL value = [obj boolValue];`.
- **Do not use Swift-only features across an exported signature.** Optionals must bridge as nullable Obj-C types; tuples and result builders cannot appear in a bridged method signature. If you need to return structured data to JS, build an `NSDictionary *` inside the Swift implementation.

## Bridge contract (method signatures)

- **`RCT_EXPORT_METHOD` parameter types are Obj-C pointer types.** Use `NSString *`, `NSNumber *`, `NSDictionary *`, `NSArray *` — not `NSString` without the `*`, and never `BOOL` / `NSInteger` / `double` directly. JS can pass `null`; primitive types crash on unbox.
- **Async method signature is `resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock` as the last two parameters.** Any other order — or omitting `reject` — makes the method register as synchronous with unexpected arity and JS calls silently error. Mark both as `@escaping` in Swift; the blocks outlive the method.
- **Call `resolve` or `reject` exactly once per invocation. Never both; never twice.** RN asserts and crashes with `Callback was already invoked` on a second call. When there are multiple code paths (error guards, branches), gate with a `__block BOOL done = NO;` (Obj-C) or `var completed = false` + lock (Swift) and no-op subsequent calls.
- **`reject` takes `(code, message, error)` — the code string is the stable API.** JS callers match on `error.code`. Use a small enumerated set of stable codes (`"E_PERMISSION_DENIED"`, `"E_NETWORK"`, `"E_UNEXPECTED"`) and pass an `NSError *` only when the underlying system already produced one. Never reject with `nil` code or a raw `[error localizedDescription]` as the code; that breaks downstream `switch` statements.
- **Callback-style methods (`RCTResponseSenderBlock`) are legacy — prefer Promises for new code.** If you must use a callback, it takes a single `NSArray *` argument. The Node-style `(error, result)` convention is *yours to enforce*; RN does not distinguish. Promise methods give JS a `try/catch`, proper stack traces, and discriminated resolve/reject.
- **Do not call `resolve(someBlock)` with a block parameter — blocks do not round-trip back to JS.** Only JSON-serializable primitives, strings, numbers, booleans, arrays, and dictionaries can cross back. If you need a callback-on-native → callback-in-JS flow, emit an event via `RCTEventEmitter` instead.
- **Methods returning synchronously (`RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD`) run on the JS thread and block every frame they hold.** Use only for trivial getters that return in well under a millisecond — constants, feature-flag reads from memory. Anything doing disk/network/UIKit/lock acquisition must be async and `Promise`-returning.

## New Architecture (TurboModules / Fabric / Codegen)

- **The TypeScript spec is the contract; native implementations conform to it, not the other way around.** Edit `NativeFoo.ts` / `FooComponentView.ts` first, run `pod install` (which triggers codegen), then update the native implementation against the generated `NativeFooSpec.h` / `RCTFooViewComponentView.h`. A native impl that "works" but doesn't match the spec will compile until JS calls a method the spec expects but the native class doesn't implement.
- **Conform to the codegen-generated protocol explicitly.** `@interface MyModule : NSObject <NativeFooSpec>` / `class MyModule: NSObject, NativeFooSpec`. Missing the conformance means codegen's type-checked dispatch falls back to dynamic Obj-C lookup, and method-signature mismatches surface as runtime crashes rather than compile errors.
- **Run codegen on every spec change; commit the expected outputs only if the project convention does.** `pod install` runs `react-native-codegen` and regenerates `build/generated/ios/`. If the project gitignores the generated folder (default), don't commit it. If the project commits it (monorepos sometimes do), run codegen and commit the refresh in the same diff.
- **Fabric ComponentView: subclass `RCTViewComponentView` and override `updateProps:oldProps:`.** Don't override `init` to set up the view — the view is pooled and reused; one-time setup goes in `initWithFrame:` or a lazy getter. Apply only the delta between `oldProps` and `props`, and read each field from the codegen-generated `Props` struct, not from an `NSDictionary`.
- **Register the component with `RCT_REGISTER_COMPONENT()` (legacy) or `[FooComponentView class]` discovery (new arch).** Under Fabric, a `+ (void)registerAsComponent` / `+load` registration hook that calls `RCTRegisterViewComponent(@"Foo", [FooComponentView class])` is required — without it, Fabric falls back to a legacy ViewManager path and complex component props silently no-op.
- **Do not mix new-arch and legacy registration for the same component.** Having both `RCTViewManager` and `RCTViewComponentView` for `RNFoo` registers the component twice and Fabric picks whichever won the `+load` race. Delete the legacy ViewManager in the same commit as the Fabric component.
- **Interop layer (`RCTLegacyViewManagerInteropComponentView`) is a migration stepping stone, not a destination.** If a Legacy ViewManager must ride along while its Fabric replacement is in progress, document the sunset date in a TODO and do not ship new props to the legacy path.
- **Module constants (`constantsToExport`) run synchronously on the main thread during bridge init — keep them cheap.** Disk reads, Keychain lookups, or remote config calls in `constantsToExport` add directly to cold-start time. Return static or memory-resident values only; defer anything I/O-bound to an explicit async method.

## Concurrency & threading

- **Async TurboModule methods default to the native-modules serial queue.** Do not hop to `DispatchQueue.global()` unnecessarily — you are already off the JS thread. Hop *only* when the work is CPU-bound and parallelizable, or when a synchronous API blocks the queue and you need to free it.
- **Override `methodQueue` only when the module must run on the main queue.** `- (dispatch_queue_t)methodQueue { return dispatch_get_main_queue(); }` is correct for modules that touch UIKit directly (view controller presentation, keyboard APIs). For anything else, leave the default serial background queue.
- **Never dispatch synchronously to the main queue from a bridge method.** `dispatch_sync(dispatch_get_main_queue(), ...)` inside a method running on the JS thread (a synchronous method) deadlocks the app. Use `dispatch_async` or await a `CheckedContinuation`.
- **Under Swift concurrency, mark UIKit-touching code `@MainActor`; do not hop with `Task { @MainActor in ... }` inside every call site.** Isolate the type once at declaration; the resolve/reject blocks still complete on whatever thread the caller was on.
- **The JS thread is not yours to block.** Any sync-exported method (`RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD`) that runs more than a few hundred microseconds drops frames visibly. Never acquire a lock, read disk, or call UIKit from a sync method.
- **Do not call back into JS from a background queue without a `CallInvoker`.** Fabric / TurboModule events emitted from an arbitrary thread must go through the `RCTCallInvoker` (new arch) or `[bridge.eventDispatcher sendEvent...]` (legacy) — both serialize back onto the correct thread. Emitting directly from `DispatchQueue.global()` corrupts JSI runtime state and crashes inconsistently.
- **`invalidate` on a TurboModule runs on the native-modules thread during bridge teardown.** Treat it like `deinit`: cancel in-flight work, null out delegate pointers, and do not assume the JS runtime is still alive. Do not emit an event from `invalidate` — the receiver is gone.
- **Swift actors and the bridge do not compose cleanly.** An `actor MyCache` reached from a TurboModule method must be awaited; the method signature becomes async and resolve/reject run on the actor's executor. Do not wrap an actor with a non-async facade that uses `dispatch_semaphore_wait` — that blocks the native-modules queue for every module instance.

## Memory

- **`RCTPromiseResolveBlock` and `RCTPromiseRejectBlock` strong-capture `self` by default.** A property-held operation queue + a resolved block that references `self.state` creates a retain cycle that survives bridge teardown. Use `__weak typeof(self) weakSelf = self;` (Obj-C) or `[weak self]` (Swift) inside the resolve/reject closure, and re-strongify at the top of the block with a nil-check.
- **`RCTBridge` / `RCTCallInvoker` references are held weakly by the bridge contract.** Do not stash `self.bridge` as a strong property beyond what the auto-synthesized `@synthesize bridge = _bridge;` gives you. Holding a strong bridge reference from a module prevents bridge tear-down and leaks the entire JS runtime.
- **Obj-C delegates are `weak` — verify explicitly when bridging Swift-side delegate patterns.** `@property (nonatomic, weak) id<MyDelegate> delegate;`. Missing `weak` on a delegate that closes back to a view controller leaks the VC past dismissal — frequent pattern in camera / scanner modules.
- **Unsubscribe in `invalidate` (TurboModule) or `dealloc` (legacy).** Any `NotificationCenter.default.addObserver`, `NSNotificationCenter` Obj-C variant, KVO, or system framework observer (`AVAudioSession`, `CLLocationManager`) must be removed explicitly. Bridge reload (Metro `r`) tears down and re-creates the module; an un-removed observer fires twice after the second load.
- **Do not retain event emitter listeners beyond `stopObserving`.** If `startObserving` attaches an `AVCaptureSession` output, `stopObserving` must detach it. Holding the output across bridge reloads leaks memory linear to reload count.
- **Static `dispatch_once` singletons survive bridge reloads.** A `static dispatch_once_t t; dispatch_once(&t, ^{ ... })` inside a module method initializes once per *process*, not per bridge instance. If that singleton holds a reference to `self`, every bridge reload leaves a zombie pointing at a dead module. Use instance state, not a `dispatch_once` on the module itself.
- **Swift `Unmanaged` round-trips need balanced retains.** `Unmanaged.passRetained(obj).toOpaque()` must be matched by exactly one `takeRetainedValue()` on the consumer side. Mis-paired `takeUnretainedValue` / `passUnretained` silently double-free or leak. Use this pattern only when crossing into C/C++ Turbo Module code.

## Events & callbacks

- **Event emitters inherit `RCTEventEmitter`, override `supportedEvents`, and gate emission on `hasListeners`.** `supportedEvents` returns the exact list JS subscribes to; emitting an event not in that list is silently dropped. Reading `self.hasListeners` before `sendEvent(withName:body:)` prevents the "`Sending event with no listeners registered`" warning and saves serialization cost when nothing's listening.
- **Implement `startObserving` / `stopObserving` and wire side-effect setup there, not in `init`.** `init` runs on bridge creation; `startObserving` runs when the first JS listener subscribes. Heavy resources (CoreLocation updates, Bluetooth scan, AVCaptureSession) must start in `startObserving` and stop in `stopObserving`, or the module burns battery while no one listens.
- **Track subscriber count explicitly if multiple JS components listen.** RN's default `hasListeners` is a boolean — if two JS components subscribe and one unsubscribes, you still have a listener but get no notification. Override `addListener:` / `removeListeners:` to maintain an `NSInteger _listenerCount` and tear down only at zero.
- **Events are fire-and-forget with no delivery guarantee.** JS may not have mounted the subscriber yet when the first event fires. Buffer initial-state emissions if an event represents state the subscriber needs to resume (e.g., "current auth state"), or expose a `getCurrentState()` async method the subscriber calls on mount.
- **Event bodies must be JSON-serializable.** `NSDate *` serializes as a number via milliseconds, `NSURL *` via `absoluteString`, `NSData *` must be base64-encoded first. Raw `NSData` or a custom `@objc` class crashes the serializer.
- **Choose Promise over callback for anything request/response.** `RCTResponseSenderBlock`-style callbacks cannot be reused (one-shot) and lose stack context. Promises get JS-side `try/catch`, Sentry stack traces, and composability. Callback style is only acceptable for streaming "N events per action" patterns — and even there, an event emitter is usually cleaner.

## Security

- **Certificate pinning for RN apps belongs in a native `URLSessionDelegate`, not `global.XMLHttpRequest` monkey-patching from JS.** A JS-side pin is defeatable by any in-bundle code or a hot-reloaded patch. Implement `urlSession:didReceiveChallenge:completionHandler:` in the native module that owns the request and validate the server's SubjectPublicKeyInfo hash there.
- **Validate deep-link scheme and host in AppDelegate *before* forwarding to JS via `RCTLinkingManager`.** `- application:openURL:options:` and `- application:continueUserActivity:restorationHandler:` receive attacker-controlled input. Never hand a deep-link URL straight to a `WKWebView.loadRequest:`; forwarding to `RCTLinkingManager` without first verifying scheme + host + path lets untrusted origins trigger your JS `Linking` handlers.

## Testing

- **XCTest or Swift Testing for the native-module unit layer; mock the bridge.** Instantiate the module without a real `RCTBridge` — inject a mock `RCTCallInvoker` (new arch) or stub the bridge reference. Test the module's public `@objc` methods by calling them directly with synthetic `RCTPromiseResolveBlock` / `RCTPromiseRejectBlock` stubs that capture the (resolved, rejected) values.
- **Do not test TurboModule method dispatch end-to-end in a unit test.** The dispatcher is RN's responsibility; your test surface is the method body behind it. Contract-test the codegen spec by compiling a dummy consumer against `NativeFooSpec` — if the spec drifts, the build breaks.
- **Integration tests for bridge correctness run in a hosted RN app with Detox or Maestro.** A Swift unit test cannot exercise real JSI marshaling, event delivery, or Fabric rendering. End-to-end "JS calls native, native emits event, JS receives" flows belong in E2E.
- **Assert on the resolved/rejected code string, not the localized message.** Tests that match `[error localizedDescription]` break on locale; match on `error.code` which is the actual API.

## Accessibility

- **Fabric ComponentView must map `accessibilityLabel` / `accessibilityHint` / `accessibilityRole` from codegen props to the native view.** The codegen `Props` struct exposes them under `accessibilityProps`; apply them in `updateProps:oldProps:` via `self.accessibilityLabel = ...`, `self.accessibilityTraits = ...`. Without this, a custom Fabric component is VoiceOver-invisible.
- **Expose a native AppDelegate-level accessibility focus hook if you own navigation in native.** When a native-driven screen transition lands a new RN view, call `UIAccessibility.post(notification: .screenChanged, argument: targetView)` so VoiceOver reads the new screen's first element. Without this, VoiceOver keeps reading the old screen after a back-swipe handled in native.
- **Bridge-emitted `AccessibilityInfo` events (screen-reader enabled, bold-text enabled) must be fresh on subscribe.** When JS subscribes via `AccessibilityInfo.isScreenReaderEnabled`, the native module should emit the current state immediately — don't wait for the next `UIAccessibilityVoiceOverStatusDidChangeNotification`, or the UI renders in the wrong mode on cold start.

## References

Digested from (local clones in `references/`):

- **callstackincubator/agent-skills** — sections: Architecture, Bridge contract, New Architecture, Concurrency & threading, Memory, Events & callbacks (drew from `skills/react-native-best-practices/references/native-turbo-modules.md`, `native-threading-model.md`, `native-memory-patterns.md`, `native-memory-leaks.md`, `native-view-flattening.md`, `native-profiling.md`, `native-sdks-over-polyfills.md`, and `skills/react-native-brownfield-migration/references/bare-ios-native-integration.md`, `bare-ios-xcframework-generation.md`, `expo-ios-integration.md` for AppDelegate / brownfield wiring).
- **steipete/agent-rules** — sections: Swift / Obj-C interop, Concurrency & threading, Memory (drew from `swift6-migration-compact.md` on Sendable/actor boundaries, `nonisolated(unsafe)`, deinit isolation rules; `docs/modern-swift.md` for modern async patterns).
- **twostraws/SwiftAgents** — sections: Swift / Obj-C interop, Concurrency & threading (drew from `AGENTS.md` on avoiding GCD in favor of structured concurrency, Swift-native Foundation preferences).
- **AvdLee/SwiftUI-Agent-Skill** — sections: Accessibility (skimmed `swiftui-expert-skill/references/accessibility-patterns.md` for VoiceOver propagation principles applicable to Fabric ComponentView).
