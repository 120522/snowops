# Snow Ops

Native SwiftUI iPhone/iPad snow-removal operations app, targeting **iOS 26** and **Xcode 26**. The source uses native tab bars, navigation stacks, forms, sheets, MapKit, SF Symbols, semantic colors and Liquid Glass map controls. No web view or external app dependencies.

**Status: substantial local development implementation, not production-ready.** Secure sign-in, a deployed multi-tenant backend, bidirectional automatic synchronization, background transfer and APNs delivery are not connected. The app says this explicitly and never labels queued work “synced.” This project has not been compiled or run on an Apple device because the authoring environment is Windows without Swift or Xcode. Do not use it as your only service record system until the release checks below pass.

## Open on a Mac

1. Open `SnowOps.xcodeproj` in Xcode 26 or newer. Select the `SnowOps` scheme.
2. Select your development team in Signing & Capabilities and change `com.snowops.app` to your bundle identifier.
3. Select an iOS 26 simulator or a connected device and Run.
4. In More → Settings & development access, select a sample administrator, manager or field employee to test each interface. This identity switch is development-only, not authentication.

The Xcode project is checked in. After adding Swift files, regenerate it with `node scripts/generate-project.mjs` (Node 22 or newer). An equivalent `project.yml` is included for teams already using XcodeGen; neither generator is required to open the checked-in project.

## Included workflows

- Administrator dashboard, seven-step storm setup, status transitions and progress.
- Separate customers/properties, customer editing and archiving, property setup/duplication, custom service names, rates, triggers and snowfall tiers.
- Crews, equipment descriptions, employee crew assignment and configurable manager permissions.
- Dispatch by crew, route reordering, reassignment, additional visits and documented stop exceptions.
- Field home, assigned route, status map, Apple Maps directions, visit start/timer, typed checklists, services, quantities, materials, library photo attachment, notes and issue reporting.
- Locally saved field edits, duplicate-start protection, required-work checks and authorized completion overrides.
- Completed visit history, audited corrections/cancellation with required reasons and retained original snapshots.
- Final snowfall recalculation, property billing breakdowns, independent calculated/final amounts, preserved overrides, review flags and finalization validation.
- Storm summaries, invoice-prep filters, copy/share, CSV/PDF export, and external-invoice “entered” tracking. Exports summarize one property/storm per row; the app creates no invoices.
- Search across names, addresses, customers, storms, crews, employees and visit notes.
- Ten realistic sample properties, three crews, five development identities, one active February 6 sample storm, tier and per-push pricing, and three completed visits.

## Architecture

`Sources/SnowOpsCore` is a Foundation-only Swift package: Codable value models, decimal pricing, validation, seed fixtures and safe CSV encoding. `SnowOps` separates feature views, shared UI, the observable operations store, persistence, transport and export services. `SnowOpsTests` exercises offline mutations and permission checks; `Tests/SnowOpsCoreTests` exercises domain behavior.

Entities use stable UUID foreign keys rather than copying customer/property objects into visits. A visit intentionally snapshots service pricing and checklist definitions at arrival, so later configuration changes cannot silently rewrite historical work. Route and crew relationships are represented by storm assignment ordering and employee IDs; there is no separate redundant route entity. Billing records hold final overrides and entered status alongside calculations.

### Local persistence

The local repository writes a versioned Codable envelope to Application Support with an atomic replacement and file protection until first unlock. Domain changes, audit history and a durable outbox commit together. Memory only changes after a successful write. A corrupt or unsupported file shows a recovery error and is preserved; the app never deletes it or reseeds over it. Photos live in protected Application Support files and their references live in visits. Unreferenced photo files can remain after a failed reference save; cleanup must not run before recovery has been assessed.

This is an appropriate replaceable local persistence boundary for a small development dataset, not a production-scale relational store. Audit snapshots exclude the audit array to avoid recursive growth. Full workspace snapshots and synchronous writes should be replaced with transactional row persistence, entity-scoped audit diffs and a migration strategy before large-scale use. There is no at-rest application-level encryption beyond iOS file protection and no implemented backup/restore UI.

### Synchronization and authentication boundary

`SyncTransport` provides a replaceable HTTPS upload boundary with authorization headers, idempotency keys and matching commit receipts. It is intentionally not scheduled or wired to a server in the development UI. **A transport interface is not a finished sync engine.** Outbox entries are never removed here. See `docs/PRODUCTION.md` for the server, auth, conflict, background and attachment requirements. Production roles must be derived from verified server identities; the local role selector cannot enforce cross-device security.

### Pricing rules

- All money uses `Decimal`, rounded to cents with `.plain`.
- Custom tiers are half-open `[lower, upper)`; a nil upper bound is open-ended. At exactly 6 inches, the tier beginning at 6 applies.
- Gaps may be configured, but a missing matching tier blocks calculation instead of silently charging zero. Overlaps and negative rates are rejected.
- Tier pricing is applied per completed, performed, billable visit. Each service can use a different pricing method. Per-inch multiplies snowfall by the recorded quantity; hourly uses recorded arrival/departure duration.
- An open tier can add an incremental rate above its lower boundary.
- Seasonal services contribute zero event billing. Manual services block calculation until an authorized correction supplies an explicit method/rate.
- Administrative overrides remain separate from calculations. Changing snowfall updates calculated values and flags affected totals without erasing overrides.
- Correcting completed work invalidates review. Stale totals cannot be accepted or finalized without recalculation.
- Finalization locks storm/service/billing edits. Marking an invoice-prep record entered remains allowed after finalization.

## Verification

On a Mac with Xcode 26:

```sh
swift test
xcodebuild -project SnowOps.xcodeproj -scheme SnowOps -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Choose an installed simulator name if iPhone 17 is unavailable. On Windows the available check is `node scripts/check-project.mjs`; it checks source inventory and project references, **not Swift compilation or behavior**.

Tests cover tier boundaries, multiple visits, additional-inch rates, duration billing, cancellation, missing/overlapping tiers, manual pricing, snapshots, required responses/photos, finalization blockers, CSV formula injection, serialization, durable offline visits, duplicate starts, role restrictions, failed local writes and override-preserving recalculation. Test sources are provided; XCTest execution is still unverified.

See `docs/WORKFLOW-ACCEPTANCE.md` for the requested end-to-end device acceptance script and `docs/PRODUCTION.md` for the remaining release work.
