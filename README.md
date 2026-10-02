# Snow Ops

Snow-removal operations in a browser, built with **plain HTML, CSS, and JavaScript**. No framework, build step, Xcode, Apple signing, or external runtime dependencies are required. The native iOS implementation is retained as a reference; the web app is the default development workflow.

## Run locally

Install Node.js 22 or newer. In Terminal:

```sh
cd /Users/cameron/Documents/snowops
npm start
```

Open **http://localhost:3000** in your browser. Leave Terminal running; press Control-C to stop. On another machine use that machine’s repository path. `PORT=3001 npm start` uses a different port. Use the same address and port each time: browser data is specific to a site origin.

You can host the contents of `web/` on any static HTTPS host. Hosting makes the interface accessible; it does not add shared data or authentication. Plain HTTP on a remote machine is unsupported because the app uses secure-context browser APIs. Localhost is supported for development.

## Included workflows

- Responsive administrator overview and field home with crew-scoped routes.
- Storm preparation, property selection, crew assignment, activation, wrap-up, review and finalization.
- Customers with contacts and archive status; properties with instructions, hazards, custom services, snowfall tiers, typed checklists and independent duplication.
- Crew/equipment editing, employee crew assignment and manager permissions.
- Dispatch reordering, reassignment, additional visits and reasoned stop exceptions.
- Visits with duplicate-start protection, original pricing/checklist snapshots, materials, notes, JPEG/PNG/WebP photo attachments, required-work validation and authorized overrides.
- Local visit history, completed-record corrections/cancellation with reasons, before/after audit snapshots (photo metadata rather than duplicated image bytes) and billing invalidation.
- Exact decimal money calculation, snowfall recalculation, separate final overrides, billing review and finalization blockers.
- Invoice preparation filters, CSV download, browser Print / Save PDF and external-invoice entered tracking. No actual invoices are created.
- Search in customers, properties, routes and visit history; JSON workspace backup downloads and recovery downloads when saved data cannot be opened.

The development identity selector previews roles; **it is not authentication**. Client permission checks keep the demo workflows consistent, but a deployed backend must enforce security.

## Local records

A versioned JSON envelope in browser localStorage commits records, audit snapshots and pending changes in one write. Memory updates only after that write succeeds. Invalid/unsupported saved data is preserved and exposes a recovery download. Stale-tab writes are rejected when a changed revision is detected; simultaneous cross-tab edits are not supported. Use one editing tab per workspace.

Photos are saved in that same envelope (input limit 10 MB, resized to 1280 pixels with a bounded JPEG size). Browser storage quotas are small, full snapshots grow with each edit, and there is no production attachment store. If a save fails, the app displays the error and leaves the previously saved workspace intact. Download backups regularly, especially before clearing site data. Private browsing and browser cleanup can remove local records. Pending changes are never labeled synced and are never removed in this demo.

Native iOS files are **not automatically imported** into the browser. Preserve existing native records until an explicit migration is built and verified. The web backup format is not a Swift Codable import format. Backup restoration UI is not implemented.

Money inputs use decimal strings, with up to six fractional places; calculations use BigInt fractions and cent rounding. Tier bounds are lower-inclusive and upper-exclusive. Missing/overlapping tiers and manual pricing block calculation. Changed billing retains overrides but requires another review.

## Checks

```sh
npm test
npm run check
```

The first runs Node’s built-in domain tests. The second checks JavaScript syntax and retained native source/project references. Neither requires dependencies.

Optional browser acceptance (development dependency only):

```sh
npm install --no-save --package-lock=false playwright
npx playwright install chromium
node scripts/test-web-browser.mjs
```

Alternatively, point `CHROMIUM_PATH` at an installed Chromium/Chrome executable. The smoke script starts a browser against the running server and covers real controls, persistence, crew permissions, billing and mobile layout. `SNOWOPS_URL` changes the server address. See `docs/WEB-ACCEPTANCE.md` for manual checks.

## Remaining production work

See `docs/PRODUCTION.md`. Secure sign-in, multi-tenant backend storage, automatic bidirectional sync, photo uploads, cross-device dispatch and push notifications require deployed services. Browser-based offline shell caching, backup restoration, large-dataset storage and automatic migrations remain unfinished. Opening this local app does not prove production readiness.

The retained Swift project and its Xcode-specific requirements are described in `docs/NATIVE-IOS.md`.
