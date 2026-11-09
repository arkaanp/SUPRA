# Test incident report

> Current demo baseline: `main` application commit `967a477` (2026-11-09).
> Documentation imported from `docs/testing`; application changes on that branch
> are excluded. Results below distinguish current checks from earlier branch evidence.

## Incidents by testing step

| Step | Current status |
|---|---|
| 1. Unit testing | No failing assertion in the recorded package checks |
| 2. Integration testing | Dedicated DB run outstanding; account API trace needed for INC-001 |
| 3. System testing | INC-001 account-refresh warning and INC-005 live demo coverage remain open |

## INC-001 — Account refresh unavailable

**Status: open, exact failing request unconfirmed.** User reports the banner:
“Account refresh unavailable. Last-known conditions can still be shown as stale.”

`SupraService.loadAccount()` synchronizes profile, trips, alerts/inbox and
preferences. The shell stores the caught error but displays a generic message.
Any required request or JSON decoding failure can trigger this banner.

### Current evidence

- Local backend readiness returned 200.
- Configured schema contains the newer trip/notification columns and commute tables.
- Mobile and backend Supabase project configuration matches.
- Client API address defaults to localhost because the local config lacks
  `SUPRA_API_URL`; confirm reachability on the presentation device.
- Reading notifications also evaluates alerts and calls providers. The client
  request deadline is 15 seconds, so this is a possible timeout path.

The imported diagnosis of a definitely missing migration is not established for
this environment. Schema presence does not close the incident; account loading
must succeed with an authenticated demo session.

### Next reproduction

Sign in, press Retry, capture the failing endpoint/status and sanitized backend
error. Check profile upsert, trip decoding, notification load latency and
preferences separately. Confirm token acceptance and actual device API URL.
Do not apply migrations solely on the strength of this generic banner.

### Closure

Account refresh succeeds and a trip can be confirmed and reloaded. Record the
request trace and outcome without tokens or personal data.

## INC-005 — Live demo coverage incomplete

Open. Real recovery email/callbacks, transit GTFS, provider credentials, actual
UI/device rendering and complete cross-account demo need manual verification.

## Historical incidents

Compile/analyzer/fixture corrections and 16:9 fixes in the source documentation
belong to their recorded branch revisions. See the original incident report via
Git history; the docs-only merge does not deliver additional app fixes.

## INC-001 update — timeout fixes applied

The desktop session stored before the fix was expired; authenticated reads with
it returned 401. After backend rebuild and Flutter restart, the session refreshed
and profile/trip reads returned 200. This supports a shared authentication-path
contribution to the reported trip/upload/account timeouts; the exact original
stall was not captured. Refresh transport and JWT/DB waits are bounded, and
provider evaluation is removed from inbox reads. Isolated avatar/trip integration
passes. Keep the incident open pending the user's upload and trip retries.
