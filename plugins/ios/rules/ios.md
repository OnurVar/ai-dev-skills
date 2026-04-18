# iOS rules

Opinionated rules for Swift/SwiftUI/UIKit code targeting modern Apple platforms (iOS 17+, Swift 6 strict concurrency).

## Review behavior

Applies to any tool that reads this file via CLAUDE.md — `/pr-review-toolkit:review-pr`, `/security-review`, `/simplify`, `/code-review:code-review`, and our `/ios:review` orchestrator.

**Scope:** Only report findings for iOS native code (Swift, SwiftUI, UIKit, Obj-C bridging). Ignore findings about other languages/frameworks not in the current diff.

**In-scope findings (report):**
- Correctness bugs (logic errors, race conditions, crashes, data corruption)
- Security issues (Keychain misuse, insecure transport, secret exposure, input-validation gaps)
- iOS-specific concerns (concurrency, memory, lifecycle, state management, accessibility regressions)
- Explicit rule violations from this file

**Out-of-scope (drop, do not report):**
- Pure style, whitespace, blank lines, import order, trailing commas
- Comment/docstring formatting
- Anything a linter/formatter/compiler catches (SwiftLint, SwiftFormat, Xcode warnings)
- Pedantic naming, "could be shorter" suggestions
- Pre-existing issues on lines not in the diff
- Findings about other languages/frameworks not in this diff

**Confidence gate:** Report only findings you are ≥80% confident are real. When in doubt, drop. Prefer false negatives over noise.

## Architecture

- **SwiftUI is the default** for all new screens. Introduce `UIViewRepresentable`/`UIViewControllerRepresentable` only when SwiftUI lacks the required API (e.g., `MKMapView`, `AVPlayerViewController`, complex text input). Do not wrap a UIKit control when a SwiftUI equivalent exists.
- **Do not create a ViewModel per view.** Use `@State` + `@Observable` for local state. Extract a separate `@Observable` type only when logic is shared across views, is async-heavy, or needs direct unit testing. Avoid porting MVVM/VIPER/Coordinator layering from other platforms.
- **State ownership: one source of truth.** The view that creates a value uses `@State private`; children receive `let` for read-only, `@Binding` when they write, or `@Bindable` for injected `@Observable` instances. Never declare a value received from a parent as `@State` or `@StateObject` — it will ignore parent updates.
- **Inject cross-cutting dependencies via `@Environment`**, not singletons. Define custom values with the `@Entry` macro. Do not read frequently-changing values (timers, scroll offsets) from the environment — every reader gets invalidated on change.
- **Organize by feature, not by type.** Avoid top-level `Views/`, `Models/`, `ViewModels/` folders. Keep each feature's view, model, and tests colocated. One top-level type per file.
- **Do not introduce third-party dependencies** (SwiftPM, CocoaPods) without justification.

## Swift language

- **No force-unwraps (`!`) or force-try (`try!`)** on data that can fail at runtime — user input, network payloads, file I/O, JSON decoding, keychain reads. Acceptable only for programmer-error invariants (`IBOutlet`s, resource-bundle assets known to exist, preconditions a crash would correctly surface).
- **Prefer value types.** Use `struct` and `enum` by default. Reach for `class` only for reference semantics, `@Observable` state, identity-based equality, or Obj-C/UIKit interop.
- **Use Swift error handling via `throws`/`Result`**, not `NSError` round-trips or sentinel return values. Always propagate with `try`; catch at a layer that can act on the error (UI surface, retry boundary), not in the middle of a pipeline that swallows it.
- **Modern Foundation only.** Use `URL.documentsDirectory` + `appending(path:)`, not `FileManager` string paths. Use `date.formatted(date: .abbreviated, time: .shortened)` and other `FormatStyle` APIs — never `DateFormatter`, `NumberFormatter`, `MeasurementFormatter`, or `String(format: "%.2f", …)`.
- **Native Swift string APIs** over Foundation bridges: `replacing(_:with:)`, `localizedStandardContains(_:)` for user-input filtering (handles case/diacritics). Avoid `contains()` for case-insensitive search of user text.
- **Use `async`/`await`** when both a callback and an async variant exist. Do not wrap modern async APIs in new `withCheckedContinuation` calls unless bridging a truly callback-only API.

## SwiftUI

- **`@State` properties are always `private`.** Same for `@StateObject`, `@FocusState`, `@ScaledMetric`. Anything not private leaks into the generated initializer and can silently accept passed values that are then ignored.
- **Prefer `@Observable` over `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject`.** New code must use `@Observable` with `@State` (owner) and `@Bindable`/`@Environment` (injection). Touch legacy `ObservableObject` code only when migrating would balloon the diff.
- **Mark `@Observable` classes `@MainActor`** unless the module opts into MainActor default isolation. Property wrappers (`@AppStorage`, `@SceneStorage`, `@Query`) inside `@Observable` classes must be prefixed with `@ObservationIgnored` — omitting it is a compile error.
- **`ForEach` requires stable identity.** Use `Identifiable` or `id: \.someStableProperty`. Never use `id: \.self` for reference types or `id: \.indices` for dynamic collections (causes crashes on deletion). The ID must be globally unique — a derived `id: String { url.absoluteString }` fails the moment two items share a URL.
- **No inline filtering/sorting in `ForEach`, `List`, or `body`.** Pre-compute in `.onChange`, `init`, or a computed property in the model. `body` can run many times per layout pass; heavy work there tanks scroll performance.
- **Extract subviews as `struct`s, not `@ViewBuilder` functions or computed properties**, once a section depends on distinct state, is non-trivial, or needs diffing to skip. SwiftUI cannot skip a `@ViewBuilder` function's body when its inputs are unchanged, but it can skip a subview struct's `body`.
- **Use `Button` for tappable elements**, not `onTapGesture`. `onTapGesture` is reserved for cases that need tap location or tap count; everything else loses accessibility traits, focus, and hit-testing for free.
- **Navigation uses `NavigationStack` + `navigationDestination(for:)`.** `NavigationView` and `NavigationLink(destination:)` are deprecated patterns. For multiple sheets, use a single `@State` enum with `.sheet(item:)` rather than N booleans.
- **Sheets dismiss themselves** via `@Environment(\.dismiss)`. Do not pass `onSave`/`onCancel` callbacks down from the parent — it's prop-drilling that prevents reuse.
- **Avoid `AnyView`.** Use `@ViewBuilder` or `Group` for conditional branches. `AnyView` erases type info SwiftUI uses for diffing.
- **Prefer modifier-value changes over conditional inclusion** when you're representing two states of the same view (`.opacity(x ? 1 : 0)`, `.foregroundStyle(isError ? .red : .primary)`). Conditional `if`/`else` branches destroy view identity and break animations.
- **Never read screen size from `UIScreen.main.bounds`.** Use `GeometryReader`, `containerRelativeFrame`, `visualEffect`, or `ScrollView` geometry APIs. `UIScreen.main` is also deprecated on iPad/multi-scene.
- **Always provide `#available` fallbacks** for iOS 17+/18+/26+ APIs unless the deployment target already guarantees them.

## UIKit (legacy surface)

- **Do not introduce new UIKit screens.** Use UIKit only for (a) maintaining existing UIKit-first code, (b) APIs SwiftUI does not wrap cleanly (camera pipelines, custom collection layouts, complex gesture arbitration), or (c) integrating SDK components shipped as UIKit.
- **Bridge via `UIViewRepresentable`/`UIViewControllerRepresentable`.** `makeUIView` runs once; `updateUIView` runs on every SwiftUI redraw — keep it idempotent and compare inputs before applying heavy work (tile downloads, animations, reloads). Do not allocate inside `updateUIView` on the hot path.
- **Use a `Coordinator`** for delegate callbacks, and avoid capturing the representable struct itself (it's recreated on every redraw). `UIViewController`-backed representables own their lifecycle; do not re-instantiate the VC on updates.

## Concurrency

- **Swift 6 strict concurrency is the baseline.** Keep modules on `StrictConcurrency` at minimum. Diagnose data-race warnings — do not silence with `@unchecked Sendable` or `nonisolated(unsafe)` unless the invariant is documented and genuinely protected externally.
- **`async`/`await` over `DispatchQueue.main.async` or GCD.** Do not introduce new `DispatchQueue`/`OperationQueue` usage. Convert existing GCD code opportunistically when touching it.
- **UI work belongs on `@MainActor`.** Mark view-adjacent types (`@Observable` view models, presentation logic) `@MainActor`. Do not hop to main with `Task { @MainActor in … }` inside every call site — isolate the type once.
- **Actor state is non-atomic across `await`.** Any `await` inside an actor method is a suspension point; re-read state after suspension rather than trusting values read before. Do not hold an actor's mutable state across an `await` and assume it's unchanged.
- **`.task { … }` for lifecycle-scoped async work.** It auto-cancels on view disappearance. Bare `Task { … }` inside `body` or `onAppear` leaks work past view teardown — use `.task` or store the handle and cancel in `onDisappear`.
- **Handle cancellation.** Long loops and network calls must check `Task.checkCancellation()` or observe `Task.isCancelled`. Propagate `CancellationError` rather than swallowing it.
- **Closures passed to `Shape.path(in:)`, `visualEffect`, `Layout` methods, and `onGeometryChange` may run off the main thread.** They must be `Sendable` and must capture `@MainActor` state by value (capture list), not via `self`.
- **Sendable conformance is explicit for public types.** Non-public value types of all-`Sendable` properties are implicitly `Sendable` within the module, but become non-`Sendable` to callers once made `public`. Add `: Sendable` explicitly on public types that must cross isolation.
- **Never extend the lifetime of `self` from `deinit`.** `deinit` is non-isolated; capture any actor-isolated values you need in the `Task` capture list before awaiting.
- **Limit concurrency with `TaskGroup`** for fan-out work (downloads, parallel decoding). Do not spawn thousands of top-level `Task`s.

## Memory

- **Closure capture lists are mandatory** for any closure stored past the current scope (completion handlers, `Task {}`, `Combine` sinks, `NotificationCenter` observers). Use `[weak self]` when the closure is owned by `self` or a child of `self`; `[unowned self]` only when you can prove `self` outlives the closure.
- **`Task { … }` captures `self` strongly by default.** Either `[weak self]` or ensure the task is short-lived and tied to a view via `.task`. A long-running `Task` held on a `@Observable` singleton is a retain cycle.
- **UIKit delegates are `weak` by default; verify on bridging types.** When bridging an Obj-C delegate pattern to Swift, declare the property `weak var delegate: … ?`. Missing `weak` on a delegate is almost always a leak.
- **`NotificationCenter` observers are strong.** Use the token-returning `addObserver(forName:object:queue:using:)` variant and remove in `deinit`, or prefer `NotificationCenter.default.notifications(named:).stream` with `.task { for await … in }` for lifecycle-scoped observation.
- **`Timer` retains its target.** Always capture `[weak self]` in block-based timers and invalidate explicitly when no longer needed.

## Security

- **Secrets never land in `UserDefaults`.** Tokens, passwords, OAuth refresh credentials, API keys tied to a user — all go in Keychain with an access class at least as strict as `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Prefer `.whenUnlockedThisDeviceOnly` for high-sensitivity values. Never use `...Always` access classes.
- **No secrets in source control or Info.plist.** Build-time configuration for non-sensitive constants is fine; anything sensitive (signing keys, third-party API keys) must come from an ignored `.xcconfig` or runtime source.
- **App Transport Security stays on.** No `NSAllowsArbitraryLoads = YES` in `Info.plist`. Exceptions must be per-host, justified, and time-bounded.
- **Certificate pinning** for high-value endpoints (auth, payments, PHI) — pin via `URLSessionDelegate` `urlSession(_:didReceive:completionHandler:)` validating the server's public-key hash. Do not rely on hostname alone.
- **Validate all URL-scheme and universal-link inputs.** Deep-link handlers must treat parameters as untrusted: length-check, whitelist paths, and never execute string-typed navigation without a match against a known `enum Route`. Never open a URL from a deep-link payload without scheme validation (`https` only).
- **Pasteboard is sensitive.** Do not copy credentials, OTPs, or PII to `UIPasteboard.general`. If you must, set `localOnly: true` and/or `expirationDate:` when copying short-lived secrets (iOS 10+).
- **Webviews default to hardened config.** `WKWebView` instances must disable JavaScript (`preferences.javaScriptEnabled = false` or via `WKWebpagePreferences`) when rendering untrusted HTML. Never expose native capabilities via `WKScriptMessageHandler` to content loaded from arbitrary URLs.
- **Validate input at trust boundaries.** Any JSON decoded from the network must be treated as untrusted until validated — bounds-check counts, lengths, and enum cases. Use `Decodable` with explicit `CodingKeys` and reject unknown enum values via `init(from:)` rather than `@unknown default` in switches.
- **Privacy manifests and permission prompts are load-bearing.** Any new API using location, photos, contacts, Bluetooth, local network, tracking, or microphone requires a corresponding `NSUsage*Description` with a human-readable reason. Missing strings crash the app at runtime on first call.
- **Do not log PII, tokens, or request bodies.** `os_log` with `%{public}s` on sensitive fields leaks to Console.app and sysdiagnose. Use `%{private}s` or redact before logging.

## Testing

- **Use Swift Testing (`@Test`, `#expect`, `#require`) for new tests** on iOS 16+; XCTest remains for legacy and for `XCUITest`. Don't port wholesale — add new tests in Swift Testing, keep existing XCTest.
- **Test business logic in isolation.** Extract logic into `@Observable` types or plain structs that can be instantiated without a view hierarchy. Views get SwiftUI Previews; models get unit tests.
- **Async tests use `async`/`await` directly.** Do not use `XCTestExpectation` + `wait(for:timeout:)` for code that has an async API — just `await` the call. Expectations remain valid for delegate-driven or notification-driven flows.
- **Mock at protocol boundaries** (networking, persistence, auth), not via method swizzling. Define a narrow protocol the production type conforms to; inject the protocol. Do not use `OCMock`-style partial mocks.
- **Snapshot tests are brittle without deterministic input.** When using `swift-snapshot-testing` or similar, fix `Date`, `UUID`, `Locale`, `TimeZone`, and Dynamic Type category; run on a single simulator model. A snapshot diff on CI that only reproduces on one machine is a red flag.
- **Never test SwiftUI views via `UIHostingController` + assertions on subview trees.** Use ViewInspector sparingly; prefer testing the `@Observable` model driving the view, plus a SwiftUI Preview for visual regression.
- **Tests must not hit production networks.** Use `URLProtocol` stubs or a fake `URLSession` conforming to a protocol. A test that occasionally fails because of a real API is a test that will be deleted.

## Accessibility

- **Dynamic Type is non-negotiable.** Use `.font(.body)`, `.font(.title2)`, and the other semantic styles. Custom fonts must use `Font.custom(_:size:relativeTo:)`. Hard-coded `.system(size: 17)` breaks accessibility at large content sizes.
- **Use `@ScaledMetric` for sizes tied to text** (avatar diameters, icon sizes, spacing next to scalable text). Static `.frame(width: 44, height: 44)` tap targets are fine; decorative sizing near text is not.
- **Minimum tap target is 44x44 points.** Buttons smaller than that fail HIG and are hard to hit for motor-impaired users. Use `.contentShape(Rectangle())` to expand hit regions on small visual elements.
- **VoiceOver labels for icon-only controls.** `Button(action: delete) { Image(systemName: "trash") }` needs `.accessibilityLabel("Delete")`. Icon buttons without text labels and without accessibility labels are VoiceOver-invisible.
- **Group related elements with `.accessibilityElement(children: .combine)`** so VoiceOver reads a row as one element, not three separate ones. Use `.ignore` + manual `.accessibilityLabel` when the default read order is wrong.
- **Decorative images must be hidden from the accessibility tree.** Use `Image(decorative:)` for assets; use `.accessibilityHidden(true)` on SF Symbols that only illustrate.
- **Color is never the only signal.** A red error state needs an icon or text, not just a red tint — Color Differentiate Without Color and low-vision users depend on this.

## References

Digested from (local clones in `references/`):
- steipete/agent-rules — sections: Architecture, Swift language, SwiftUI, Concurrency, Memory, Testing (drew from `docs/modern-swift.md`, `swift6-migration-compact.md`, `project-rules/modern-swift.mdc`, `project-rules/pr-review.mdc`).
- twostraws/SwiftAgents — sections: Swift language, SwiftUI, Architecture (drew from `AGENTS.md` — iOS 26/Swift 6.2 API preferences, modern Foundation, `@Observable` + `@MainActor`, `FormatStyle`, navigation APIs, Localizable.xcstrings discipline).
- AvdLee/SwiftUI-Agent-Skill — sections: SwiftUI, Architecture, Memory, Testing, Accessibility (drew from `swiftui-expert-skill/SKILL.md` correctness checklist and `references/state-management.md`, `performance-patterns.md`, `view-structure.md`, `list-patterns.md`, `sheet-navigation-patterns.md`, `image-optimization.md`, `accessibility-patterns.md`, `layout-best-practices.md`, `scroll-patterns.md`).
