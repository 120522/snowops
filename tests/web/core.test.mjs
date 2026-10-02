import test from 'node:test';
import assert from 'node:assert/strict';
import {
  Store,
  seed,
  id,
  total,
  pricingLines,
  completionProblems,
  finalizationProblems,
  csv,
  STORAGE_KEY,
} from '../../web/core.js';
class MemoryStorage {
  data = new Map();
  fail = false;
  getItem(key) {
    return this.data.get(key) ?? null;
  }
  setItem(key, value) {
    if (this.fail) throw new Error('Storage quota exceeded');
    this.data.set(key, value);
  }
}
const setup = () => {
  const storage = new MemoryStorage();
  const store = new Store(storage);
  return { store, storage };
};
const performed = (service, overrides = {}) => ({
  id: id(),
  arrival: '2026-02-06T00:00:00Z',
  departure: '2026-02-06T01:30:00Z',
  canceled: false,
  billable: true,
  services: [
    {
      name: 'Plowing',
      trigger: '0',
      rate: '0',
      quantity: '1',
      performed: true,
      tiers: [],
      ...service,
    },
  ],
  ...overrides,
});
test('half-open tiers, extra inch rates, exact rounding and multiple visits', () => {
  const visit = performed({
    method: 'snowfallTier',
    tiers: [
      { lower: '0', upper: '6', amount: '475', additional: '0' },
      { lower: '6', upper: '', amount: '650', additional: '80' },
    ],
  });
  assert.equal(total([visit], '5.999'), '47500');
  assert.equal(total([visit], '6'), '65000');
  assert.equal(total([visit, visit], '7.5'), '154000');
  assert.equal(total([performed({ method: 'perVisit', rate: '0.105' })], '0'), '11');
  assert.equal(total([performed({ method: 'perVisit', rate: '0.1', quantity: '3' })], '0'), '30');
});
test('hourly, per-inch, seasonal, cancellation and nonbillable pricing', () => {
  assert.equal(total([performed({ method: 'hourly', rate: '100' })], '0'), '15000');
  assert.equal(
    total([performed({ method: 'perInch', rate: '12.25', quantity: '2' })], '3.5'),
    '8575',
  );
  assert.equal(total([performed({ method: 'seasonal', rate: '1000' })], '5'), '0');
  assert.equal(total([performed({ method: 'manual' }, { canceled: true })], '5'), '0');
  assert.equal(
    total([performed({ method: 'perVisit', rate: '100' }, { billable: false })], '5'),
    '0',
  );
});
test('missing, overlapping and manual tiers fail explicitly', () => {
  assert.throws(
    () =>
      total(
        [performed({ method: 'snowfallTier', tiers: [{ lower: '0', upper: '3', amount: '100' }] })],
        '3',
      ),
    /No Plowing tier/,
  );
  assert.throws(
    () =>
      pricingLines(
        [
          performed({
            method: 'snowfallTier',
            tiers: [
              { lower: '0', upper: '6', amount: '100' },
              { lower: '3', upper: '', amount: '200' },
            ],
          }),
        ],
        '4',
      ),
    /overlap/,
  );
  assert.throws(() => total([performed({ method: 'manual' })], '4'), /manual pricing/);
});
test('loaded identity and pending changes survive without a rewrite', () => {
  const { store, storage } = setup();
  store.saveCustomer({ id: id(), name: 'New customer', active: true });
  const raw = storage.getItem(STORAGE_KEY);
  const reopened = new Store(storage);
  assert.equal(reopened.actorID, store.state.employees[0].id);
  assert.equal(reopened.state.outbox.length, 1);
  assert.equal(storage.getItem(STORAGE_KEY), raw);
});
test('corrupt and unsupported data are preserved', () => {
  const storage = new MemoryStorage();
  storage.setItem(STORAGE_KEY, 'broken');
  assert.throws(() => new Store(storage), /preserved/);
  assert.equal(storage.getItem(STORAGE_KEY), 'broken');
  storage.setItem(STORAGE_KEY, JSON.stringify({ schemaVersion: 8 }));
  assert.throws(() => new Store(storage), /preserved/);
});
test('failed writes do not publish state, audit or outbox', () => {
  const { store, storage } = setup();
  const before = structuredClone(store.state);
  storage.fail = true;
  assert.throws(() => store.saveCustomer({ id: id(), name: 'Cannot save' }), /quota/);
  assert.deepEqual(store.state, before);
});
test('stale browser tabs cannot overwrite newer records', () => {
  const { store, storage } = setup();
  const stale = new Store(storage);
  store.saveCrew({ id: id(), name: 'Crew four', equipment: '' });
  assert.throws(() => stale.saveCustomer({ id: id(), name: 'Stale' }), /Another tab/);
  assert.equal(new Store(storage).state.crews.length, 4);
});
test('field routes are crew scoped, including unassigned identities', () => {
  const { store } = setup();
  const stormID = store.state.storms[0].id;
  store.actorID = store.state.employees[2].id;
  assert(store.route(stormID).every((a) => a.crewID === store.actor.crewID));
  assert.throws(
    () => store.dispatch(store.state.assignments[4].id, 'reassign', store.actor.crewID),
    /role/,
  );
  assert.throws(() => store.start(store.state.assignments[4].id), /another crew/);
  store.actorID = 'missing';
  assert.deepEqual(store.route(stormID), []);
});
test('duplicate starts, snapshots, required work and durable offline completion', () => {
  const { store, storage } = setup();
  store.actorID = store.state.employees[2].id;
  const stop = store.route(store.state.storms[0].id).find((a) => a.status === 'pending');
  const visitID = store.start(stop.id);
  assert.equal(store.start(stop.id), visitID);
  const visit = structuredClone(store.state.visits.find((v) => v.id === visitID));
  assert.throws(() => store.saveVisit(visit, true), /required work/);
  const changed = structuredClone(visit);
  changed.services[0].rate = '1';
  assert.throws(() => store.saveVisit(changed), /contracted pricing/);
  visit.checklist.forEach((c) => (c.answer = true));
  visit.notes = 'North gate inspected';
  store.saveVisit(visit, true);
  const reopened = new Store(storage),
    saved = reopened.state.visits.find((v) => v.id === visitID);
  assert(saved.departure);
  assert.equal(saved.notes, 'North gate inspected');
  assert.equal(reopened.state.outbox.length, 2);
  assert.equal(reopened.state.audit[1].before.visits.find((v) => v.id === visitID).departure, null);
});
test('required photos must reference attached files', () => {
  const state = seed(),
    v = state.visits[0];
  v.checklist = [{ title: 'Photo', required: true, kind: 'photo', answer: 'missing' }];
  assert.deepEqual(completionProblems(v), ['Photo']);
  v.photos.push({ id: 'missing', data: 'photo' });
  assert.deepEqual(completionProblems(v), []);
});
test('snowfall recalculation preserves overrides and rejects stale billing review', () => {
  const { store } = setup();
  const stormID = store.state.storms[0].id;
  store.setStatus(stormID, 'wrappingUp');
  store.setStatus(stormID, 'underReview');
  store.recalculate(stormID, '5');
  const billID = store.state.billing.find((b) => b.propertyID === store.state.properties[0].id).id;
  store.reviewBilling(billID, '1350', 'Agreed cleanup');
  store.recalculate(stormID, '7');
  let bill = store.state.billing.find((b) => b.id === billID);
  assert.equal(bill.override, '135000');
  assert(bill.needsReview);
  const v = structuredClone(store.state.visits[0]);
  v.services[0].quantity = '2';
  store.saveVisit(v, false, 'Second pass correction');
  assert.throws(() => store.reviewBilling(billID, null, 'Accepted'), /Recalculate/);
  assert(store.state.audit.at(-1).before.visits[0].services[0].quantity === '1');
});
test('completed corrections require permission and reason', () => {
  const { store } = setup();
  const visit = structuredClone(store.state.visits[0]);
  assert.throws(() => store.saveVisit(visit), /reason/);
  store.actorID = store.state.employees[2].id;
  assert.throws(() => store.saveVisit(visit, false, 'Correction'), /role/);
});
test('finalization blockers and finalized record locks', () => {
  const { store } = setup();
  const stormID = store.state.storms[0].id;
  store.setStatus(stormID, 'wrappingUp');
  store.setStatus(stormID, 'underReview');
  assert.throws(() => store.setStatus(stormID, 'finalized'), /Verify final snowfall/);
  for (const a of store.state.assignments.filter((a) => a.status === 'pending'))
    store.dispatch(a.id, 'skip', 'Customer requested no service');
  store.recalculate(stormID, '5');
  for (const bill of store.state.billing) store.reviewBilling(bill.id, null, 'Accepted');
  assert.deepEqual(finalizationProblems(store.state, store.state.storms[0]), []);
  store.setStatus(stormID, 'finalized');
  assert.throws(() => store.recalculate(stormID, '6'), /locked/);
  assert.throws(
    () => store.saveVisit(structuredClone(store.state.visits[0]), false, 'Correct'),
    /locked/,
  );
  store.markEntered(store.state.billing[0].id);
  assert(store.state.billing[0].entered);
});
test('CSV escapes formula injection and quotes', () => {
  const { store } = setup();
  const stormID = store.state.storms[0].id;
  store.setStatus(stormID, 'wrappingUp');
  store.setStatus(stormID, 'underReview');
  store.recalculate(stormID, '5');
  store.state.customers[0].name = '=SUM(A1)';
  store.state.properties[0].name = 'Gate "North"';
  const output = csv(store.state);
  assert(output.includes('"\'=SUM(A1)"'));
  assert(output.includes('"Gate ""North"""'));
  assert(output.endsWith('\r\n'));
});
test('field users cannot weaken required checklist snapshots or add overrides', () => {
  const { store } = setup();
  store.actorID = store.state.employees[2].id;
  const stop = store.route(store.state.storms[0].id).find((a) => a.status === 'pending');
  const visitID = store.start(stop.id);
  const original = store.state.visits.find((v) => v.id === visitID),
    changed = structuredClone(original);
  changed.checklist[0].required = false;
  assert.throws(() => store.saveVisit(changed), /snapshots/);
  const override = structuredClone(original);
  override.overrideReason = 'Bypass';
  assert.throws(() => store.saveVisit(override, true), /Review permission/);
});
test('managers with review permission can document completion overrides without billing permission', () => {
  const { store } = setup();
  store.actorID = store.state.employees[1].id;
  const stop = store.state.assignments.find((a) => a.status === 'pending');
  const visitID = store.start(stop.id);
  const visit = structuredClone(store.state.visits.find((v) => v.id === visitID));
  visit.overrideReason = 'Blocked access documented by manager';
  store.saveVisit(visit, true);
  assert(store.state.visits.find((v) => v.id === visitID).departure);
});
