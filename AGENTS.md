# Snow Ops development

The default app is now a plain HTML/CSS/JavaScript web application in `web/`, served by `npm start`. A native iOS 26 SwiftUI application and Foundation-only Swift package, `SnowOpsCore`, are retained as reference. Read README.md and docs/PRODUCTION.md before making production-readiness claims.

## Layout

- `web/`: responsive browser interface, exact decimal domain calculations and local persistence.
- `tests/web/`: Node domain tests; `scripts/test-web-browser.mjs`: optional real-browser acceptance.
- `scripts/serve-web.mjs`: dependency-free static development server.

- `SnowOps/`: native app, feature views, operations store, local persistence and transport boundary.
- `Sources/SnowOpsCore/`: domain models, decimal pricing, validation and exports.
- `Tests/SnowOpsCoreTests/`: portable Swift package tests.
- `SnowOpsTests/`: Apple-platform application tests.
- `scripts/generate-project.mjs`: deterministic Xcode project generator (Node 22+).
- `scripts/check-project.mjs`: source/project checks, not compilation.

## Checks

For web changes, run `npm test`, `npm run check` and the browser smoke check when Chromium/Playwright are available. Preserve HTML escaping and test monetary/permission invariants.

Run `node scripts/check-project.mjs` and `git diff --check` for changes. Run `swift test` when a compatible Swift 6 toolchain is available. Run the app tests using Xcode 26 on macOS; a Linux cloud environment cannot compile SwiftUI, MapKit, PhotosUI or UIKit. Report exactly which checks ran and which remain unverified.

Regenerate the checked-in Xcode project with `node scripts/generate-project.mjs` after adding or removing application/test Swift files. The portable package discovers its sources automatically.

## Invariants

- Preserve field-first large actions and accessible responsive web navigation. Keep the retained native reference intact unless the task concerns it.
- Never discard local records on load, persistence or network failure.
- Commit data, audit history and pending mutations atomically. Publish state only after a successful write.
- Do not claim backend sync, authentication or push delivery works until implemented and tested with a real server.
- Use decimal strings and BigInt fractions/cents for web money, or Decimal in native code. Custom tiers use inclusive lower/exclusive upper boundaries. Missing tiers must raise an explicit review error.
- Preserve service/checklist snapshots, original timestamps and calculated amounts separately from administrative overrides.
- Require authorization and a reason for completed-record corrections. Recalculate and review changed billing before finalization.
- Field users see only their crew's route. An unassigned identity must never receive every crew's route.
- Never add controls that imply a working feature without implementing the action or labeling it unavailable.

The sample identity selector is development-only and must be removed or gated before distribution. The user explicitly requested the web conversion. Develop the web app by default; avoid adding frameworks or build dependencies without a clear need.
