# Browser acceptance

Run `npm start` and use a stable localhost origin. These are local demo workflows, not backend delivery tests.

1. As Alex Morgan, add/edit a customer and property. Configure custom service names, half-open snowfall tiers, photo requirements and typed checklist items. Duplicate a property, edit the copy and verify the original remains independent.
2. Prepare a storm with selected properties and crews. Activate only after the previous storm moves into review. In Dispatch move unstarted stops up/down, reassign a crew, dispatch another visit and account for an unstarted stop with a reason.
3. Select Cameron Davis. Confirm only Snow 1 route and history are visible. Start a visit; a second start continues it. Completion must fail with missing required work. Fill checklist responses, quantities, materials and notes. Attach a JPEG/PNG/WebP photo and save, reload, reopen and verify it survives. Check typed required photo items select real attached photos.
4. Report an issue. As admin resolve it. Correct completed work with a reason; verify the original snapshot in Audit history. Cancel a visit and confirm its stop needs attention unless another completed visit exists.
5. Move storm through Wrapping up and Under review. Verify snowfall, review bills, set a reasoned override, change snowfall across a boundary and verify the override survives while changed totals need review. Changed services must be recalculated before billing can be accepted.
6. Attempt finalization with unaccounted stops, active visits, unresolved issues, missing snowfall or unreviewed billing. All must block it. Resolve all blockers, finalize and confirm edits lock. Export invoice CSV, Print / Save PDF, mark entered and check the filter.
7. Download a JSON backup. Test a failed browser-storage write and verify saved data does not disappear. Do not clear real records to test this; use a separate test browser profile. Open two tabs, edit one and confirm the other rejects stale writes until reloaded.
8. Check narrow iPhone layouts, keyboard-only navigation, labels, visible focus, 200% zoom, contrast and real Safari photo/print behavior. Demo role controls are not secure authentication.

The automated `scripts/test-web-browser.mjs` exercises a representative path. No backend, push, offline cold launch, native migration or Apple-device validation is implied by its results.
