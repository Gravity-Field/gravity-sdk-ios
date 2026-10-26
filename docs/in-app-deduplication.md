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
(the host's Back route) confirm an already appeared window before starting dismissal,
including an explicit host close after the app has become inactive. Activity is required
when confirming the content frame, not when closing an already appeared window.
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
Snackbar retains its existing `onAppear` impression path. It has no visible-impression
geometry detector and does not use the modal display-link probe or durable modal outbox.

## Durable modal delivery

`VisibleImpressionDelivery` owns a minimal file-backed outbox; it is independent of UI
lifetime. Before sending a network WRIMP, the SDK atomically writes the original
WRIMP URLs, opening ID, campaign/content IDs, creation timestamp and stable section/user
identity scope under Application Support/GravitySDK/visible-impressions. API-key/section namespaces use SHA-256
filenames; the current SDK API key is captured by its transport. URLs are never rebuilt or
rewritten using the current `setUser` identity. The original tracking URL identifies the
original user/event on the existing GET endpoint, which has no current-user request body.
Old-user events are therefore **sent as originally issued**, rather than dropped or attributed
to the next user. No full `User` JSON, session snapshot or host `attributes` are persisted;
the stable scope is sufficient for isolation and the issued URL preserves event attribution.
Existing records with a `user` snapshot are rewritten without that field on load, preserving
their URL, scope and timestamp. Necessary identifiers or backend-issued URLs may themselves
contain user information; this is a minimal delivery record, not an anonymized event.
Pending protection is isolated by API key, section and user identity; changing session does
not let an undelivered event for the same user bypass the remaining 24-hour window.
Returning to that user restores its remaining protection without resetting the timestamp. Explicit users and anonymous SDK UID have separate scopes.

The gate consults this same durable store before reservation **and** before presentation,
including after restart. An appeared presentation does not lose protection on close or screen
changes. Local
protection lasts at most **24 hours from the persisted show timestamp**, or until delivery
HTTP 2xx / permanent drop / capacity eviction, whichever occurs first. The same timestamp is
used after restart. Active network attempts never extend the 24-hour window.
Successful URLs are durably removed one by one. Only after all URLs return HTTP 2xx is the opening acknowledged; requests begun
before that ACK cannot reopen it, including when the queue was loaded without an in-memory
reservation. Fresh requests after acknowledgement or protection expiry use the server's
frequency policy.
Protection expiry releases both durable and in-memory reservations **without an ACK fence**.
“No limit” / “every page view” campaigns use this same 24-hour protection policy while delivery
is pending, with no special case; a fresh allowed opening can reuse a URL. A later opening
creates its own event/timestamp while older events remain deliverable.

Transient network failures and HTTP 408/429/5xx get three immediate attempts (250 ms and
1 s pauses), then batches with exponential backoff: 30, 60, 120, 240, 480 and at most
900 seconds. A new insertion or network-restored `NWPathMonitor` signal resets the delay
and wakes delivery immediately; repeated satisfied-path updates do not reset it.
SDK initialization also resumes pending work. Closing or destroying UI does not cancel
these tasks. SDK reinitialization stops its previous monitor/retry loop and waits for its
current durable send before starting the successor. Newly enqueued work wakes the current
sender for that store. Store reload retains failed URLs and successful partial progress.
Reinitializing with a different API key/section starts only that namespace; the previous
namespace resumes when initialized again, subject to the same 7-day TTL and cleanup.

Malformed URLs and non-retryable HTTP failures (other 4xx) **drop the entire queued WRIMP**
and release its in-memory/durable protection without an ACK sequence fence. Legacy rejected
entries from the first outbox version are dropped on load as well. Every entry has a **7-day
delivery TTL from creation**, preserved across restarts. Delivery retention is independent
of the 24-hour protection window: at 24 hours the event stays queued and continues retries
with its original URL/user, including after network restoration or restart. At 7 days it is
removed and is never sent again. Existing files without a timestamp receive a persisted
timestamp on migration. The queue holds at most **256 openings per API-key/section namespace** and **1 MiB** of encoded
JSON. Insertion removes expired entries first, then evicts the oldest live openings until
both count and byte budgets fit, retaining the new WRIMP. Only an opening that exceeds
1 MiB by itself is rejected without overwriting existing events. Delivery TTL, terminal
drop and eviction deliberately trade delivery for restoring server-controlled presentation
policy; none is reported as a successful server ACK.

Each opening attempts WRIMP persistence only once. Missing WRIMP URLs or disk failure stop
the display-link probe, emit one local-only error (no error-report POST), and still emit the
host's `ContentVisibleImpressionEvent` and custom action once. These failures retain the
ordinary EGO-248 **60-second presentation fallback even after close/disappearance**.
It expires without a server ACK; no 24-hour protection is applied to a failed write or missing
URL. No per-frame or close-triggered disk retries occur for that opening. A callback
reports actual appearance and does not assert successful persistence or HTTP delivery.

Corrupt JSON is logged locally; a `.corrupt` diagnostic file contains only sanitized,
decodable minimal records, never a copy of the raw potentially sensitive input. Valid records
from a partially corrupt array survive; unknown fields are ignored. A namespace's previous
quarantine is removed on its next load, including legacy quarantines containing user snapshots.
An unreadable file is preserved and retried before mutations/drain, never overwritten as an
empty queue. A persistent storage-read failure cannot reconstruct unknown pending protection.
The queue directory and each atomically replaced file are excluded from iCloud/iTunes backup.
iOS writes explicitly use complete-until-first-user-authentication file protection.
Quarantine inherits its directory's no-backup exclusion. SDK store diagnostics use
`GravityLogger` with `sendToBack: false`, honoring logLevel and the host logListener; logging
is deferred until after initialization to avoid recursive singleton creation.

Startup loading, migration and first-frame persistence run on a serial background store queue.
Until restoration finishes, the gate temporarily refuses automatic reservations in that
namespace, so it cannot race the restored protection set. On a confirmed frame the store
sets staged in-memory protection synchronously; dismissal and navigation can then proceed.
The worker atomically persists the entry, promotes its gate protection, and only then wakes
delivery and emits the host appearance callback (which may arrive after UI dismissal). A failed write removes staged protection and
retains only the bounded 60-second fallback. Delivery cannot see an unpersisted staged entry.
UI gate reads use a separate in-memory snapshot and never wait for ACK filesystem writes.
Encoded record sizes are cached between mutations; bounds remain 256 entries / 1 MiB.
As with any asynchronous write, a process killed before the initial write completes can lose
that not-yet-durable event; it has not been sent. Successfully persisted entries survive restart.
Successful durable sends stay cached until local removal succeeds, so a temporary ACK-write
failure does not cause an in-process resend when the ordinary 15-minute cache expires.
Drain remains sequential across openings; a slow endpoint can delay later entries by the
existing transport timeout/retry budget.

After loading, background maintenance performs a bounded shallow sweep of neighboring `*.json`/`*.corrupt`
files and removes orphaned snapshots whose mtime is older than the 7-day delivery TTL. It
checks metadata for at most 256 candidates and deletes at most 32 files per pass, rotating
the scan position for later initializations. The current namespace, fresh files, directories
and symbolic links are retained. Sweeping is serialized with SDK file readers/writers so a
concurrent atomic write cannot be removed using stale mtime metadata. Inactive files are
cleaned on later store constructions, including the next process start or a new namespace;
reinitializing an already cached store does not trigger another pass. There is no autonomous
filesystem timer.

Exactly-once network analytics cannot be guaranteed across a crash between server acceptance
and the local write. Retries preserve the original URL/event ID for backend deduplication.

The pre-existing non-modal `deliver(urls:)` path retains its URL coalescing/cache and three
immediate attempts. Unconfirmed presentations and appeared modals without a persisted WRIMP
retain the bounded 60-second cleanup fallback; persisted modal delivery uses its durable outbox.

## Verification

`./scripts/test-core.sh` compiles production Foundation sources and runs the shared gate,
opening-state, outbox and HTTP transport regressions without UIKit. Run the complete package
test target on an iOS simulator with:

```sh
xcrun simctl list devices available
# Replace SIMULATOR_UDID with an available iOS simulator's ID from the list above.
xcodebuild -scheme GravitySDK -destination "platform=iOS Simulator,id=SIMULATOR_UDID" CODE_SIGNING_ALLOWED=NO test
```

Tests use temporary outbox directories, including SDK singleton integration tests. Simulator
coverage includes a real CADisplayLink sampling a committed SwiftUI presentation layer (the
package runner's missing scene activity is injected), actual SwiftUI `onDisappear`, and the
sheet binding/onChange/onWillDismiss/removal path used by swipe and backdrop. Real touch
gesture recognition and foreground-scene lifecycle still need host-app/device QA.

Before release, run the host app against a non-production section:

1. Close each modal format at 100, 200 and 400 ms using swipe, X, host Back and “Not now”.
   Inspect opening animation frames, including bottom-sheet image preroll; WRIMP must
   correspond to visible content, not a scrim, and fire once before explicit dismissal.
2. Delay `/engagement` and navigate rapidly across screens. Parallel and stale requests
   must not re-present the campaign while its queue entry exists.
3. Go offline after appearance, close, kill/relaunch, then restore connectivity. Confirm
   the original URL is sent. Confirm protection before 24 hours, release at 24 hours across
   restart without dropping the queued event, retries until the 7-day delivery TTL, and
   immediate release on HTTP 2xx/permanent drop. Exercise active-send, count/byte eviction,
   invalid URL and delivery TTL boundaries; only HTTP 2xx creates an ACK fence.
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
