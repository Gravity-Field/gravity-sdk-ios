# In-app presentation and visible impression delivery (EGO-248)

Automatic `trackView` / `triggerEvent` presentation reserves a campaign before `/choose`.
The reservation is atomic and keyed by campaign ID, rather than the content ID decorated
with a new tracking event ID on every response. It covers content retrieval, delay,
presentation, and the gap before the visible-impression HTTP acknowledgement.

Each request captures the explicit user and screen generation. A newer screen notification,
changed user/session, SDK reinitialization, or Android disposal invalidates old requests.
`/visit`, `/event`, and automatic `/choose` share that user snapshot; all three public
choose APIs now pass `setUser` identity as well. Anonymous identity fallback stays in the repository.

A failed/unsupported presentation or close before visibility releases its reservation.
Once visible, close keeps it reserved until all tracking URLs return HTTP 2xx.
Responses from requests started before that acknowledgement cannot re-present the campaign.
Fresh requests subsequently use the backend campaign frequency cap. `OPEN_STEP` does not
reserve a new campaign; the initial payload binds all its step content IDs.
The host's public `lockPresentation` / `unlockPresentation` remains a separate control.

The visibility callback sends the backend `visible_impression` event even when no custom
`onVisibleImpression` action exists. It never sends that event merely on content load.
Concurrent duplicate callbacks share delivery for the same URL. Successful URLs are cached
for 15 minutes (maximum 512); failed URLs are not cached. Each URL gets at most 3 attempts,
with 250 ms and 1 s pauses for network errors and HTTP 408/429/5xx. Other 4xx and malformed
URLs fail immediately. The SDK instance's API key is captured for delayed visibility delivery.
Failures/missing tracking URLs are logged rather than treated as successful acknowledgements.

A presented reservation expires after 60 seconds if no acknowledgement arrives, so a missing
event cannot permanently suppress a campaign. Pending unpresented requests are cancelled
on a newer screen; caller cleanup also releases them on failure/cancellation.
This is an in-process bridge, not a persistent offline outbox or a global frequency cap.
Cross-device/restart exclusion and Redis cap-write failures remain backend concerns.
Retries reuse the same tracking URL/event ID; exactly-once analytics is not guaranteed by the SDK.

## Verification

`./scripts/test-core.sh` runs the production Foundation sources and 14 shared regression cases without UIKit/XCTest. With Xcode, run the `GravitySDKTests` package test target on an iOS simulator.

Before release, verify in a test app against a non-production section:

1. For a campaign capped per user/session/day, delay `/engagement` and navigate rapidly
   across 3 screens. Only one automatic presentation may win; stale delayed content must not appear.
2. Keep at least 50% of content visible (Android: continuously for 1 second). Confirm WRIMP
   is sent only after visibility, including a payload without `onVisibleImpression` variables.
3. Inject HTTP 500/429 then 2xx. Confirm the same URL is retried and a new screen cannot
   re-present while delivery is pending. HTTP 400/403 must neither retry nor acknowledge.
4. Cancel a delayed presentation, lock presentation, close before visibility, background/destroy
   the host, change user/session, and reinitialize the SDK. Check no stale overlay is attached.
5. Open later steps and close via every UI path. Confirm the next step works and the cap
   reflects visibility; independently verify modal, full screen, bottom sheet, and snackbar.
6. Confirm `setUser` appears in choose by campaign/selector/group; repeat anonymously.
7. Confirm fresh requests honor configured server policy, including `page_view` campaigns.

Release Android and iOS independently after platform QA, first to a pilot app. No backend
schema, event name, URL contract, public SDK method, or campaign configuration changes are required.
Rollback by pinning the previous SDK version; no data migration is involved.
