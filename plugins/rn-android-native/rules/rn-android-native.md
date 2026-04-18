# React Native Android bridge rules

Opinionated rules for the Kotlin / Java code that participates in the React Native bridge on Android — TurboModules, legacy NativeModules, Fabric ViewManager, legacy ViewManager, MainActivity / MainApplication bridge wiring, ReactPackage registration, and the Gradle surface that affects the RN layer. Not pure Android app code, not JS/TS.

## Review behavior

Applies to any tool that reads this file via CLAUDE.md — `/pr-review-toolkit:review-pr`, `/security-review`, `/simplify`, `/code-review:code-review`, and our `/rn-android-native:review` orchestrator.

**Scope:** Only report findings for React Native Android bridge code (Kotlin/Java that participates in the RN bridge — TurboModules, legacy NativeModules, Fabric ViewManager, legacy ViewManager, MainActivity / MainApplication RN-bridge setup, Gradle changes affecting the RN layer). Ignore findings about pure Android app code (covered by the sibling `android` plugin), React Native JavaScript/TypeScript code (covered by the `rn-typescript` plugin), or iOS bridge code.

**In-scope findings (report):**
- Correctness bugs (logic errors, race conditions, crashes, data corruption)
- Security issues (insecure storage, TLS in native module, secret exposure in module resources, deep-link validation in MainActivity, PendingIntent misuse)
- Bridge-specific concerns (method signature hazards, multi-resolve of Promises, memory across the bridge, thread hopping, TurboModule / Fabric spec correctness, codegen drift, Activity leak patterns)
- Explicit rule violations from this file

**Out-of-scope (drop, do not report):**
- Pure style, whitespace, blank lines, import order, trailing commas
- Comment/KDoc formatting
- Anything a linter/formatter/compiler catches (ktlint, detekt, Android Lint, Gradle warnings)
- Pedantic naming, "could be shorter" suggestions
- Pre-existing issues on lines not in the diff
- Findings about pure Android app code, iOS bridge code, or JS/TS code
- Findings duplicated by the sibling `android` plugin's rules (Compose state, pure-app architecture)

**Confidence gate:** Report only findings you are >=80% confident are real. When in doubt, drop. Prefer false negatives over noise.

## Architecture

- **New Architecture (TurboModules + Fabric) is the baseline.** New modules and views must be TurboModules / Fabric `ViewManagerDelegate` with a codegen-backed TypeScript spec. Do not add a fresh `ReactContextBaseJavaModule` subclass or a bare `SimpleViewManager<T>` in a codebase that has already flipped `newArchEnabled=true` in `gradle.properties` — register via the generated `Native<Foo>Spec` / `ReactModuleInfoProvider` plumbing instead. If the project is still on Legacy, call that out in the PR rather than silently mixing registrations.
- **One module per class, one class per file, one `@ReactModule(name = ...)` per class.** The `name` value is the JS import key; two classes claiming the same name blow up at runtime with `NativeModule X is already registered`. Match the string exactly to the codegen spec and to `TurboModuleRegistry.getEnforcing<Spec>('Name')` on the JS side — a mismatch is a silent `null` and a JS null-pointer crash, not a compile error.
- **Register modules through a `ReactPackage` (legacy) or `TurboReactPackage` / `BaseReactPackage` (new arch).** Do not manually add modules to `getPackages()` with ad-hoc `new MyModule(reactContext)` sprinkled across `MainApplication.onCreate()` — put every module behind a `ReactPackage.createNativeModules(...)` or `getModule(name, reactContext)` entry so lazy init + ReactHost tear-down work correctly.
- **Autolinking is the default; manual `getPackages()` entries are the exception.** Prefer `PackageList(application).packages` in `MainApplication.getPackages()` and let `react-native-gradle-plugin` discover the module. Hand-registering a locally-linked package on top of autolinking double-registers it and fails at runtime.
- **`MainApplication` bridge wiring is minimal and RN-only.** Keep `SoLoader.init(...)`, `OpenSourceMergedSoMapping` / `DefaultNewArchitectureEntryPoint.load()`, and the `ReactHost` / `ReactNativeHost` factory in `onCreate`. Do not run feature bootstrapping (analytics, remote config, third-party SDK init) ahead of the bridge on the main thread — it extends TTI linearly. Hook deferred work into a `ReactInstanceEventListener` / `ReactHost.addReactInstanceEventListener` callback instead.
- **`MainActivity` must extend `ReactActivity` (or use `ReactActivityDelegate` / `DefaultReactActivityDelegate`).** Overriding `onCreate` to call `setContentView` directly bypasses Fabric-enabled delegate wiring (`fabricEnabled` + `isConcurrentReactEnabled`) and the JS root view silently falls back to Paper rendering. Override `getMainComponentName()` and `createReactActivityDelegate()` — do not create your own Activity lifecycle from scratch.
- **Do not add native dependencies inside `packages/*` that aren't listed in the app module's `build.gradle`.** Autolinking scans the app's `node_modules` at configuration time — a shared-library dep that isn't in the app's `package.json` will link on one machine and vanish on the next CI runner with a cleaner cache.

## Kotlin / Java interop at the bridge

- **Module classes must extend `ReactContextBaseJavaModule` (legacy) or the codegen-generated `Native<Foo>Spec` base (new arch).** A plain `class MyModule(private val reactContext: ReactApplicationContext)` does not get discovered. Do not "clean up" inheritance — the Obj-C-style dispatcher relies on the superclass hooks (`getName`, `invalidate`, `addListener`, etc.).
- **`@ReactMethod` must be public and non-suspending.** Kotlin `private fun` or `internal fun` is invisible to the bridge dispatcher and the method silently does not register. `suspend fun` cannot be a `@ReactMethod` either — the dispatcher does not know how to await a continuation. Take a `Promise` parameter and launch a coroutine inside.
- **Parameter types must be bridge-representable.** Use `String`, `Double`, `Boolean`, `Int`, `ReadableMap`, `ReadableArray`, `Promise`, `Callback` — not Kotlin `data class`, `sealed class`, generic types (`List<MyModel>`), or `Long`. `Long` does not cross the bridge on all JS engines and gets silently truncated — use `Double` for 64-bit numeric IDs, or pass as `String` if precision matters. Kotlin `data class` must be deconstructed into a `WritableMap` before return; the bridge does not reflect over your class.
- **Nullable primitives must be boxed.** JS can pass `null` for any argument; declaring `@ReactMethod fun foo(x: Int)` (primitive) will crash with a NullPointerException when JS passes `null`. Use `Int?` / `Double?` for optional numeric params, or require the JS spec to default them.
- **Kotlin `default parameter values` do not cross the bridge.** `@ReactMethod fun log(message: String, level: String = "info")` registers a 2-arg method; JS calling with 1 argument throws. Use `@JvmOverloads` + explicit overloads only if you also update the codegen spec, or require the arg on the JS side.
- **Companion-object `const val NAME` plus `override fun getName() = NAME`.** Making `NAME` a mutable `var` or deriving it dynamically breaks the `@ReactModule(name = ...)` / `getName()` / codegen-spec invariant — all three must return the same string, and it must be a compile-time constant so the annotation processor can read it.
- **Do not expose `enum class` directly over the bridge.** JS receives it as a string, which is fine one-way, but reading a string back into the enum must go through `enumValueOf` with a guard — an unknown JS-provided value crashes with `IllegalArgumentException`. Wrap in `runCatching { enumValueOf<MyEnum>(s) }.getOrNull()` or use a sealed mapping.
- **Returning a Kotlin `List<T>` from a codegen-typed TurboModule requires the spec to declare an array type.** If you return `List<String>` and the spec says `string[]`, codegen generates the right marshalling. If you try to return a `List<MyData>`, each element must be converted to a `WritableMap` manually — there is no reflection-based bridge.

## Bridge contract (method signatures)

- **`@ReactMethod` taking a `Promise` — call `promise.resolve(value)` or `promise.reject(code, message)` exactly once.** A second call throws `com.facebook.react.bridge.ObjectAlreadyConsumedException` and crashes the bridge. When there are multiple branches (error guards, callbacks, coroutine timeouts), gate with `AtomicBoolean` and short-circuit subsequent calls:

```kotlin
val settled = AtomicBoolean(false)
fun safeResolve(v: Any?) { if (settled.compareAndSet(false, true)) promise.resolve(v) }
fun safeReject(code: String, msg: String) { if (settled.compareAndSet(false, true)) promise.reject(code, msg) }
```

- **`promise.reject(code, message)` — the code string is the stable API.** JS callers `switch` on `error.code`. Use a small enumerated set (`"E_PERMISSION_DENIED"`, `"E_NETWORK"`, `"E_UNEXPECTED"`), defined as `const val`s on the module. Never reject with `null` code, a raw exception-class name, or a localized message as the code — that breaks downstream JS handling.
- **`WritableMap` / `WritableArray` returned from a `@ReactMethod` is consumed by the bridge.** Do not reuse them across calls or retain them as fields — after `promise.resolve(map)` the map is in an undefined state and `map.putString(...)` on it is UB. Build a fresh `Arguments.createMap()` / `Arguments.createArray()` for each call.
- **`Callback` is single-shot — invoking it twice throws.** Legacy `Callback` parameters are a one-shot fire-and-forget. If a method takes `(successCallback: Callback, errorCallback: Callback)`, invoke exactly one of the two, exactly once. Prefer `Promise` for new code; `Callback` is only acceptable for streaming "N events per call" patterns and even there an event emitter is cleaner.
- **`@ReactMethod(isBlockingSynchronousMethod = true)` runs on the JS thread and blocks every frame it holds.** Use only for trivial, memory-resident getters (constants, feature-flag reads). Anything doing disk I/O, network, lock acquisition, or UI framework calls must be async + `Promise`-returning. A synchronous method that takes more than a millisecond is visibly a dropped frame.
- **Module constants (`getConstants()` / `@ReactConstantMethod`) run synchronously during bridge init — keep them cheap.** Disk reads, `SharedPreferences.getAll()` on a large prefs file, or Keystore lookups in `getConstants()` add directly to cold-start time. Return static or memory-resident values only; defer I/O to an explicit async method the JS side calls on mount.
- **Do not pass a Kotlin lambda or `Function1` to `promise.resolve(...)`.** Only bridge-serializable types (`String`, `Double`, `Boolean`, `WritableMap`, `WritableArray`, `null`) round-trip back to JS. A lambda serializes as `null` silently. If you need a native-initiated callback, emit an event via `DeviceEventManagerModule.RCTDeviceEventEmitter`.

## New Architecture (TurboModules / Fabric / Codegen)

- **The TypeScript spec is the contract; the Kotlin `Native<Foo>Spec` base class is generated from it.** Edit `Native<Foo>.ts` first, run the codegen task (`./gradlew generateCodegenArtifactsFromSchema` or a full `assembleDebug`), then implement `override fun <method>(...)` against the refreshed base. A Kotlin impl that "works" but doesn't override a spec method will compile — the class is abstract only for spec-declared methods — but JS calls to the missing method throw at runtime.
- **Register the TurboModule via `ReactModuleInfoProvider.getReactModuleInfos()`.** Each module entry returns a `ReactModuleInfo(name, className, canOverrideExistingModule, needsEagerInit, isCxxModule, isTurboModule)`. Setting `isTurboModule = true` for a module that inherits from the legacy base (or vice versa) causes the module registry to pick the wrong dispatcher and calls silently return `undefined`.
- **`needsEagerInit = true` only when the module must be ready before JS runs.** Eager init moves module construction to the native-modules thread at bridge startup, costing TTI. Default to lazy (`false`) and let the module instantiate on first JS call. Eager init is correct for modules that emit startup events JS cannot afford to miss (crash reporter, cold-start analytics).
- **Fabric `ViewManager`: subclass the codegen-generated `<Name>ManagerDelegate` and the matching `<Name>ManagerInterface`.** The concrete `SimpleViewManager<T>` / `ViewGroupManager<T>` subclass holds `val delegate = <Name>ManagerDelegate(this)`, and all prop setters go through `@ReactProp(name = "...")`-annotated methods that the delegate dispatches into. Writing a `@ReactProp` that isn't in the codegen schema silently no-ops under Fabric — the delegate never routes to it.
- **`@ReactPropGroup` for related props (`marginLeft`, `marginTop`, …) — but only if the spec declares them grouped.** Codegen under Fabric won't route a grouped setter if the spec lists props individually, and vice versa. Keep the native prop shape aligned with the TS spec.
- **Don't mix new-arch and legacy registration for the same component.** Having both a legacy `ViewManager<T>` and a Fabric `ViewManagerDelegate` for `RNFoo` ends up registering twice and the renderer picks one non-deterministically. Delete the legacy ViewManager in the same commit as the Fabric migration.
- **C++ TurboModules skip JNI at runtime but still need JNI bindings at registration.** Keep the Kotlin wrapper minimal; heavy logic belongs in C++ accessed via JSI.
- **Regenerate and re-link when upgrading React Native.** `node_modules/react-native/ReactAndroid/build/generated/source/codegen/...` changes with every RN minor version. A codegen schema mismatch between the RN version and what the module was generated against manifests as `AbstractMethodError` at runtime — do a clean Gradle build after any RN bump.

## Concurrency & threading

- **Async `@ReactMethod` runs on the NativeModules serial queue (`mqt_v_native`), not the JS thread.** Do not hop to `Dispatchers.IO` or `Dispatchers.Default` unnecessarily — you are already off the JS thread. Hop only when (a) the work is CPU-bound and you want parallelism, or (b) you're calling a blocking Java API and need to free the native-modules queue for other modules.
- **Synchronous `@ReactMethod(isBlockingSynchronousMethod = true)` runs on the JS thread. Treat it as a critical section.** No `runBlocking`, no lock acquisition, no `View.measure()`, no `SharedPreferences.getString` on a large file — each is a visible dropped frame.
- **UI work goes through `UIManagerModule.addUIBlock { ... }` or `reactContext.runOnUiQueueThread { ... }`, not a raw `Handler(Looper.getMainLooper())`.** `addUIBlock` serializes the native mutation with the next Fabric commit so the UI change lands in the same frame as pending layout updates. A raw Handler post can interleave with a Fabric commit mid-frame and produce a one-frame flicker.
- **`reactContext.runOnJSQueueThread { ... }` / `runOnNativeModulesQueueThread { ... }` are the correct hops into RN-owned threads from a background thread.** Calling `reactContext.getJSModule(RCTDeviceEventEmitter::class.java).emit(...)` from an arbitrary coroutine context risks crashing the JSI runtime. Always hop onto the NativeModules queue (or use a `CallInvokerHolder` under new arch) before touching JS.
- **Module-scoped coroutines use `SupervisorJob() + injected dispatcher`, cancelled in `invalidate()`.** A coroutine launched from a `@ReactMethod` that outlives the module leaks the `Promise` and potentially the `ReactContext`. Pattern:

```kotlin
private val moduleJob = SupervisorJob()
private val moduleScope = CoroutineScope(ioDispatcher + moduleJob)

override fun invalidate() {
    moduleJob.cancel()
    super.invalidate()
}
```

- **Never use `GlobalScope.launch` / `runBlocking` in a module.** `GlobalScope` outlives every bridge reload and leaks the `ReactContext` captured in the closure. `runBlocking` on the native-modules queue deadlocks the queue for every module sharing it.
- **For RN view mutations from a coroutine, prefer `UIManagerModule.addUIBlock` over `withContext(Dispatchers.Main)`.** The former serializes with Fabric's next commit so the native change lands in the same frame as pending layout updates; a raw main-thread hop can interleave mid-commit and produce a one-frame flicker.
- **Do not share a `CoroutineScope` across module instances.** A bridge reload (`r` in Metro) destroys and recreates the module; a `companion object val sharedScope` survives the reload and ends up with two generations of modules racing on the same scope.

## Memory & lifecycle

- **Modules must not cache the Activity.** `reactContext.currentActivity` can return `null` (bridge exists before the Activity is attached, or after it is destroyed), and an Activity reference captured at construction goes stale on configuration change + bridge reload. Read `reactContext.currentActivity` on each method call, null-check, and reject the Promise with a stable code if it's `null`.
- **Do not store `ReactApplicationContext` in a `companion object` or a static field.** `ReactApplicationContext` wraps the application-wide bridge instance; a static reference survives bridge reload and leaks the old runtime. Stash it as a `private val` captured by the primary constructor only.
- **Register `LifecycleEventListener` for Activity-lifecycle-sensitive work, unregister in `invalidate()`.** `reactContext.addLifecycleEventListener(this)` gives you `onHostResume` / `onHostPause` / `onHostDestroy` — use these for starting/stopping background work (location updates, camera session, Bluetooth scan) tied to foreground state. Failing to call `removeLifecycleEventListener(this)` in `invalidate()` leaks the module and everything it captures across bridge reloads.
- **Override `invalidate()` / `onCatalystInstanceDestroy()` and call `super`.** In RN 0.74+ use `invalidate()`; in older versions use `onCatalystInstanceDestroy()`. This is the hook for cancelling coroutine scopes, detaching `BroadcastReceiver`s, closing file descriptors, releasing `MediaPlayer` / `Camera2` handles. Bridge reload (Metro `r`) calls this — an un-cleaned observer fires twice after the second load.
- **`BroadcastReceiver`s registered via `reactContext.registerReceiver(...)` must be unregistered in `invalidate()`.** `reactContext.unregisterReceiver(receiver)` wrapped in a `runCatching { }` (receiver may already be detached on a non-orderly teardown). An un-unregistered receiver leaks the module plus the `ReactContext`.
- **Use `WeakReference<ReactApplicationContext>` only when a native listener outlives the module** (e.g. a singleton SDK callback that you can't unregister). The normal pattern is: own the lifecycle yourself via `invalidate()`. `WeakReference` is a workaround for SDKs with bad lifecycle APIs.
- **Do not emit events from `invalidate()`.** The JS runtime may already be torn down; `getJSModule(RCTDeviceEventEmitter::class.java).emit(...)` crashes or is silently dropped. `invalidate()` is the symmetric counterpart of `initialize()` — it cancels, it does not notify.
- **Closure capture of `this` from a `Promise` resolver survives into the native-modules queue.** A `moduleScope.launch { ... promise.resolve(doWork(this@MyModule.state)) }` holds `this` until the coroutine completes, which prevents `invalidate()` from freeing the module if the coroutine is stuck. Always cancel `moduleScope` in `invalidate()` so pending promises unwind.

## Events & callbacks

- **Event emission: `reactContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java).emit(eventName, params)`.** Gate on `reactContext.hasActiveReactInstance()` (new arch: `reactContext.hasActiveCatalystInstance()` on older RN) — calling `getJSModule` after bridge destroy crashes with `IllegalStateException: Tried to get JS module ... before CatalystInstance was set up`.
- **Override `addListener(eventName: String)` and `removeListeners(count: Int)` on TurboModules that emit events.** The new-arch TurboModule spec requires them; JS's `NativeEventEmitter` calls them to let the module know someone is listening. Maintain an `AtomicInteger listenerCount` and start/stop any expensive backing resource (location client, Bluetooth scan, `ContentObserver`) at the 0↔1 transition — don't keep the sensor running while nobody subscribes.
- **Hop onto the NativeModules queue or the JS queue before `emit()`.** Emitting from an arbitrary coroutine dispatcher (`Dispatchers.IO`, a library's callback thread) corrupts JSI runtime state and crashes inconsistently under new arch. Use `reactContext.runOnJSQueueThread { emitter.emit(...) }` or hop via `withContext(Dispatchers.Main)` + `UIManagerModule.addUIBlock` when the event is synchronized with a UI change.
- **Event body must be bridge-serializable.** `WritableMap` / `WritableArray` / primitives only — no Kotlin `data class`, no `Parcelable`, no `JSONObject`. A raw object silently serializes as `null` on some RN versions and throws on others.
- **Event names must match the JS-side spec.** Under Fabric with codegen, the spec enumerates supported events; emitting an event name the spec doesn't declare is silently dropped by the new arch event emitter. Keep the list in a `const val` companion-object constant and reference it from both the codegen spec and the emit site.
- **Events are fire-and-forget with no delivery guarantee.** JS may not have subscribed yet when the first event fires (common pattern on cold start: native module initialized before JS root component mounted). For events representing state (auth, connectivity), also expose a synchronous `getCurrentState()` `@ReactMethod` so JS can pull on mount rather than rely on the first emit.
- **Prefer `Promise` over `Callback`-based events for request/response.** `Callback` loses stack context, can't be reused, and its fire-and-forget semantics hide errors. Use Promise for request/response, event emitter for streaming.

## Security

- **Validate deep-link `Intent` extras in `MainActivity.onNewIntent` / `onCreate` *before* forwarding to JS.** Deep links hit `MainActivity` with attacker-controlled `Uri` data. Check scheme equals what you own, host matches an allowed set, path conforms to an expected route, and numeric IDs parse cleanly. Never hand a raw deep-link `Uri` to JS via a `Linking` event without validation — JS-side `Linking.addEventListener` handlers frequently trust the input and navigate straight to it.
- **`BuildConfig` constants in a bridge module end up inline in the APK and extractable by anyone with `apktool`.** A `buildConfigField("String", "API_KEY", ...)` in the RN app module is not a secret. Fetch native-only secrets through a `@ReactMethod` behind auth at runtime rather than exposing them at build time; JS bundling makes the exposure worse since any hot-reload snapshot captures them too.
- **Certificate pinning for requests originating in a native module uses OkHttp `CertificatePinner`, not JS `fetch` monkey-patching.** JS-side pinning is defeatable by any bundled library or hot-reloaded patch. Implement pinning in the `OkHttpClient` the module owns, pin to the SPKI hash, and expose only the module's method — never hand the `OkHttpClient` to JS.
- **Input validation on every bridge boundary.** `ReadableMap.getString(key)` returns attacker-controlled content; treat every field as untrusted before using it in a file path (path traversal), SQL (injection), shell command (command injection), `WebView.loadUrl` (XSS), or `Intent` (implicit intent hijack). The JS-side type signature is a suggestion, not a guarantee — JS callers can be compromised.
- **Module methods that expose filesystem paths must not return absolute internal-storage paths to JS.** Returning `/data/data/com.app/...` invites JS-side code to hardcode paths that break on the next Android storage-model change. Return relative paths keyed to a known base and expose a separate method to resolve them, or use `content://` URIs via `FileProvider`.

## Testing

- **JVM unit tests for module logic — mock `ReactApplicationContext` / `ReactContext` and inject a test `Promise`.** Instantiate the module with a Mockito or MockK mock of `ReactApplicationContext`, stub `getSystemService` / `currentActivity` as needed, and call `@ReactMethod`s directly with a test `Promise` impl that captures `(resolve, reject)` calls:

```kotlin
class TestPromise : Promise {
    var resolved: Any? = null; var rejectCode: String? = null
    override fun resolve(v: Any?) { resolved = v }
    override fun reject(code: String, msg: String?) { rejectCode = code }
    // ... other overrides delegating to the captured fields
}
```

- **Assert on the reject code, not the message.** `assertEquals("E_PERMISSION_DENIED", promise.rejectCode)` — messages may be localized or tweaked; the code is the stable API.
- **Use Robolectric when the module touches framework types** (`Uri`, `Context`, `PackageManager`, `SharedPreferences`). A pure-JVM unit test that touches `Uri.parse` throws because `Uri` is an Android stub on the JVM. Robolectric's JVM shadow lets the test run without a device.
- **Instrumented tests (`src/androidTest`) for real Fabric rendering and event round-trip.** A Kotlin unit test cannot exercise real JSI marshaling, event delivery through the JS runtime, or Fabric `ViewManagerDelegate` dispatch. End-to-end "JS calls native, native emits event, JS receives" belongs in an instrumented test running on an emulator with an RN host app — or in Detox/Maestro for the highest-fidelity case.
- **Contract-test codegen specs by compiling a dummy consumer.** If the TS spec drifts and the Kotlin implementation no longer satisfies the generated `Native<Foo>Spec` (e.g. abstract method not overridden), the build should break. Don't suppress the error with a stub — fix the impl or the spec.
- **Do not test the TurboModule dispatcher itself.** The registry, marshalling, and method resolution are RN's responsibility; your test surface is the method body. Pointing tests at `TurboModuleRegistry` couples the tests to RN internals that change across versions.

## Accessibility

- **Fabric `ViewManagerDelegate`: accessibility props arrive as codegen-typed props.** `accessibilityLabel`, `accessibilityHint`, `accessibilityRole`, `accessibilityState`, `accessibilityLiveRegion` come through the generated `setAccessibilityLabel(view, value)` etc. Implement each `@ReactProp(name = "accessibility...")` setter to forward to the native `View` (`view.contentDescription = value`, `ViewCompat.setAccessibilityLiveRegion(view, ...)`). Without this, a custom Fabric component is TalkBack-invisible.
- **`contentDescription` for decorative vs actionable views.** For a custom `View` that exposes a click handler to JS, a non-null `contentDescription` is required — TalkBack reads it as the action's label. For purely decorative children of a labelled parent, set `importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO` so TalkBack skips them rather than reading a confusing fragment.
- **Custom `@ReactProp` setters for text size must treat the value as `sp`, not `px`.** Fabric's built-in `<Text>` applies `fontScale` automatically, but a custom ViewManager that sets `view.textSize = value` (px) ignores it. Convert via `TypedValue.applyDimension(COMPLEX_UNIT_SP, size, resources.displayMetrics)` and re-apply on `onConfigurationChanged`.
- **Emit `AccessibilityManager` state-change events to JS.** Android exposes `AccessibilityManager.TouchExplorationStateChangeListener` (screen reader enabled) and similar listeners for enabled accessibility services. A bridge that wraps `AccessibilityInfo.isScreenReaderEnabled` for JS must both (a) emit the current state on subscribe (not wait for the next change) and (b) forward subsequent changes via `DeviceEventEmitter`. Without the initial emit, JS renders in the wrong mode on cold start.
- **Don't override `View.performAccessibilityAction` without calling `super`.** A custom ViewManager that handles a custom gesture via `performAccessibilityAction(ACTION_CLICK, ...)` must still delegate to `super.performAccessibilityAction(...)` so TalkBack's built-in actions (scroll, dismiss) keep working.

## References

Digested from (local clones in `references/`):

- **callstackincubator/agent-skills** — sections: Architecture, Bridge contract, New Architecture, Concurrency & threading, Memory & lifecycle, Events & callbacks, Testing (drew from `skills/react-native-best-practices/references/native-turbo-modules.md` for the Kotlin module + `invalidate()` + `moduleScope.cancel()` pattern, `native-threading-model.md` for the NativeModules / JS / Main thread matrix and Android eager-init `ReactModuleInfo` flags, `native-memory-leaks.md` and `native-memory-patterns.md` for `WeakReference` + listener-removal patterns, `native-view-flattening.md` for Fabric child-count hazards in custom ViewManagers, `bundle-r8-android.md` for R8 / DoNotStrip proguard rules, `native-android-16kb-alignment.md` for release-build SO alignment, and `skills/react-native-brownfield-migration/references/bare-android-native-integration.md`, `bare-android-aar-generation.md`, `expo-android-integration.md` for `MainApplication` / `ReactNativeHostManager` / autolinking wiring).
- **Kotlin/kotlin-agent-skills** — sections: Kotlin / Java interop at the bridge, Bridge contract, Testing (drew from `skills/kotlin-tooling-java-to-kotlin/references/CONVERSION-METHODOLOGY.md` and `KNOWN-ISSUES.md` for platform-type nullability, `@JvmStatic` / `@JvmField` / `@JvmOverloads` visibility across the Java-discovered RN dispatcher, backtick-escaped keywords; `frameworks/DAGGER-HILT.md` for `@Inject` constructor visibility and module injection patterns applicable to dispatcher injection; `skills/kotlin-tooling-agp9-migration/references/KNOWN-ISSUES.md` informed the R8 / ProGuard and secrets-not-in-BuildConfig rules).
- **android/nowinandroid** — sections: Concurrency & threading, Memory & lifecycle, Security (drew from `core/common/src/main/kotlin/.../NiaDispatchers.kt` + `di/CoroutineScopesModule.kt` for the `@Dispatcher(IO) CoroutineDispatcher` qualifier pattern applied to RN module injection, `app/src/main/kotlin/.../MainActivity.kt` for the `repeatOnLifecycle` + `lifecycleScope` pattern that informs the `LifecycleEventListener` rule at the bridge boundary, `core/notifications/src/main/kotlin/.../SystemTrayNotifier.kt` for the `FLAG_IMMUTABLE or FLAG_UPDATE_CURRENT` `PendingIntent` rule and deep-link URI construction discipline).
