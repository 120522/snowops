# Device acceptance script

These steps are pending execution on an Apple device/simulator. The demo uses a single local dataset; switch identities in Settings to exercise local roles. This does not test actual assignment delivery between employees.

## Customer and property

As administrator: More → Customers → add a customer with contact details. Properties → add property → choose customer → location and coordinates → add snow service → select snowfall tier → define nonoverlapping tiers → add photo requirement if desired → assign a reusable checklist → instructions/hazards → review/save. Open the property and verify service rules. Duplicate it and confirm its ID is independent. Archive/restore the customer and check that existing visit references survive.

## Storm setup

First wrap up the seeded February storm and move it to review to free the active slot. Storms → new storm → enter forecast/operational snowfall → select properties → inspect triggered services and manually override inclusion → assign crews → review → activate. Check dashboard counts and dispatch crew grouping. Reorder stops using Edit. Reassign an unstarted stop to another crew.

## Field service

Switch to the assigned field identity. Home must show only its crew’s route. Open next stop, launch Apple Maps, return, start visit. Repeated start must continue the existing visit. Attempt completion with missing required checklist answers: it must fail. Complete checkbox/yes-no/number/text/photo/confirmation responses where configured. Record materials, selected services and quantities, notes and a library photo. Report an issue. Complete service. Return to route and open the next stop.

Terminate/reopen the app with an active visit, then with a completed visit. Verify times, notes, checklist values, photos and pending changes survive. Switch to another field crew and verify edit/dispatch permissions reject unauthorized operations. A field identity without a crew must receive no route, not every crew’s route.

## Admin monitoring

Switch to administrator. Check progress and issue visibility. Resolve the issue. Add an additional visit to a completed property and perform it. Correct the completed record with a reason. Verify original snapshots, editor identity and correction reason in audit history. Cancel an erroneous completed visit and confirm the property becomes Needs Attention if no other completed visit accounts for that stop. Account for an unstarted stop using a documented exception.

## Post-storm

Wrap up → under review. Open review, enter verified snowfall and recalculate. Inspect the property service breakdown. Set a final amount override with a reason and mark reviewed. Change snowfall across a tier boundary. Verify calculated amount changes, manual final amount remains intact, and affected rows need review. Correct a service record and try reviewing its stale calculated total: it must require recalculation.

Attempt finalization with unaccounted stops, incomplete visits, unresolved issues, missing snowfall, unreviewed bills or undocumented adjustments. Each must block finalization. After resolving every blocker, finalize and verify service/billing controls lock. Open invoice prep, filter Ready, export CSV/PDF and share. Mark a record Entered and verify filters; no actual invoice is created.

## Production-only acceptance

Secure login, assignment notifications, two-device crew delivery, offline conflict recovery, background sync and photo uploads cannot be tested in this local build. Repeat the complete workflow with deployed production services and physical devices before release.
