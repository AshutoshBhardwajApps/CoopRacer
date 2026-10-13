# Claude Conventions for CoopRacer

Two-player local racing game (split screen, one phone, players at opposite
ends). Its infrastructure was ported from CoopHockey in October 2026, and
CoopHockey's `CLAUDE.md` is the longer reference for every pattern below.
Where the two disagree, this file wins for this app.

## Architecture

- **SwiftUI app, UIKit AppDelegate adaptor.** AppDelegate handles the audio
  session, AdMob init, UMP consent, ATT and ad preload. SwiftUI handles
  everything else.
- **Singletons via `@StateObject` in the App struct, injected via
  `@EnvironmentObject`** (`SettingsStore`, `PurchaseManager`).
- **Flat file layout.** `AdManager`, `AdPresenter`, `ConsentManager`,
  `PurchaseManager`, `SettingsStore` and `Haptics` are the infrastructure files.
- **No `Constants.swift`.** Ad unit IDs live in `AdManager`, the IAP product ID
  in `SettingsStore`, the same as CoopHockey.
- **UserDefaults keys are prefixed `cr.`.** Keep the prefix on anything new.
- The Xcode project uses **file-system synchronized groups**: any file dropped
  into `CoopRacer/` is compiled or bundled automatically, with no
  `project.pbxproj` edit needed. `Info.plist` is the one exception.

## Launch order (do not change)

**UMP consent, then ATT, then preload ads.** All three run inside
`requestATTIfNeeded()`, on `didBecomeActive` plus 0.4s. Calling ATT from
`didFinishLaunching` silently no-ops, and that got CoopHockey 1.3(14) rejected.
Consent failures never block ads: `ConsentManager.gather` always completes,
and gives up waiting after 5s.

To test the consent form, set `ConsentManager.forceEEAForTesting = true`
(DEBUG only) and use "Reset consent" in the Settings DEBUG section.

## Ads (`AdManager`)

- **DEBUG uses Google's test interstitial unit, Release uses the real one.** The
  Release ID is a `XXXX` placeholder until the AdMob unit is created.
  `adUnitIsPlaceholder` blocks requests (and logs it) while it is one.
- `testDeviceIdentifiers` in `AppDelegate` makes the developer's phone get
  test ads even in Release. The hash changes if the advertising ID is reset.
- **Round-end flow** (`ContentView.handleRoundEnded`): count the round, then
  either show the Remove Ads promo or present an interstitial, and only then
  raise the results sheet. Wait 0.4s after `.adDidDismiss` (or the promo
  closing) before setting `showResults`, or the sheet can come up blank.
  `GameCoordinator.roundEnded` is the trigger, and `showResults` is now set
  only by this flow.
- Pacing is the same as CoopHockey: `minRoundsBetweenAds = 1`,
  `minGapSeconds = 0`, a forced promo every 8th round plus random 1-in-12 rolls.
- **Presenter rules.** Interstitials present from `AdPresenter`'s anchor.
  Anything shown from inside a sheet or `fullScreenCover` must use
  `AdManager.topmostPresenterVC()`. Getting this wrong shows up in AdMob as
  100% fill with zero impressions.
- Mediation adapters (Meta, Liftoff/Vungle, Pangle) are linked through SPM, at
  the same versions as CoopHockey. `FBAdSettings.setAdvertiserTrackingEnabled`
  must stay ahead of `MobileAds.shared.start()`.

## IAP (`PurchaseManager`)

- StoreKit 2. One product, Remove Ads: `coopracer.removeads`. It must exist in
  App Store Connect with that exact ID.
- `loadProducts()` and `restorePurchases()` run once from the App struct's `.task`.
- `SettingsStore.markRemoveAdsPurchased()` sets `hasRemovedAds`, which stops
  interstitials and promos and hides the home-screen pill.

## Sound + haptics

- `effectsEnabled` gates the countdown, engine loop and crash sounds, as well as `Haptics`.
- `musicEnabled` is checked inside `BGM.play()` itself, so every caller respects it.

## Layout

- **Portrait only, with `UIRequiresFullScreen = YES`.** The rule is copied from
  CoopHockey and the reasoning is the same: two players face each other across
  the phone. Removing `UIRequiresFullScreen` opts into iPad multitasking, and
  App Store validation then demands all four orientations.
- `GameScene.didChangeSize` and the `geo.size` check in `ContentView` rebuild
  the scenes when the window resizes (iPhone Duo fold/unfold).

## app-ads.txt

`app-ads.txt` sits at the repo root and is served through GitHub Pages. Its
content is `google.com, pub-2320635595451132, DIRECT, f08c47fec0942fa0`.

## Versioning

- `CURRENT_PROJECT_VERSION` bumps on every upload, and `MARKETING_VERSION` per
  public release. Each appears twice in `project.pbxproj` for the app target
  (Debug and Release). The test targets keep their own values.

## Not ported yet

- **Single player** (a CPU opponent, the equivalent of CoopHockey's
  difficulties and NEMESIS) still shows "Coming soon".
- **Game Center leaderboards** and **rewarded ads** both need a design
  decision about what to rank and what to earn.

## Style

- Terse comments that explain **why**. `// MARK: -` for sections. 4-space indent.
