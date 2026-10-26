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
This also means `ContentVisibleImpressionEvent` and custom `onVisibleImpression` notifications
occur once for the initial step, rather than once per later step. A custom action different
from `visible_impression` now sends its existing action URL **in addition to** WRIMP (previously
it replaced WRIMP); the custom action retains its existing best-effort delivery path.
iOS has no system Back button for these SDK-owned fullscreen/over-fullscreen controllers;
host Back handlers use the existing `dismissInApp(contentId:completion:)` API.

Inline-block and product-card visibility detectors and product tracking are unchanged.
Snackbar retains its existing geometric detector and delivery path; it does not use the new
modal display-link probe or durable modal outbox.

## Durable modal delivery

`VisibleImpressionDelivery` owns a minimal file-backed outbox; it is independent of UI
lifetime. Before sending a network WRIMP, the SDK atomically writes the original
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
changes, or the old 60-second acknowledgement deadline, while its bounded queue entry exists. Successful URLs are durably removed
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

Malformed URLs and non-retryable HTTP failures (other 4xx) **drop the entire queued WRIMP**
and release its in-memory/durable protection without an ACK sequence fence. Legacy rejected
entries from the first outbox version are dropped on load as well. Every entry has a **7-day
TTL from creation**, preserved across restarts; expired events are never sent and no longer
block presentation. Existing files without a timestamp receive a persisted timestamp on
migration. The queue holds at most **256 openings per API-key/section namespace**; insertion
replaces expired entries first, then evicts the oldest live openings if necessary. Queue
serialization is capped at **1 MiB**; an oversized new entry is rejected without overwriting
existing events. TTL, terminal drop and eviction deliberately trade delivery for restoring
server-controlled presentation policy; none is reported as a successful server ACK.

Each opening attempts WRIMP persistence only once. Missing WRIMP URLs or disk failure stop
the display-link probe, emit one local-only error (no error-report POST), and still emit the
host's `ContentVisibleImpressionEvent` and custom action once. These failures retain the
ordinary 60-second presentation fallback; passive/explicit close can release the unpersisted
reservation. No per-frame or close-triggered disk retries occur for that opening. A callback
reports actual appearance and does not assert successful persistence or HTTP delivery.

Corrupt JSON is logged locally and moved to a `.corrupt` file (one retained quarantine per
namespace). Valid records from a partially corrupt array survive; unknown fields are ignored.
An unreadable file is preserved and retried before mutations/drain, never overwritten as an
empty queue. A persistent storage-read failure cannot reconstruct unknown pending protection.
The queue directory and each atomically replaced file are excluded from iCloud/iTunes backup.
Quarantine inherits its directory's no-backup exclusion.

The bounded startup read and atomic persist-before-close write remain synchronous. This is
intentional: asynchronous enqueue would allow UI dismissal or process termination before
persistence, and asynchronous startup would allow a reservation before restored protection
is known. Directory preparation happens once per store, and the 256-entry/1-MiB bounds limit
work; network sends, retries and subsequent ACK writes are owned by the background actor.
Successful durable sends stay cached until local removal succeeds, so a temporary ACK-write
failure does not cause an in-process resend when the ordinary 15-minute cache expires.
Drain remains sequential across openings; a slow endpoint can delay later entries by the
existing transport timeout/retry budget. Inactive API-key/section files are checked/pruned
when their namespace is initialized; no cross-namespace filesystem sweeper is introduced.

Exactly-once network analytics cannot be guaranteed across a crash between server acceptance
and the local write. Retries preserve the original URL/event ID for backend deduplication.

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
   the original URL is sent and the campaign stays protected until HTTP 2xx, terminal drop,
   capacity eviction or the 7-day TTL. Exercise HTTP 400/invalid URL and TTL expiration to
   confirm release without an acknowledgement fence.
4. Change user A → B → A and section; confirm delivery retains A's original URL/context
   and protection does not leak into B or another section.
5. Cancel before appearance, background/remove the host and transition through steps.
   Confirm no synthetic impressions and no duplicate opening impressions.
6. Verify backend monthly caps and allowed repeats (“no limit” / “every page view”),
   and smoke-test unchanged inline, product tracking and snackbar behavior.

No backend schema, event name, URL contract or public SDK method changes are required.

## Release and rollback

Release iOS independently after device QA, first to a pilot app. Verify the backend campaign
cap and allowed repeats before broad rollout. Rollback by pinning the previous SDK version;
older SDKs ignore this queue file. On upgrading again, normal TTL/drop rules apply to saved
events. Initialize the SDK from the host's UI/main-thread startup path; the public API remains
source-compatible and is not newly annotated with `@MainActor`.
