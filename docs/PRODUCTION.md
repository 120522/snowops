# Production completion requirements

This document describes work still required, not capabilities currently delivered.

## Web conversion

The default development workflow is now the plain JavaScript browser app in `web/`; Xcode is not required to run it. The following native implementation notes remain relevant to the retained iOS reference, but browser delivery needs different platform integrations:

- Replace localStorage and whole-workspace audit snapshots with versioned transactional IndexedDB storage, bounded entity audit diffs, attachment blobs and tested migrations. Browser quota/eviction, private browsing and simultaneous-tab writes must be covered. The current demo checks stale revisions but is not a multi-tab transactional database.
- Implement a service worker and offline shell caching before claiming reload/launch works without the server. Locally loaded pages can save while offline, but cold offline startup is not implemented.
- Use browser-compatible OIDC Authorization Code with PKCE and a reviewed token/session architecture. Do not place production credentials in localStorage. Enforce all permissions and tenant ownership on a real server.
- Implement change feed pulls, typed mutation delivery, acknowledgements, attachment storage and conflict recovery. Static hosting alone does not create a backend.
- Browser Web Push requires HTTPS, a service worker, permission and a deployed subscription/push service. iOS browser background behavior differs from a native app; do not promise guaranteed background delivery.
- Provide browser backup restore/recovery, native-to-web data migration, service/site photos, full checklist-template inheritance, a geographic dispatch map, expanded reports and outstanding product requirements listed below.
- Validate Safari on actual iPhones/iPads, Chrome/Firefox desktop, keyboard focus, screen readers, zoom, touch sizes, print pagination, interrupted saves, quota errors and contract totals before operational use.

The web app uses local development identities and sample data. It is not a production record system or a substitute for deployed multi-tenant services.

## Backend and tenancy

Implement an authenticated organization-scoped relational backend. Keep separate tables for user membership, employee, crew, crew membership, customer, property, property service, pricing rule/tier, checklist template/item, storm, assignment/route order, visit, visit service snapshot, checklist response, material usage, photo metadata, issue, billing adjustment, invoice-prep record and append-only audit event. Every child foreign key must belong to the same organization; UUID possession must never confer access.

Enforce permissions and state transitions on the server for every write. Managers can use only granted capabilities. Field identities can read their assigned routes and write their own crew’s visits, responses, notes, materials, photos and issues. Field users cannot alter contracted rates or billing amounts. Calculate money server-side too, comparing the client result without trusting it.

Use database transactions for visit lifecycle updates, assignment status, billing invalidation, audit append and receipt creation. Preserve created timestamps and user-provided original arrival timestamps separately from server receipt times. Audit actor IDs come from the authenticated session. Never rely on the client-supplied actor or device clock for authorization or proof of server receipt.

## Authentication

Provide a selected OIDC/OAuth identity service using Authorization Code with PKCE and system browser sign-in, scoped organization invitations, expiring access tokens, refresh rotation, revocation, secure Keychain storage and explicit sign-out/device ownership handling. Remove the development identity picker and sample records from distribution builds. Do not mix tenant data when sessions change. Decide whether previously downloaded routes remain readable after token expiration, and whether a lost-device revocation should erase protected local data after acknowledgement.

## Mutation delivery

The existing development transport proposes:

```
POST /v1/mutations
Authorization: Bearer <token>
Idempotency-Key: <audit-event UUID>
Content-Type: application/json

200 { "mutationID": "<matching UUID>", "committed": true }
```

Do not deploy the full-workspace development snapshot format as an unrestricted write endpoint. Replace it with typed, organization-bound entity commands carrying immutable mutation IDs, per-entity base revisions and attachments. A repeated idempotency key must return the original receipt; reuse with a different payload must fail. Apply only whitelisted field patches and reject forbidden changes even if the UI omitted those controls.

Persist acknowledgements and remove only the specifically acknowledged outbox entries in the same local transaction. Serialize queue draining with an actor. Retry timeouts and transient server failures using bounded exponential backoff and jitter, preserving payloads across crashes. Pause and surface revoked/expired credentials; never discard queued work on authorization failure. Expose actual Synced, Pending Sync, Offline and Sync Error states only from real connectivity and receipts.

Add an ordered server change feed with persistent cursors, pagination and tombstones for pulling dispatch changes. Resolve version conflicts explicitly. Never use last-write-wins for completed service or billing records; retain both versions and require a manager reason. Concurrent starts need a server-enforced active-visit constraint and a conflict review path that preserves both local observations. Preserve canceled records rather than deleting them.

## Background and photos

Use BGTaskScheduler for best-effort catch-up and background URLSession for resumable attachments. Persist upload IDs and local file paths. iOS background execution is opportunistic, so foreground resume and app activation must also drain/pull. Register APNs capabilities and device tokens with the backend. Push assignment notifications only after server commit; notification receipt must trigger an authorized change-feed fetch, not blindly apply arbitrary payload data.

Upload photos to organization-scoped storage using bounded/resumable transfers, file checksums, protected local originals and metadata acknowledgements. Photos and required photo checklist items must not be marked synced until both bytes and record references are acknowledged. Add camera capture, issue-specific photos, optional location permission/capture and service-site images/maps. The development build currently attaches library images and has no GPS capture switch.

## Product completion

Remaining requested capabilities include site photos/maps in property setup, service/crew/storm checklist-template inheritance, service-specific crew types, richer equipment records, issue photo attachment, visit duplication and arbitrary crew corrections, manager review reporting, activity notifications and a full relational persistence migration. Reports currently consist of storm summary, invoice preparation and visit/audit history. Dispatch reordering uses native Edit/reorder controls rather than drag-and-drop between crews. PDF export currently summarizes property/storm totals rather than every service line.

Add app icon/launch branding, organization configuration, operational snowfall updates with distinct history, configurable forecast time zones, location consent and retention policy, privacy disclosures, migration fixtures, local data recovery/export and an attachment retention policy.

## Release gates

1. Compile with Xcode 26 and run both test suites; repair compiler/runtime issues.
2. Complete the device acceptance script; test real iPhone/iPad layouts, VoiceOver, largest Dynamic Type, Dark Mode, Increase Contrast, Reduce Transparency and Reduce Motion.
3. Test airplane mode, process termination, power loss around transactions, interrupted image saves, low disk space, expired credentials, revoked memberships, duplicate delivery and server conflicts on two physical devices.
4. Validate totals against real customer contracts, including seasonal inclusion, per-visit snowfall tiers and invoice-prep aggregation.
5. Review backend authorization, tenant isolation, database migrations, backups, APNs, Keychain and threat model with deployed infrastructure.
6. Archive, sign, run on devices, distribute through TestFlight and observe crash/sync diagnostics that redact customer notes and photos.

Passing the local development tests alone does not satisfy these release gates.
