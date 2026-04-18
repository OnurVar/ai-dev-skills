# Android rules

Native Android in Kotlin with Jetpack Compose as the primary UI, optional legacy View interop, targeting `minSdk 24+` and a current `compileSdk`/`targetSdk` (36 at time of writing).

## Review behavior

Applies to any tool that reads this file via CLAUDE.md — `/pr-review-toolkit:review-pr`, `/security-review`, `/simplify`, `/code-review:code-review`, and our `/android:review` orchestrator.

**Scope:** Only report findings for Android native code (Kotlin, Java, Jetpack Compose, XML layouts, Gradle build-logic in the diff). Ignore findings about other languages/frameworks not in the current diff.

**In-scope findings (report):**
- Correctness bugs (logic errors, race conditions, crashes, data corruption)
- Security issues (insecure storage, TLS, secret exposure, input-validation gaps, PendingIntent misuse)
- Android-specific concerns (lifecycle, leaks, coroutines, Compose recomposition, process death, configuration changes, accessibility regressions)
- Explicit rule violations from this file

**Out-of-scope (drop, do not report):**
- Pure style, whitespace, blank lines, import order, trailing commas
- Comment/KDoc formatting
- Anything a linter/formatter/compiler catches (ktlint, detekt, Android Lint, Gradle warnings)
- Pedantic naming, "could be shorter" suggestions
- Pre-existing issues on lines not in the diff
- Findings about other languages/frameworks not in this diff

**Confidence gate:** Report only findings you are >=80% confident are real. When in doubt, drop. Prefer false negatives over noise.

## Architecture

- Single-activity app. `MainActivity` is the only `Activity`; every screen is a composable reached through a `NavHost`. New code does not add Activities or Fragments without a concrete reason (IPC surface, `launchMode` requirements, third-party SDK that demands an Activity). When you do add one, justify it in the PR description.
- Three layers — UI, domain (optional), data. UI (`@Composable` + `ViewModel`) talks to domain use-cases or to repositories directly; repositories talk to data sources (Room, DataStore, Retrofit). Never let a `@Composable` or `ViewModel` touch Retrofit / Room / DataStore directly.
- Unidirectional data flow. Events go down (lambdas passed into composables and called back into the `ViewModel`), state goes up (`StateFlow<UiState>` exposed by the `ViewModel`). Do not mutate shared state from inside a composable.
- Offline-first where the app has a remote. Local store (Room/DataStore) is the single source of truth for reads; network writes to local, and local emits to UI. Do not read from `Retrofit` directly in a repository flow path that the UI observes.
- Repositories expose reads as cold `Flow<T>` and writes as `suspend fun`. No snapshot getters (`fun getFoo(): Foo`) that race with the underlying store.
- Modules: `:app` (wiring + `MainActivity`), `:feature:<name>:api` (navigation keys + public contracts) and `:feature:<name>:impl` (screens, `ViewModel`s, feature-local data), `:core:<name>` (`designsystem`, `ui`, `data`, `database`, `datastore`, `network`, `model`, `common`, `testing`). `:feature:*:impl` may depend on other features' `:api` only — never on another feature's `:impl`. `:core:*` never depends on `:feature:*` or `:app`.
- Dependency injection is Hilt. Use `@HiltAndroidApp` on `Application`, `@AndroidEntryPoint` on Activity, `@HiltViewModel` + `@Inject constructor` on `ViewModel`, `@Module @InstallIn(SingletonComponent::class)` for bindings. Do not use service locators, `object Singletons { ... }`, or hand-rolled factories for new code. `@Binds` for interface -> impl, `@Provides` only when construction requires logic.
- Navigation is Jetpack Navigation Compose with type-safe routes (`@Serializable` data classes or sealed keys). Do not pass serialized JSON through string args, and do not hand-pack values into `savedStateHandle` when a typed route will do it.

## Kotlin language

- Null safety is non-negotiable. Do not use `!!` in production code unless you can explain in a comment why the value is impossible to be null at that point. Prefer `requireNotNull(x) { "descriptive message" }` or `checkNotNull(x)` when you want a fast-fail.
- `lateinit var` is allowed only for (a) `@Inject` field injection in Android entry points (`Activity`, `Fragment`, `Worker`), or (b) `@Before`-initialized test fixtures. Business logic classes take dependencies through the constructor.
- Data classes are for values, not behavior. Keep them in `:core:model` or feature-local `data` packages, and mark their properties `val`. If you find yourself adding methods that mutate or run side-effects, it is not a data class.
- Model UI state with a `sealed interface` (`Loading`, `Error`, `Success(data)`) plus `data object` for stateless variants. Exhaustive `when` on a sealed UI state is required; no `else ->` catch-all that hides future additions.
- `operator fun invoke` belongs on use-cases (`class GetFooUseCase @Inject constructor(...) { operator fun invoke(id: String): Flow<Foo> = ... }`) and nothing else — no clever operator overloads on domain classes.
- Suspension discipline: a `suspend fun` must be main-safe (either itself dispatches via `withContext(dispatcher)` or is trivially pure). A repository's `suspend fun` that does disk/network work must `withContext(@Dispatcher(IO) dispatcher)`. Do not switch dispatchers inside a `ViewModel` — that is the repository's job.
- Never call `runBlocking` on Android outside tests. Never call `GlobalScope.launch` / `GlobalScope.async`. Use `viewModelScope`, `lifecycleScope`, a `CoroutineWorker`, or an injected `@ApplicationScope CoroutineScope` that is `SupervisorJob() + Dispatchers.Default`.

## Jetpack Compose

- State hoisting: a composable is stateless by default. State lives in the `ViewModel` (or in a state holder for pure-UI state like scroll position). Accept state as parameters, emit changes via lambda parameters (`onFooChanged: (Foo) -> Unit`). Never reach into a `ViewModel` from a deeply nested composable; pass what you need down.
- `collectAsStateWithLifecycle()`, not `collectAsState()`. Bare `collectAsState` keeps collecting while the app is backgrounded, wastes battery, and mishandles reconnects. The only exception is a composable that runs in a non-Android preview/test harness where the lifecycle-aware version won't work.
- `StateFlow` for UI state. `SharedFlow(replay = 0, extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)` (or equivalent) for one-shot events (navigation, snackbars). Do not fire events through `StateFlow` — replaying the last event on process restore will re-trigger navigation. `LiveData` only when interop with legacy XML requires it — new code is `StateFlow`.
- `WhileSubscribed(5_000)` is the default for `stateIn` in a `ViewModel`. It keeps the upstream alive for 5 seconds after the last collector so configuration changes do not cause a re-subscription storm, but drops it for real backgrounding.
- `remember` for state that survives recomposition but may be lost on configuration change. `rememberSaveable` for state that must survive configuration change and low-memory process death: text input, scroll position within a screen, selected tab, form drafts. Primitive types and `@Parcelize` types work directly; for everything else provide a `Saver`.
- Use `derivedStateOf { ... }` when a composable reads a frequently changing state but only a derived boolean/threshold actually changes what is drawn (e.g. `firstVisibleItemIndex > 0`). Do not wrap every transformation in `derivedStateOf` — it is for reducing recomposition, not for general memoization; use `remember(key) { ... }` for that.
- Side effects have dedicated APIs. `LaunchedEffect(key)` for suspending work tied to composition, `DisposableEffect(key) { onDispose { ... } }` for setup/teardown of listeners, `SideEffect { ... }` for pushing Compose state to non-Compose code, `rememberCoroutineScope()` for a scope you launch from event callbacks. Do not call `viewModelScope.launch { ... }` from inside a composable body — use a callback that the `ViewModel` exposes.
- `key` parameter on effects is not optional. `LaunchedEffect(Unit)` is allowed only when the effect should run exactly once per composition entry; if any read state could change what the effect does, it must be in the key list.
- Stability: data classes you pass into composables should be `@Immutable` (all properties `val` and deeply immutable) or `@Stable` (mutations are observable through Compose state). `List<T>` from stdlib is not stable to the compiler — prefer `ImmutableList` / `PersistentList` from `kotlinx.collections.immutable` when recomposition profiling shows the issue, or pass a `LazyListScope`-style slot.
- Previews are a tool, not a deliverable. Every screen-level composable has at least one `@Preview` with representative fake data, ideally behind a `@DevicePreviews` multipreview covering phone/foldable/tablet. Previews must not reach into Hilt (`hiltViewModel()`) — pass fakes.
- `CompositionLocal` is for ambient values (`LocalContext`, theme, analytics sink). Do not use it as a dependency-injection shortcut for `ViewModel`-owned data.

## View system (legacy surface)

- New UI is Compose. The View system is used only when (a) interop is required (Maps, WebView, CameraX `PreviewView`, third-party `View` components), (b) a screen is still in the old stack and a full migration is out of scope, or (c) a platform widget has no Compose equivalent of acceptable quality.
- Compose -> View interop uses `AndroidView(factory = { ... }, update = { view -> ... })`. Keep `factory` idempotent (no side effects on external state); `update` is where state from Compose reaches the View.
- View -> Compose interop uses `ComposeView` inside the layout with `setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)`. Do not leave the default `DisposeOnDetachedFromWindow` strategy inside a `Fragment` that can be detached without destruction.
- Do not mix data binding (`<layout>` XML) with Compose in the same screen. Pick one.

## Concurrency

- Use `kotlinx.coroutines` with structured concurrency. A `launch { ... }` always has a parent scope; that scope must be tied to a real owner (`viewModelScope`, `lifecycleScope`, `CoroutineWorker`'s scope, or an `@ApplicationScope` with a `SupervisorJob`).
- Inject dispatchers. `Dispatchers.IO` / `Dispatchers.Default` are not referenced directly in feature code — create a `@Dispatcher(IO) CoroutineDispatcher` qualifier and inject it via Hilt. This makes tests deterministic by swapping in a `TestDispatcher`.
- `Dispatchers.Main.immediate` for UI updates that are already on the main thread — avoids a needless dispatch. `Dispatchers.IO` for blocking I/O (disk, network). `Dispatchers.Default` for CPU-bound work (parsing, crypto, compression). Never `Dispatchers.Unconfined` outside tests.
- Exception handling in coroutines: `SupervisorJob` for scopes where one child's failure must not cancel siblings (application scope, `viewModelScope` already uses supervisor semantics). A bare `launch { ... }` in a supervisor scope swallows cancellation correctly but still propagates other throwables — install a `CoroutineExceptionHandler` when you start a long-lived top-level coroutine.
- Cold `Flow` vs hot `StateFlow`/`SharedFlow`:
  - Repository returns cold `Flow<T>` built on top of Room/DataStore/SSE sources. Cold means it starts work per collector.
  - `ViewModel` converts to hot `StateFlow` with `.stateIn(viewModelScope, WhileSubscribed(5_000), initialValue)` for state the UI needs to replay, or `SharedFlow` for events.
  - Do not `stateIn` in a repository — it will keep upstream alive forever regardless of UI lifetime.
- `flatMapLatest` when only the newest parameter matters (searches, deep-link args), `combine` when you need the cartesian product of multiple streams, `zip` only when the streams are genuinely paired by index. `flatMapConcat` almost always means you want `flatMapLatest` or `flatMapMerge`.
- `collect` suspends until upstream terminates — do not `collect` in a place that must return immediately. For fire-and-forget bridges from a cold Flow to a store, `launchIn(scope)` plus `onEach { ... }`.
- Cancellation is cooperative. Long loops call `ensureActive()` or check `isActive` at their boundary. Never swallow `CancellationException` — if you `catch (e: Throwable)`, re-throw `CancellationException`.
- Background work is `WorkManager` for deferrable / guaranteed-once tasks, a foreground service for user-visible long-running work (playback, navigation), and `CoroutineWorker` implemented with `@HiltWorker + @AssistedInject` for injectability. Do not schedule long-running work from `ViewModel.viewModelScope` — that scope dies with the screen.

## Lifecycle & memory

- A `ViewModel` outlives configuration changes and may outlive the screen's visibility. It must never hold an `Activity` `Context`, a `View`, a `Fragment`, an `Activity` reference, or anything that transitively retains them. If you need `Context` inside a `ViewModel`, inject `Application` via `@ApplicationContext` or `AndroidViewModel`, and prefer injecting the specific collaborator you actually need (e.g. a `ResourceProvider` wrapper).
- `viewModelScope` only. A `ViewModel` does not create its own `CoroutineScope`. Do not pass `viewModelScope` out of the `ViewModel` into collaborators — that couples collaborator lifetime to the `ViewModel`.
- Observers registered in an `Activity`/`Fragment` with `lifecycleScope.launch { repeatOnLifecycle(Lifecycle.State.STARTED) { ... } }` or `flowWithLifecycle(lifecycle)`. Plain `lifecycleScope.launch` without `repeatOnLifecycle` will keep collecting while the screen is stopped.
- Resource cleanup: any listener, callback, `BroadcastReceiver`, sensor, location client, or service binder registered in `onStart`/`onResume` must be unregistered in the matching `onStop`/`onPause`. Compose composables use `DisposableEffect` for the same contract.
- Singletons must be truly stateless or hold only `Application`-scoped state. A `@Singleton` that caches per-screen state will leak across users and navigations.
- Process death: the OS can kill your process while backgrounded and restore the back stack later. State that matters on restore must be in `rememberSaveable`, `SavedStateHandle` (ViewModel), DataStore/Room, or regenerated from a repository observation — never in a plain `var` in a `ViewModel` or composable.
- `SavedStateHandle` is the `ViewModel`'s slice of saved state. Prefer `savedStateHandle.getStateFlow(key, default)` over ad-hoc `savedStateHandle.get`/`set` for state you want the UI to observe.
- Configuration changes: do not fight them with `android:configChanges` to avoid recreation unless you are handling the change manually (keyboard, orientation-locked game). The default recreate path is tested and correct; overriding it means you also own rotation/locale/dark-mode responses.

## Security

- Secrets do not live in source, `gradle.properties` committed to VCS, or XML resources. Use `local.properties` (gitignored) + `BuildConfig`/`buildConfigField`, or a secrets-injection Gradle plugin. Never hardcode API keys or tokens in Kotlin/Java/XML.
- Sensitive at-rest data goes through the Keystore. Use `androidx.security:security-crypto`'s `EncryptedSharedPreferences` / `EncryptedFile` for small-to-medium payloads, or `MasterKey.Builder` + `Cipher` with a `KeyGenParameterSpec` that sets `setUserAuthenticationRequired(true)` when appropriate. Do not roll your own AES — use the library.
- Plain `SharedPreferences` and `DataStore` without encryption are fine for non-sensitive state (UI prefs, feature flags). User credentials, session tokens, PII, PHI, and payment data require Keystore-backed encryption.
- Network: TLS only. `android:usesCleartextTraffic` must be `false` (the default on `targetSdk >= 28`), and the network security config must not add cleartext domains in release builds. Certificate pinning via OkHttp `CertificatePinner` is expected for first-party APIs that handle sensitive data; pin to the public key SPKI, not a leaf certificate.
- Biometric auth uses `androidx.biometric:BiometricPrompt` with `BiometricManager.canAuthenticate(BIOMETRIC_STRONG)`. Always tie sensitive operations to an authenticated `Cipher` (`CryptoObject`) — a successful prompt alone is not proof of user presence for later decryption.
- `PendingIntent` flags are a security boundary. On `targetSdk >= 31` every `PendingIntent` must set `FLAG_IMMUTABLE` unless you specifically need `FLAG_MUTABLE` (e.g. `Notification.MediaStyle`). Combine with `FLAG_UPDATE_CURRENT` when updating an existing intent — never pass `0`.
- Intent filters are attack surface. Any exported `Activity`/`Service`/`Receiver`/`Provider` (`android:exported="true"`) must validate the calling package, signature, or permission. Implicit intents delivered to your app can carry attacker-controlled extras — validate every string you read from `Intent.getExtras()` before using it (path traversal, SQL inputs, URL schemes).
- Deep-link validation: do not trust the URL's host/path. Verify the scheme is one you own, the path matches an expected route, and numeric IDs parse cleanly. Use Android App Links (`autoVerify="true"`) with `assetlinks.json` to prove domain ownership; without App Links, an attacker can register a competing handler.
- `WebView` defaults are unsafe. Disable `setJavaScriptEnabled` unless required, disable `setAllowFileAccess`/`setAllowContentAccess`/`setAllowFileAccessFromFileURLs`/`setAllowUniversalAccessFromFileURLs`, set `setMixedContentMode(MIXED_CONTENT_NEVER_ALLOW)`, and if you add a JS bridge, only expose methods annotated `@JavascriptInterface` and only when loading content you control.
- Input validation on every boundary that crosses a trust line: IPC, deep links, notification actions, content providers. Treat `SavedStateHandle` keys from deep-link args as untrusted.
- R8 / ProGuard rules are part of the security and correctness story. Release builds use `minifyEnabled true` with `shrinkResources true`. Keep rules (`-keep`) are scoped to specific classes/members — blanket `-keep class com.myapp.** { *; }` defeats R8. Use `consumerProguardFiles` in library modules so apps pick them up automatically. Verify release builds actually work: crashes from missing keep rules surface only under R8.
- Logging: never `Log.d`/`Log.i`/`println` tokens, passwords, PII, device IDs, or request/response bodies that may contain them. Strip debug logs in release via ProGuard (`-assumenosideeffects class android.util.Log { ... }`) or a `Timber.DebugTree` that is only planted in debug builds.
- `FileProvider` for every `file://` URI you would share across apps on `targetSdk >= 24`. Direct `Uri.fromFile` crashes with `FileUriExposedException` and is the right behavior — do not work around it.

## Testing

- Three layers of tests:
  - Unit tests (`src/test`) for pure JVM logic — use-cases, `ViewModel` wiring, serializers, mappers. Fast, run on every commit.
  - Robolectric (still in `src/test`) only when you need framework types (`Context`, `Uri`, `Resources`) and a JVM runtime is enough. Do not use Robolectric as a substitute for instrumentation tests of real device behavior.
  - Instrumented tests (`src/androidTest`) for Compose UI, Room DAOs, WorkManager, and anything touching the real Android runtime.
- `ViewModel` tests swap `Dispatchers.Main` with a `TestDispatcher` via a `MainDispatcherRule` (or `@BeforeEach` setMain/resetMain). Do not test a `ViewModel` without doing this — `Dispatchers.Main` on JVM throws on first use.
- Inject `TestDispatcher` for the `IO`/`Default` qualifiers in tests via Hilt's `@TestInstallIn(replaces = [DispatchersModule::class])`. Production code never references `Dispatchers.IO` directly so this substitution is clean.
- `Flow` assertions use Turbine (`flow.test { assertThat(awaitItem())... }`). Do not roll your own `toList()` + timeout — it hides races.
- For `stateIn(WhileSubscribed(5_000))` flows: start an explicit collector in the test (`backgroundScope.launch(UnconfinedTestDispatcher()) { vm.uiState.collect() }`) before asserting `vm.uiState.value`. Otherwise the flow is cold and the value is the initial.
- `runTest { ... }` from `kotlinx-coroutines-test`, never `runBlocking` for coroutine tests. Use `advanceUntilIdle()` / `advanceTimeBy()` to drive virtual time; do not `Thread.sleep`.
- Compose tests use `createComposeRule()` (no Activity) for stateless composables and `createAndroidComposeRule<ComponentActivity>()` when you need `Activity` context. Production `Activity` subclasses are not used in tests — `ComponentActivity` is enough.
- Fakes over mocks for repositories and data sources. A hand-written `TestFooRepository : FooRepository` that backs on a `MutableSharedFlow` is easier to reason about than a mock with four stubbed methods. MockK is available for Kotlin-friendly mocking when a fake is impractical — prefer relaxed mocks only for collaborators you are not exercising.
- No shared mutable state between tests. Each test gets its own `TestDispatcher`, its own fakes, its own `Hilt` test components. Order-dependent test suites are bugs.
- Screenshot tests (Roborazzi / Paparazzi) are generated by CI, not committed from a workstation, and they live in `src/test` (JVM-based) for speed.

## Accessibility

- Interactive `Icon`/`Image` requires a non-null `contentDescription` from a string resource; decorative icons inside a labelled `Button` or next to text use `contentDescription = null`.
- Clickable composables use `Modifier.clickable` with `onClickLabel` for the action verb ("Open article"), or wrap in a semantic component (`Button`, `Card` with `onClick`) that already does the right thing. Do not use bare `pointerInput { detectTapGestures { ... } }` for primary click affordances — it bypasses accessibility semantics.
- Touch targets are at least 48x48 dp for anything the user taps. Use `Modifier.minimumInteractiveComponentSize()` or the Material components that already enforce this; do not shrink below 48dp to fit a dense design — add padding instead.
- Text uses `sp`, non-text sizing uses `dp`. No fixed-height containers wrapping text.
- TalkBack grouping: `Modifier.semantics(mergeDescendants = true) { ... }` for composite items (a card with title + subtitle + icon) so TalkBack reads one focusable node. Without this, users tab through three separate, confusing nodes.
- State changes announce themselves. Use `Modifier.semantics { stateDescription = "selected" }` for toggle-like controls, and `LiveRegion` semantics for updating text (error banners, countdowns).

## References

Digested from (local clones in `references/`):
- android/nowinandroid — sections: Architecture (`AGENT.md`, `docs/ArchitectureLearningJourney.md`, `docs/ModularizationLearningJourney.md`), Jetpack Compose + Lifecycle (`feature/foryou/impl/src/main/kotlin/.../ForYouViewModel.kt`, `ForYouScreen.kt`, `OnboardingUiState.kt`, `core/ui/src/main/kotlin/.../DevicePreviews.kt`), Concurrency + DI (`core/common/src/main/kotlin/.../NiaDispatchers.kt`, `.../di/DispatchersModule.kt`, `.../di/CoroutineScopesModule.kt`, `core/common/src/main/kotlin/.../result/Result.kt`, `sync/work/src/main/kotlin/.../SyncWorker.kt`), Security (`core/notifications/src/main/kotlin/.../SystemTrayNotifier.kt` for `PendingIntent` flags and permission checks, `app/proguard-rules.pro`, `core/datastore/consumer-proguard-rules.pro`), Testing (`core/testing/src/main/kotlin/.../util/MainDispatcherRule.kt`, `.../di/TestDispatchersModule.kt`, `feature/foryou/impl/src/test/kotlin/.../ForYouViewModelTest.kt`, `feature/foryou/impl/src/androidTest/kotlin/.../ForYouScreenTest.kt`), Architecture (`app/src/main/kotlin/.../MainActivity.kt`, `NiaApplication.kt`, `core/data/src/main/kotlin/.../repository/OfflineFirstNewsRepository.kt`, `.../di/DataModule.kt`, `build-logic/convention/src/main/kotlin/.../KotlinAndroid.kt`).
- Kotlin/kotlin-agent-skills — sections: Kotlin language + DI (`skills/kotlin-tooling-java-to-kotlin/references/frameworks/DAGGER-HILT.md`, `.../RETROFIT.md`), Build / tooling (`skills/kotlin-tooling-agp9-migration/SKILL.md` — AGP 9 / built-in Kotlin / ProGuard default changes informed the security + R8 rule on strict keep rules and removal of legacy flags).
