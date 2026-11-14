# Changelog

## Unreleased

- Avoid iOS 17 crashes on extreme campaign priority and delay exponents by decoding raw JSON numbers with binary precision.
- Expose the chosen campaign’s `delayTime` in NoShow responses and load callbacks for host-owned waiting and rendering; accept fractional numbers and numeric strings (truncated toward zero; decimal strings retain exact precision) for campaign priorities and delays; invalid values are ignored and no longer fail the whole /visit or /event response.
- Prevent auto-show crashes on negative or very large integer campaign delays; negative delays mean no wait and large delays saturate to the maximum supported sleep; delayed auto-show stops when the screen, user or presentation lock changes, releasing its reservation.

### Choose requests

- Send content settings under `option` in all choose requests.

### Error reports

- Redact complete Authorization, Proxy-Authorization and X-Authorization values to the end of the line in free-text messages, stack traces and diagnostic fields; preserve following lines.
- Require valid IPv6 address syntax before exempting bracketed endpoints from credential redaction.
- Redact JSON and partially encoded slash forms and malformed credential ports; deduplicate sanitized diagnostics with stable transport codes and endpoints.
- Strip credentials from generic URL schemes and URLs nested after opaque prefixes while preserving following prose.
- Keep surrounding diagnostics and endpoint paths while stripping secrets from all URL schemes, malformed credentials and escaped URLs in linear passes.
- Bound backend error reports to ten attempts per rolling minute and suppress identical message/stack reports for a minute after successful delivery; allow failed sends to retry within the budget.
- Preserve useful encoded endpoint paths in diagnostics while redacting URL credentials, queries and sensitive headers; omit HTTP failure bodies from debug logs.
- Keep error reports usable before session initialization, preserve the current device identity, sanitize URL credentials and queries, and redact authorization in request logs.

### Products grid and presentation

- Ignore non-finite dimensions in server styles to prevent invalid layout and product-row rendering crashes.
- Parse legacy `gridColumns` as numeric or `px` dimensions, validating 1–12 before truncating fractional values.
- Send modal, fullscreen and bottom-sheet impressions once per showing, including when the host covers and uncovers the view.
- Wait for modal dismissal before opening the next step; cancel stale transitions when the user, presentation state or foreground activity changes.
- Replace the current modal, fullscreen or bottom sheet with the next `open_step` step regardless of `closeOnClick`, matching Flutter; the replaced step sends no close, the showing keeps one visible impression, and one close is tracked when the last step closes.
- Omit modal, fullscreen and bottom-sheet close tracking before the first confirmed content frame, including external UIKit removal; missing WRIMP URLs do not suppress an appeared close.
- Track modal, fullscreen and bottom-sheet close once when their UIKit host is removed outside `dismissInApp`, preserving SDK dismissal completions.
- Present a different campaign above an open modal, fullscreen or bottom sheet instead of skipping it; a new opening of a campaign whose in-app is still open is skipped, and `dismissInApp` for a lower in-app also closes those stacked above it, tracking each close once.
- Send close tracking once when modal, fullscreen or bottom-sheet close buttons also trigger the configured dismissal action.
- Add product grids with public `GridSettings`, `Style.gridSettings` and a `gridSettings` parameter in `Style.init`; fall back to legacy `gridColumns`, with 2 columns and spacing 8 by default.
- Render square grid cards with `style.padding` and 1–12 columns; invalid settings fall back to valid `gridColumns`, otherwise 2.
- Accept numeric and `px` strings for dimensions of all elements, including size, padding, margin and corner radius.
- Send grid product impressions once per slot after at least half of the card is visible inside the scroll viewport.
- Scroll tall fullscreen and bottom-sheet content within the actual host bounds while preserving sheet drag dismissal.
- Allow all fullscreen content to extend beneath the home indicator, matching Flutter.
- Render nothing for product rows and grids without products, including their margin, padding and background, when the products object or its slots are missing or empty.
- Drag a bottom sheet down from the top of its content without bouncing the nested scroll view.

### User identity

- Add `getUserId` and `setUserIdListener` to read and observe the server user ID.
- Add `resetUser`, `restoreUserId` and `GravityUserIdError` for explicit identity changes and storage failures.
- Discard previous-user content after identity changes; reload pending or empty inline content when the page context changes while retaining loads during navigation.
- Preserve user ID listeners across SDK initialization; reset clears the in-memory identity even if storage removal fails.

### Headless campaign fetching

- Add async `trackViewNoShow` and `triggerEventNoShow` to return campaign content and raw JSON without opening UI or sending client impression events; candidates are tried by descending priority.
- Add `isFetchContentOnTrack` and `staleContentTimeout` to control NoShow fetching before or after initialization. Settings survive reinitialization, timeout updates affect in-flight requests, and host request options are passed unchanged. Each content candidate uses the current options and content settings.

### Snackbar presentation

- Remove snackbars dismissed before their first visible frame without impression or close tracking; keep successful dismissal results and completion after removal.
- Pause snackbar and modal impression visibility behind presented controllers or opaque covering views; resume after the content is exposed.
- Keep attached snackbar and modal impressions valid across normal server UID updates and bind durable delivery to the identity scope at visibility confirmation.
- Discard pending modal visible impressions after `setUser`, `resetUser` or `restoreUserId` changes the opening identity.
- Track snackbar visible impressions through the durable outbox after half the content stays visible for one active second; send one impression per showing and avoid duplicate close tracking.

## 1.2.0

- Add `getContentBySelectorWithDetails` and `getContentByCampaignIdWithDetails`: the model plus the raw JSON of the same response
- Add `CampaignContent.rawVariables` and key access on `Variables` for keys with no typed counterpart
- Add `customProps` and `eventTime` to all trigger events; `CustomEvent` also gets `cuid`, `cuidType` and `cart`
- Events without `eventTime` are sent with the time `triggerEvent` was called
- Count modal, fullscreen and bottom-sheet visible impressions on the first confirmed content frame while active, with one WRIMP per opening across fast explicit close and step transitions.
- Persist modal WRIMP URLs and stable user identity scope before sending; retain campaign protection through offline close/restart, retry on network restoration, and release after server acknowledgement.
- Limit local modal re-open protection to 24 hours from the persisted show timestamp (also during active sends), ending sooner on HTTP 2xx/permanent drop; continue original WRIMP delivery independently for up to 7 days across restart/network restoration, including for no-limit/every-page-view campaigns.
- Keep at most 256 openings/1 MiB per API-key/section by evicting oldest events to retain a fresh WRIMP; reject only a single opening exceeding 1 MiB. Drop permanent HTTP/URL failures without treating them as acknowledgements.
- Clean orphaned queue/quarantine namespace files older than the 7-day delivery TTL with a bounded mtime sweep; route store diagnostics through GravityLogger and the host logListener without backend error reports.
- Stop modal visibility detection after one attempt even when WRIMP is absent or persistence fails; preserve the appearance callback/custom action and log locally once.
- Remove unused full User snapshots/host attributes from the outbox, migrate existing records and sanitize quarantine data; preserve original URL attribution and stable user isolation.
- Preserve the bounded 60-second presentation fence after closing an appeared modal with no WRIMP URL or failed persistence; explicit close remains valid after the app becomes inactive.
- Use capped exponential delivery backoff (30 seconds to 15 minutes), resetting on new events and network restoration.
- Move startup restore, first-frame persistence and namespace cleanup off the UI thread; establish memory protection before dismissal and persist before sending. Automatic presentation awaits initial restore asynchronously before deciding protection, avoiding skipped first campaigns on a slow cold start; waits are cancellable and bounded to 5 seconds with a local timeout diagnostic.
- Modal ContentVisibleImpressionEvent callbacks and custom onVisible actions follow the result of background persistence and may arrive after UI dismissal.
- Recover valid queue records by atomically rewriting corrupt files without redundant quarantine copies; remove legacy quarantine files on load, preserve temporarily unreadable files, and exclude the queue from device backups.
- Emit modal visibility callbacks and custom onVisible actions once for the initial step of an opening; OPEN_STEP no longer emits per-step visibility notifications. Custom onVisible actions now run alongside WRIMP rather than replacing it, retaining their existing best-effort delivery.

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
