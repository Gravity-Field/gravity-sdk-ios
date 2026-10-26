# In-app presentation and visible impression delivery (EGO-248, EGO-272)

Automatic `trackView` / `triggerEvent` presentation reserves a campaign before `/choose`.
The existing `InAppPresentationGate` is atomic and keyed by campaign ID. Each request
captures the user and screen generation; newer screens, changed users/sessions and SDK
reinitialization invalidate stale work. Unsupported, cancelled or never-visible presentations
release their reservations. The public presentation lock remains a separate host control.

## iOS modal visibility

For bottom sheet, modal/dialog and fullscreen, `visible_impression` / WRIMP means **the
window content actually appeared on screen**, with the application active. There is no
minimum viewing duration and no 50% threshold for these formats. A display-link probe
attached to the content checks its committed Core Animation presentation layer, including
opening offsets, opacity, window intersection and foreground scene state. Merely creating a
view, receiving `/choose`, loading content, or showing a scrim does not count. Bottom-sheet
image preroll remains off screen and does not count until the opening animation exposes content.

Frame detection and explicit close share one atomic `ModalImpressionSession` per opening.
Swipe/backdrop, close X, close/cancel buttons (including “Not now”), and `dismissInApp`
(the host's Back route) confirm an already appeared window before starting dismissal.
A close before any confirmed content frame, navigation-driven removal or backgrounding
cannot manufacture WRIMP. Repeated callbacks and `OPEN_STEP` reuse the opening's flag and
initial content tracking URL, so later steps do not generate another logical impression.
iOS has no system Back button for these SDK-owned fullscreen/over-fullscreen controllers;
host Back handlers use the existing `dismissInApp(contentId:completion:)` API.

Inline-block and product-card visibility detectors and product tracking are unchanged.
Snackbar retains its existing geometric detector and delivery path; it does not use the new
modal display-link probe or durable modal outbox.

## Durable modal delivery

`VisibleImpressionDelivery` owns a minimal file-backed outbox; it is independent of UI
lifetime. Before tracking callbacks or network sends, the SDK atomically writes the original
WRIMP URLs, opening ID, campaign/content IDs, section/user scope and user snapshot under
Application Support/GravitySDK/visible-impressions. API-key/section namespaces use SHA-256
filenames; the current SDK API key is captured by its transport. URLs are never rebuilt or
rewritten using the current `setUser` identity. The original tracking URL identifies the
original user/event on the existing GET endpoint, which has no current-user request body.
Old-user events are therefore **sent as originally issued**, rather than dropped or attributed
to the next user. The saved user snapshot also preserves the original session context.
Pending protection is isolated by API key, section and user identity; changing session does
not let an undelivered event for the same user bypass it. Returning to that user restores
its pending protection. Explicit users and anonymous SDK UID have separate scopes.

The gate consults this same durable store before reservation **and** before presentation,
including after restart. An appeared presentation does not lose protection on close, screen
changes, or the old 60-second acknowledgement deadline. Successful URLs are durably removed
one by one. Only after all URLs return HTTP 2xx is the opening acknowledged; requests begun
before that ACK cannot reopen it, including when the queue was loaded without an in-memory
reservation. Fresh requests then use the server's frequency policy. There is no session-long
or permanent ban after successful delivery, and a fresh allowed opening can reuse a URL.
“No limit” / “every page view” campaigns may open again after acknowledgement.

Transient network failures and HTTP 408/429/5xx get three immediate attempts (250 ms and
1 s pauses), then another batch after 30 seconds. A network-restored `NWPathMonitor` signal
and SDK initialization also resume pending work. Closing or destroying UI does not cancel
these tasks. SDK reinitialization stops its previous monitor/retry loop and waits for its
current durable send before starting the successor. Newly enqueued work wakes the current
sender for that store. Store reload retains failed URLs and successful partial progress.

Malformed URLs and other non-retryable HTTP failures are retained as rejected entries without
automatic resends or a false ACK; their campaign remains protected while delivery is
unconfirmed. Missing WRIMP URLs and persistence failures are logged. A device storage failure
cannot be represented as successful persistence/delivery. Exactly-once network analytics
cannot be guaranteed across a process crash between server acceptance and the local write;
retries preserve the original tracking URL/event ID for backend deduplication.

The pre-existing non-modal `deliver(urls:)` path retains its URL coalescing/cache and three
immediate attempts. Only unconfirmed in-memory presentations retain the 60-second cleanup
fallback; confirmed modal delivery is governed by its durable outbox.

## Verification

`./scripts/test-core.sh` compiles production Foundation sources and runs the shared gate,
opening-state, outbox and HTTP transport regressions without UIKit. Run the complete package
test target on an iOS simulator with:

```sh
xcodebuild -scheme GravitySDK -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO test
```

Before release, run the host app against a non-production section:

1. Close each modal format at 100, 200 and 400 ms using swipe, X, host Back and “Not now”.
   Inspect opening animation frames, including bottom-sheet image preroll; WRIMP must
   correspond to visible content, not a scrim, and fire once before explicit dismissal.
2. Delay `/engagement` and navigate rapidly across screens. Parallel and stale requests
   must not re-present the campaign while its queue entry exists.
3. Go offline after appearance, close, kill/relaunch, then restore connectivity. Confirm
   the original URL is sent and the campaign stays protected until HTTP 2xx.
4. Change user A → B → A and section; confirm delivery retains A's original URL/context
   and protection does not leak into B or another section.
5. Cancel before appearance, background/remove the host and transition through steps.
   Confirm no synthetic impressions and no duplicate opening impressions.
6. Verify backend monthly caps and allowed repeats (“no limit” / “every page view”),
   and smoke-test unchanged inline, product tracking and snackbar behavior.

No backend schema, event name, URL contract or public SDK method changes are required.
