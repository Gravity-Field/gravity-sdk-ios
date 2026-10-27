# Changelog

## Unreleased

* Add `getContentBySelectorWithDetails` and `getContentByCampaignIdWithDetails`: the model plus the raw JSON of the same response
* Add `CampaignContent.rawVariables` and key access on `Variables` for keys with no typed counterpart

## 1.1.0

- Send all content requests on behalf of the user set via `setUser`, preserving the automatic request user snapshot.

- Default missing follow_url type to browser.
- Render button borders from outlineColor and preserve disabled/pressed styling.
- Fix parsing of `#RRGGBB` colors; `#RRGGBBAA` keeps alpha last. Invalid colors resolve to no color.

- Prevent duplicate automatic in-app presentations while a campaign is being prepared, displayed, or awaiting visible-impression acknowledgement.
- Retry transient visible-impression delivery failures; acknowledge visibility only after successful delivery.
- Combine asynchronous preparation with presentation reservations, rejecting stale screens, users, cancelled tasks, and presentation locks before mounting UI.
- Load demo credentials from local configuration instead of committing them.

- Add `dismissInApp(contentId:completion:)` for targeted dismissal from the existing ProductViewBuilder; navigate after dismissal and track close once.

- Add optional asynchronous in-app preparation, deadline and per-content skip.
- Preserve original product slots and tracking when filtering review prompts.
- Revalidate presentation after preparation and invalidate pending work on user changes or presentation lock.
- Add a purchase-review integration example and regression tests.
- Extract `ReviewPromptIntegration.recommendedContent(for:campaign:)` so the eligibility-filtering logic is directly callable, and add a demo "Review Prompt Test Console" screen with scenario checks and a live recommendations preview.
- Wire the demo app's `GravitySDK.initialize` to a shared `ReviewPromptCoordinator`, and point the test console at the real test campaign `6acdfec314d8e893950c5402` (selector `ios-review`, trigger "Page load" / Search page): one button calls `getContentBySelector` directly and renders the filtered products with the real `productViewBuilder` (since `getContentBySelector` never displays anything itself), another runs the matching `trackView` trigger through the full automatic/`inAppPreparation` pipeline — which competes by priority with any other campaign on the same trigger.
- Extract `GravitySDK.resolvedContent(_:_:preparation:)` — the no-handler-passthrough / delegate-to-`InAppPreparation.prepare` decision `prepareAndShowBackendContent` makes — so it's directly unit-testable; add regression tests for invalid/boundary timeouts, a slow handler hitting its own timeout, and a user/screen change that invalidates the presentation revision while preparation is still in flight.
- Add `InAppPreparationTests.testPreparationWaitsForTheClientsBatchCheckBeforeResolving`: a client integrating the SDK does one batch eligibility check for every SKU, and `prepare()` must not resolve before that check actually completes (proven with a manually-resumed continuation, not a sleep-based guess) — whatever survives keeps its original order and tracking.
- Turn the demo's "ios-review" integration into a real, working feature instead of a stub: `DemoReviewEligibilityAPI` now does a genuine batch lookup against a new `UserDefaults`-backed `ReviewStatusStore` (no more "approve everyone"), and tapping "Оставить отзыв" opens a real `ReviewFormView` whose submission persists the status — so a reviewed SKU is actually excluded from the campaign on every later show, including after relaunch. Test console gets a "Сбросить статус отзывов" control to re-test the flow.
- Fix: the "Получить и показать по selector" preview rendered the real `ProductViewBuilder`, whose button only opens the review screen after `dismissInApp` succeeds — but that preview has no live SDK-presented in-app to dismiss, so it always returned `false` and the form never opened. Added `ReviewPromptCoordinator.reviewFromPreview`, which sends the real click tracking but opens the review screen directly for this preview-only path; the real campaign flow (`triggerRealCampaign`) is unaffected and still gated on a real dismissal.
- Redesign the test console: card-style sections, trimmed explanations, bounded/scrollable log output, and a nicer product card (image, price, prominent button) shared by the real campaign and the demo recommendations preview.
- Fix (review): "Сбросить статус отзывов" only cleared `ReviewStatusStore`, leaving the SKU excluded by `ReviewPromptIntegration`'s own in-session `SubmittedReviews` cache until relaunch — added `ReviewPromptIntegration.clearSubmittedReviews()` and route the reset through a single `ReviewPromptCoordinator.resetReviewStatus()` that clears both.
- Fix (review): the test console's scenarios and `loadRecommendations()` shared one mutable `TestConsoleReviewAPI`, so overlapping runs could leak `shouldThrow`/`ineligibleSkus`/`requestedSkuBatches` into each other. `TestConsoleReviewAPI` is now configured once at construction and never mutated; every scenario and `loadRecommendations()` builds its own instance via `makeIntegration`, and both are also guarded against re-entrant calls (`isRunningScenarios`/`isLoadingRecommendations`) with their buttons disabled while in flight.

## 1.0.6

* Add presentation lock to suppress campaign display

## 1.0.5

* Remove force unwrap
* Use child controller for snackbar
* Make snackbar dismiss idempotent
* Add custom font
* Add background image
* Fix bottom sheet layout
* Add GravityWebView
* Add loader to inline view
* Add verticalAlignment to Style for content alignment
* Add element with type ITEMS_CONTAINER and campaign steps logic
* Support layoutWidth in GravityText
* Add GravityInlineListView
* Fallback products container type to row
* Fix products container layout
* Fix image sizing without height
* Fix custom font weight
* Fix image rendering

## 1.0.4

* Marked `GravityLogListener` as `@Sendable`

## 1.0.3

* Added `setLogListener` to forward SDK logs to a custom callback

## 1.0.2

* Improved SDK log visibility

## 1.0.1

* Removed trailing commas

## 1.0.0

* Public methods no longer crash when called before `GravitySDK.initialize()`
* Default `logLevel` is now `.error` instead of `.none`

## 0.1.0

* Replace `import SwiftUICore` with `import SwiftUI`

## 0.0.9

* Initial release
