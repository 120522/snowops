// Plain JavaScript domain rules. Decimal inputs stay strings; money uses BigInt cents.
export const id = () => crypto.randomUUID();
const copy = (value) => structuredClone(value);
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};
const SCALE = 1000000n;
export function decimal(value) {
  const text = String(value).trim();
  assert(
    /^\d+(\.\d{1,6})?$/.test(text),
    'Enter a nonnegative number with up to six decimal places.',
  );
  const [whole, fraction = ''] = text.split('.');
  return BigInt(whole) * SCALE + BigInt(fraction.padEnd(6, '0'));
}
export function money(cents) {
  const value = BigInt(cents);
  return `$${(value / 100n).toLocaleString('en-US')}.${String(value % 100n).padStart(2, '0')}`;
}
const rounded = (numerator, denominator) => (numerator + denominator / 2n) / denominator;
export const methods = [
  'perPush',
  'perVisit',
  'perInch',
  'snowfallTier',
  'hourly',
  'perApplication',
  'seasonal',
  'manual',
];
export const permissions = [
  'manageCustomers',
  'manageProperties',
  'manageCrews',
  'dispatch',
  'reviewVisits',
  'reviewBilling',
  'finalizeStorm',
];
export function validateService(service) {
  assert(service.name.trim(), 'Enter a service name.');
  assert(methods.includes(service.method), 'Choose a pricing method.');
  decimal(service.rate);
  decimal(service.trigger || '0');
  if (service.method !== 'snowfallTier') return;
  const tiers = [...service.tiers].sort((a, b) => (decimal(a.lower) < decimal(b.lower) ? -1 : 1));
  assert(tiers.length, 'Add at least one snowfall tier.');
  tiers.forEach((tier, index) => {
    decimal(tier.amount);
    decimal(tier.additional || '0');
    assert(
      tier.upper === '' || decimal(tier.upper) > decimal(tier.lower),
      'Tier upper bound must exceed its lower bound.',
    );
    if (index)
      assert(
        tiers[index - 1].upper !== '' && decimal(tiers[index - 1].upper) <= decimal(tier.lower),
        'Snowfall tiers overlap.',
      );
  });
}
export function pricingLines(visits, snowfall) {
  const snow = decimal(snowfall),
    lines = [];
  for (const visit of visits.filter((v) => v.departure && !v.canceled && v.billable)) {
    for (const service of visit.services.filter((s) => s.performed)) {
      validateService(service);
      let rate = decimal(service.rate),
        quantity = decimal(service.quantity),
        denominator = SCALE * SCALE;
      let numerator = rate * quantity * 100n;
      switch (service.method) {
        case 'manual':
          throw new Error(`${service.name} requires a manual pricing correction before billing.`);
        case 'seasonal':
          numerator = 0n;
          break;
        case 'perInch':
          numerator *= snow;
          denominator *= SCALE;
          break;
        case 'hourly': {
          const duration = Date.parse(visit.departure) - Date.parse(visit.arrival);
          assert(Number.isFinite(duration) && duration >= 0, 'Invalid visit times.');
          numerator = rate * BigInt(duration) * 100n;
          denominator = SCALE * 3600000n;
          break;
        }
        case 'snowfallTier': {
          const tier = service.tiers.find(
            (t) => snow >= decimal(t.lower) && (t.upper === '' || snow < decimal(t.upper)),
          );
          assert(tier, `No ${service.name} tier covers ${snowfall} inches.`);
          numerator =
            (decimal(tier.amount) * SCALE +
              (snow - decimal(tier.lower)) * decimal(tier.additional || '0')) *
            quantity *
            100n;
          denominator = SCALE * SCALE * SCALE;
          break;
        }
      }
      lines.push({
        visitID: visit.id,
        service: service.name,
        cents: String(rounded(numerator, denominator)),
      });
    }
  }
  return lines;
}
export const total = (visits, snow) =>
  String(pricingLines(visits, snow).reduce((sum, line) => sum + BigInt(line.cents), 0n));
export function completionProblems(visit) {
  const problems = [];
  for (const item of visit.checklist) {
    if (!item.required) continue;
    const answer = item.answer;
    const satisfied = ['checkbox', 'confirmation'].includes(item.kind)
      ? answer === true
      : item.kind === 'yesNo'
        ? ['Yes', 'No'].includes(answer)
        : item.kind === 'photo'
          ? visit.photos.some((p) => p.id === answer)
          : item.kind === 'number'
            ? /^\d+(\.\d{1,6})?$/.test(String(answer))
            : String(answer || '').trim();
    if (!satisfied) problems.push(item.title);
  }
  if (!visit.services.some((s) => s.performed)) problems.push('Select a performed service');
  if (visit.services.some((s) => s.performed && s.photoRequired) && !visit.photos.length)
    problems.push('Attach a service photo');
  for (const entry of [...visit.services, ...visit.materials]) {
    try {
      decimal(entry.quantity);
    } catch {
      problems.push('Enter valid nonnegative quantities');
      break;
    }
  }
  return problems;
}
const visitsFor = (state, stormID, propertyID) =>
  state.visits.filter((v) => v.stormID === stormID && v.propertyID === propertyID);
export function finalizationProblems(state, storm) {
  const problems = [];
  if (storm.status !== 'underReview') problems.push('Move the storm into review');
  if (storm.finalSnowfall === null) problems.push('Verify final snowfall');
  const assignments = state.assignments.filter((a) => a.stormID === storm.id);
  if (!assignments.length) problems.push('Dispatch at least one property');
  if (
    assignments.some(
      (a) =>
        !['completed', 'skipped'].includes(a.status) ||
        (a.status === 'skipped' && !a.reason.trim()),
    )
  )
    problems.push('Account for every stop');
  const visits = state.visits.filter((v) => v.stormID === storm.id && !v.canceled);
  if (visits.some((v) => !v.departure)) problems.push('Complete active visits');
  if (visits.some((v) => completionProblems(v).length && !v.overrideReason.trim()))
    problems.push('Review required work');
  if (state.issues.some((i) => i.stormID === storm.id && !i.resolved))
    problems.push('Resolve outstanding issues');
  for (const assignment of assignments.filter((a) => a.status === 'completed')) {
    if (!visits.some((v) => v.assignmentID === assignment.id && v.departure))
      problems.push('Completed stop has no visit');
    if (
      !state.billing.some(
        (b) => b.stormID === storm.id && b.propertyID === assignment.propertyID && !b.needsReview,
      )
    )
      problems.push('Review all property billing');
  }
  for (const bill of state.billing.filter((b) => b.stormID === storm.id)) {
    if (bill.needsReview) problems.push('Review all property billing');
    if (bill.override !== null && !bill.reason.trim())
      problems.push('Document billing adjustments');
    if (storm.finalSnowfall !== null) {
      try {
        if (
          total(visitsFor(state, storm.id, bill.propertyID), storm.finalSnowfall) !==
          bill.calculated
        )
          problems.push('Recalculate changed services');
      } catch (error) {
        problems.push(error.message);
      }
    }
  }
  return [...new Set(problems)];
}
export function seed() {
  const crews = ['Snow 1', 'Snow 2', 'Sidewalk 1'].map((name) => ({
    id: id(),
    name,
    equipment:
      name === 'Sidewalk 1'
        ? 'Sidewalk machine · calcium spreader'
        : 'F-350 · 8 ft plow · salt spreader',
  }));
  const employees = [
    { id: id(), name: 'Alex Morgan', role: 'admin', crewID: '', grants: [] },
    {
      id: id(),
      name: 'Jordan Lee',
      role: 'manager',
      crewID: '',
      grants: ['dispatch', 'manageCrews', 'reviewVisits'],
    },
    ...['Cameron Davis', 'Sam Rivera', 'Taylor Brooks'].map((name, i) => ({
      id: id(),
      name,
      role: 'field',
      crewID: crews[i].id,
      grants: [],
    })),
  ];
  const customers = ['Lehigh Valley Medical', 'Northside Property Group', 'Bethlehem Commerce'].map(
    (name) => ({ id: id(), name, contact: '', phone: '', email: '', notes: '', active: true }),
  );
  const checklist = [
    'Main lot cleared',
    'Fire lane accessible',
    'Entrances and sidewalks cleared',
    'Salt applied',
    'Final inspection complete',
  ].map((title) => ({ id: id(), title, required: true, kind: 'checkbox', answer: false }));
  const locations = [
    ['St. Luke’s Building', '801 Ostrum Street, Bethlehem, PA'],
    ['Northside Commons', '1200 Main Street, Bethlehem, PA'],
    ['ABC Warehouse', '1600 Union Boulevard, Allentown, PA'],
    ['Riverwalk Offices', '101 River Street, Bethlehem, PA'],
    ['Cedar Medical Center', '410 Cedar Crest Boulevard, Allentown, PA'],
    ['Westgate Plaza', '2285 Schoenersville Road, Bethlehem, PA'],
    ['Oak Terrace', '700 Linden Street, Bethlehem, PA'],
    ['Commerce Park', '2200 Avenue A, Bethlehem, PA'],
    ['Southside Market', '315 East 3rd Street, Bethlehem, PA'],
    ['Hanover Logistics', '5000 Hanoverville Road, Bethlehem, PA'],
  ];
  const tiers = [
    { lower: '0', upper: '3', amount: '250', additional: '0' },
    { lower: '3', upper: '6', amount: '475', additional: '0' },
    { lower: '6', upper: '9', amount: '650', additional: '0' },
    { lower: '9', upper: '12', amount: '825', additional: '0' },
    { lower: '12', upper: '', amount: '825', additional: '80' },
  ];
  const properties = locations.map(([name, address], i) => ({
    id: id(),
    customerID: customers[i % 3].id,
    name,
    address,
    active: true,
    crewID: crews[i % 3].id,
    instructions:
      'Push snow to the north perimeter. Keep entrances and fire lanes open. Finish with salt.',
    hazards: 'Watch for parked vehicles and raised drains.',
    checklist: copy(checklist),
    services: [
      {
        id: id(),
        name: 'Snow plowing',
        method: i % 2 ? 'perPush' : 'snowfallTier',
        rate: '325',
        trigger: '1',
        tiers: copy(tiers),
        photoRequired: false,
      },
      {
        id: id(),
        name: 'Sidewalk clearing',
        method: 'perVisit',
        rate: '110',
        trigger: '0',
        tiers: [],
        photoRequired: false,
      },
      {
        id: id(),
        name: 'Lot salt',
        method: 'perApplication',
        rate: '180',
        trigger: '0',
        tiers: [],
        photoRequired: false,
      },
    ],
  }));
  const storm = {
    id: id(),
    name: 'February 6 Snow Event',
    start: '2026-02-06T02:00:00Z',
    status: 'active',
    forecastLow: '4',
    forecastHigh: '7',
    operationalSnowfall: '5.8',
    finalSnowfall: null,
  };
  const assignments = properties.map((p, order) => ({
    id: id(),
    stormID: storm.id,
    propertyID: p.id,
    crewID: p.crewID,
    order,
    status: order < 3 ? 'completed' : 'pending',
    reason: '',
  }));
  const state = {
    schemaVersion: 1,
    revision: 0,
    crews,
    employees,
    customers,
    properties,
    storms: [storm],
    assignments,
    visits: [],
    issues: [],
    billing: [],
    audit: [],
    outbox: [],
  };
  for (const assignment of assignments.slice(0, 3)) {
    const visit = makeVisit(state, assignment, employees[2].id, '2026-02-06T03:00:00Z');
    visit.departure = '2026-02-06T03:45:00Z';
    visit.checklist.forEach((item) => (item.answer = true));
    state.visits.push(visit);
  }
  return state;
}
function makeVisit(state, assignment, actorID, now) {
  const property = state.properties.find((p) => p.id === assignment.propertyID);
  return {
    id: id(),
    assignmentID: assignment.id,
    stormID: assignment.stormID,
    propertyID: property.id,
    customerID: property.customerID,
    crewID: assignment.crewID,
    employeeIDs: state.employees.filter((e) => e.crewID === assignment.crewID).map((e) => e.id),
    arrival: now,
    departure: null,
    createdAt: now,
    editedAt: now,
    editedBy: actorID,
    services: property.services.map((s) => ({ ...copy(s), performed: true, quantity: '1' })),
    checklist: copy(property.checklist),
    materials: [],
    photos: [],
    notes: '',
    overrideReason: '',
    canceled: false,
    billable: true,
  };
}
export const STORAGE_KEY = 'snowops-web-v1';
export class Store {
  constructor(storage) {
    this.storage = storage;
    const raw = storage.getItem(STORAGE_KEY);
    if (raw !== null) {
      try {
        this.state = JSON.parse(raw);
      } catch {
        throw new Error(
          'Saved data cannot be read. It has been preserved. Export it before attempting recovery.',
        );
      }
      assert(
        this.state?.schemaVersion === 1 &&
          Number.isInteger(this.state.revision) &&
          [
            'employees',
            'properties',
            'customers',
            'crews',
            'storms',
            'assignments',
            'visits',
            'issues',
            'billing',
            'audit',
            'outbox',
          ].every((key) => Array.isArray(this.state[key])),
        'Saved data is unsupported. It has been preserved.',
      );
    } else {
      this.state = seed();
      storage.setItem(STORAGE_KEY, JSON.stringify(this.state));
    }
    assert(
      this.state.employees.length,
      'The saved workspace has no employee identity. Its data has been preserved.',
    );
    this.actorID = this.state.employees[0].id;
  }
  get actor() {
    return this.state.employees.find((e) => e.id === this.actorID) || { role: 'field', crewID: '' };
  }
  allows(permission) {
    return (
      this.actor.role === 'admin' ||
      (this.actor.role === 'manager' && this.actor.grants.includes(permission))
    );
  }
  require(permission) {
    assert(this.allows(permission), 'Your role does not permit this action.');
  }
  storm(state, stormID) {
    const storm = state.storms.find((s) => s.id === stormID);
    assert(storm, 'Storm not found.');
    return storm;
  }
  mutable(state, stormID) {
    const storm = this.storm(state, stormID);
    assert(storm.status !== 'finalized', 'Finalized storm records are locked.');
    return storm;
  }
  route(stormID, crewID = '') {
    if (this.actor.role === 'field') crewID = this.actor.crewID || '__unassigned__';
    return this.state.assignments
      .filter((a) => a.stormID === stormID && (!crewID || a.crewID === crewID))
      .sort((a, b) => a.order - b.order);
  }
  transaction(action, entityID, reason, mutation) {
    // Refuse stale-tab writes rather than overwrite newer work. One JSON write commits everything.
    const persisted = JSON.parse(this.storage.getItem(STORAGE_KEY));
    assert(
      persisted.revision === this.state.revision,
      'Another tab changed this workspace. Reload before editing.',
    );
    const next = copy(this.state);
    const snapshot = (state) => {
      const value = copy(state);
      delete value.audit;
      delete value.outbox;
      // Keep photo references in audit snapshots without copying image bytes on every edit.
      value.visits.forEach((visit) => visit.photos.forEach((photo) => delete photo.data));
      return value;
    };
    const before = snapshot(next);
    mutation(next);
    next.revision++;
    const event = {
      id: id(),
      entityID,
      actorID: this.actorID,
      action,
      reason,
      timestamp: new Date().toISOString(),
      before,
      after: snapshot(next),
    };
    next.audit.push(event);
    next.outbox.push({ id: event.id, createdAt: event.timestamp });
    this.storage.setItem(STORAGE_KEY, JSON.stringify(next));
    this.state = next;
  }
  saveCustomer(customer) {
    this.transaction('Customer saved', customer.id, '', (state) => {
      this.require('manageCustomers');
      assert(customer.name.trim(), 'Enter a customer name.');
      upsert(state.customers, copy(customer));
    });
  }
  saveProperty(property) {
    this.transaction('Property saved', property.id, '', (state) => {
      this.require('manageProperties');
      assert(property.name.trim() && property.address.trim(), 'Enter property name and address.');
      assert(
        state.customers.some((c) => c.id === property.customerID),
        'Choose an existing customer.',
      );
      assert(
        !property.crewID || state.crews.some((c) => c.id === property.crewID),
        'Choose an existing crew.',
      );
      assert(property.services.length, 'Add at least one service.');
      property.services.forEach(validateService);
      upsert(state.properties, copy(property));
    });
  }
  saveCrew(crew) {
    this.transaction('Crew saved', crew.id, '', (state) => {
      this.require('manageCrews');
      assert(crew.name.trim(), 'Enter crew name.');
      upsert(state.crews, copy(crew));
    });
  }
  createStorm(storm, propertyIDs, crews) {
    this.transaction('Storm created', storm.id, '', (state) => {
      this.require('dispatch');
      decimal(storm.forecastLow);
      decimal(storm.forecastHigh);
      decimal(storm.operationalSnowfall);
      assert(storm.name.trim() && propertyIDs.length, 'Enter a name and select properties.');
      assert(
        decimal(storm.forecastHigh) >= decimal(storm.forecastLow),
        'Forecast high must be at least the low.',
      );
      assert(
        !['active', 'wrappingUp'].includes(storm.status) ||
          !state.storms.some((s) => ['active', 'wrappingUp'].includes(s.status)),
        'Wrap up and move the current storm into review first.',
      );
      assert(['preparing', 'active'].includes(storm.status), 'Invalid initial storm status.');
      state.storms.push(copy(storm));
      for (const [order, propertyID] of propertyIDs.entries()) {
        assert(
          state.properties.some((p) => p.id === propertyID),
          'Property not found.',
        );
        assert(
          state.crews.some((c) => c.id === crews[propertyID]),
          'Assign every property to a crew.',
        );
        state.assignments.push({
          id: id(),
          stormID: storm.id,
          propertyID,
          crewID: crews[propertyID],
          order,
          status: 'pending',
          reason: '',
        });
      }
    });
  }
  setStatus(stormID, status) {
    this.transaction(`Storm ${status}`, stormID, '', (state) => {
      this.require(status === 'finalized' ? 'finalizeStorm' : 'dispatch');
      const storm = this.mutable(state, stormID);
      assert(
        {
          preparing: 'active',
          active: 'wrappingUp',
          wrappingUp: 'underReview',
          underReview: 'finalized',
        }[storm.status] === status,
        'Invalid storm transition.',
      );
      if (status === 'active')
        assert(
          !state.storms.some((s) => ['active', 'wrappingUp'].includes(s.status)),
          'Another storm is active.',
        );
      if (status === 'finalized') {
        const problems = finalizationProblems(state, storm);
        assert(!problems.length, problems.join('. '));
      }
      storm.status = status;
    });
  }
  dispatch(assignmentID, operation, value) {
    this.transaction(
      `Dispatch ${operation}`,
      assignmentID,
      operation === 'skip' ? value : '',
      (state) => {
        this.require('dispatch');
        const assignment = state.assignments.find((a) => a.id === assignmentID);
        assert(assignment, 'Stop not found.');
        this.mutable(state, assignment.stormID);
        if (operation === 'reassign') {
          assert(
            assignment.status !== 'inProgress',
            'Complete the active visit before changing crews.',
          );
          assert(
            state.crews.some((c) => c.id === value),
            'Crew not found.',
          );
          assignment.crewID = value;
        } else if (operation === 'skip') {
          assert(
            !['inProgress', 'completed'].includes(assignment.status) && value.trim(),
            'An unstarted stop and a reason are required.',
          );
          assignment.status = 'skipped';
          assignment.reason = value;
        } else if (operation === 'additional') {
          assert(
            ['active', 'wrappingUp'].includes(this.storm(state, assignment.stormID).status),
            'Additional visits require an active storm.',
          );
          state.assignments.push({
            ...copy(assignment),
            id: id(),
            status: 'pending',
            reason: '',
            order: Math.max(...state.assignments.map((a) => a.order)) + 1,
          });
        } else if (operation === 'up' || operation === 'down') {
          const route = state.assignments
            .filter((a) => a.stormID === assignment.stormID && a.crewID === assignment.crewID)
            .sort((a, b) => a.order - b.order);
          const index = route.findIndex((a) => a.id === assignmentID),
            target = index + (operation === 'up' ? -1 : 1);
          if (route[target]) [route[index], route[target]] = [route[target], route[index]];
          route.forEach((a, i) => (a.order = i));
        } else throw new Error('Unknown dispatch action.');
      },
    );
  }
  start(assignmentID) {
    const assignment = this.state.assignments.find((a) => a.id === assignmentID);
    assert(assignment, 'Stop not found.');
    assert(
      this.allows('dispatch') || (this.actor.crewID && this.actor.crewID === assignment.crewID),
      'This stop belongs to another crew.',
    );
    const storm = this.mutable(this.state, assignment.stormID);
    assert(['active', 'wrappingUp'].includes(storm.status), 'Visits require an active storm.');
    const existing = this.state.visits.find(
      (v) => v.assignmentID === assignmentID && !v.departure && !v.canceled,
    );
    if (existing) return existing.id;
    const visit = makeVisit(this.state, assignment, this.actorID, new Date().toISOString());
    this.transaction('Visit started', visit.id, '', (state) => {
      assert(
        ['pending', 'attention'].includes(assignment.status),
        'Dispatch an additional visit for a completed stop.',
      );
      assert(
        !state.visits.some((v) => v.crewID === assignment.crewID && !v.departure && !v.canceled),
        'Complete this crew’s current visit first.',
      );
      state.visits.push(visit);
      state.assignments.find((a) => a.id === assignmentID).status = 'inProgress';
      invalidate(state, visit);
    });
    return visit.id;
  }
  saveVisit(draft, complete = false, correctionReason = '') {
    this.transaction(
      correctionReason ? 'Completed visit corrected' : complete ? 'Visit completed' : 'Visit saved',
      draft.id,
      correctionReason || draft.overrideReason,
      (state) => {
        const original = state.visits.find((v) => v.id === draft.id);
        assert(original, 'Visit not found.');
        this.mutable(state, original.stormID);
        assert(
          this.allows('reviewVisits') ||
            (this.actor.crewID && this.actor.crewID === original.crewID),
          'You cannot edit another crew’s visit.',
        );
        for (const key of [
          'assignmentID',
          'stormID',
          'propertyID',
          'customerID',
          'crewID',
          'employeeIDs',
          'createdAt',
        ])
          assert(
            JSON.stringify(draft[key]) === JSON.stringify(original[key]),
            'Visit identity must be preserved.',
          );
        const corrected = !!original.departure;
        if (corrected) {
          this.require('reviewVisits');
          assert(correctionReason.trim(), 'A correction requires a reason.');
          assert(
            draft.departure && Date.parse(draft.departure) >= Date.parse(draft.arrival),
            'Invalid corrected timestamps.',
          );
        } else {
          assert(
            draft.arrival === original.arrival && draft.departure === null && !draft.canceled,
            'Field edits cannot change timestamps or cancel records.',
          );
        }
        assert(
          JSON.stringify(draft.checklist.map(({ answer, ...item }) => item)) ===
            JSON.stringify(original.checklist.map(({ answer, ...item }) => item)),
          'Required checklist snapshots cannot be changed.',
        );
        if (!this.allows('reviewVisits'))
          assert(
            draft.overrideReason === original.overrideReason,
            'Review permission is required for checklist overrides.',
          );
        if (!this.allows('reviewBilling')) {
          assert(draft.billable === original.billable, 'Billing permission is required.');
          assert(
            JSON.stringify(draft.services.map(({ performed, quantity, ...config }) => config)) ===
              JSON.stringify(original.services.map(({ performed, quantity, ...config }) => config)),
            'Field users cannot change contracted pricing.',
          );
        }
        draft.services.forEach(validateService);
        draft.services.forEach((s) => decimal(s.quantity));
        draft.materials.forEach((m) => decimal(m.quantity));
        const updated = copy(draft);
        updated.editedAt = new Date().toISOString();
        updated.editedBy = this.actorID;
        if ((complete || corrected) && !updated.canceled) {
          const problems = completionProblems(updated);
          assert(
            !problems.length || (this.allows('reviewVisits') && updated.overrideReason.trim()),
            `Complete required work: ${problems.join(', ')}.`,
          );
        }
        if (complete && !corrected) updated.departure = updated.editedAt;
        upsert(state.visits, updated);
        const assignment = state.assignments.find((a) => a.id === updated.assignmentID);
        if (updated.departure && !updated.canceled) assignment.status = 'completed';
        if (
          updated.canceled &&
          !state.visits.some(
            (v) => v.assignmentID === updated.assignmentID && !v.canceled && v.departure,
          )
        )
          assignment.status = 'attention';
        invalidate(state, updated);
      },
    );
  }
  reportIssue(issue) {
    this.transaction('Issue reported', issue.id, '', (state) => {
      this.mutable(state, issue.stormID);
      assert(issue.note.trim(), 'Describe the issue.');
      assert(
        this.allows('reviewVisits') ||
          (this.actor.crewID &&
            state.assignments.some(
              (a) =>
                a.stormID === issue.stormID &&
                a.propertyID === issue.propertyID &&
                a.crewID === this.actor.crewID,
            )),
        'This site is not assigned to your crew.',
      );
      state.issues.push({
        ...copy(issue),
        createdBy: this.actorID,
        resolved: false,
        createdAt: new Date().toISOString(),
      });
    });
  }
  resolveIssue(issueID) {
    this.transaction('Issue resolved', issueID, '', (state) => {
      this.require('reviewVisits');
      const issue = state.issues.find((i) => i.id === issueID);
      assert(issue, 'Issue not found.');
      this.mutable(state, issue.stormID);
      issue.resolved = true;
    });
  }
  recalculate(stormID, snowfall) {
    this.transaction('Snowfall recalculated', stormID, `${snowfall} inches`, (state) => {
      this.require('reviewBilling');
      const storm = this.mutable(state, stormID);
      assert(storm.status === 'underReview', 'Move the storm into review first.');
      decimal(snowfall);
      storm.finalSnowfall = snowfall;
      const propertyIDs = new Set([
        ...state.assignments
          .filter((a) => a.stormID === stormID && a.status !== 'skipped')
          .map((a) => a.propertyID),
        ...state.billing.filter((b) => b.stormID === stormID).map((b) => b.propertyID),
      ]);
      for (const propertyID of propertyIDs) {
        const calculated = total(visitsFor(state, stormID, propertyID), snowfall),
          bill = state.billing.find((b) => b.stormID === stormID && b.propertyID === propertyID);
        if (bill) {
          if (bill.calculated !== calculated) bill.needsReview = true;
          bill.calculated = calculated;
        } else
          state.billing.push({
            id: id(),
            stormID,
            propertyID,
            calculated,
            override: null,
            reason: '',
            needsReview: true,
            entered: false,
          });
      }
    });
  }
  reviewBilling(billID, override, reason) {
    this.transaction('Billing reviewed', billID, reason, (state) => {
      this.require('reviewBilling');
      const bill = state.billing.find((b) => b.id === billID);
      assert(bill, 'Billing record not found.');
      const storm = this.mutable(state, bill.stormID);
      assert(
        storm.status === 'underReview' && storm.finalSnowfall !== null,
        'Verify snowfall while under review.',
      );
      assert(
        total(visitsFor(state, bill.stormID, bill.propertyID), storm.finalSnowfall) ===
          bill.calculated,
        'Service records changed. Recalculate before reviewing.',
      );
      if (override !== null) {
        assert(reason.trim(), 'An adjustment requires a reason.');
        bill.override = String(rounded(decimal(override) * 100n, SCALE));
      } else bill.override = null;
      bill.reason = reason;
      bill.needsReview = false;
    });
  }
  markEntered(billID) {
    this.transaction('Invoice preparation marked entered', billID, '', (state) => {
      this.require('reviewBilling');
      const bill = state.billing.find((b) => b.id === billID);
      assert(bill, 'Billing record not found.');
      assert(
        this.storm(state, bill.stormID).status === 'finalized' && !bill.needsReview,
        'Finalize and review first.',
      );
      bill.entered = true;
    });
  }
}
function upsert(list, value) {
  const index = list.findIndex((item) => item.id === value.id);
  if (index < 0) list.push(value);
  else list[index] = value;
}
function invalidate(state, visit) {
  state.billing
    .filter((b) => b.stormID === visit.stormID && b.propertyID === visit.propertyID)
    .forEach((b) => (b.needsReview = true));
}
export function csv(state, records = state.billing) {
  const escape = (value) => {
    let text = String(value ?? '');
    if (/^[=+\-@\t\r]/.test(text) || /^[=+\-@]/.test(text.trim())) text = "'" + text;
    return '"' + text.replaceAll('"', '""') + '"';
  };
  const rows = [
    ['Customer', 'Property', 'Storm', 'Quantity', 'Calculated', 'Final Amount', 'Reason', 'Status'],
  ];
  for (const bill of records) {
    const property = state.properties.find((p) => p.id === bill.propertyID),
      storm = state.storms.find((s) => s.id === bill.stormID);
    rows.push([
      state.customers.find((c) => c.id === property.customerID)?.name,
      property.name,
      storm.name,
      '1',
      money(bill.calculated),
      money(bill.override ?? bill.calculated),
      bill.reason,
      bill.entered
        ? 'Entered'
        : bill.needsReview || storm.status !== 'finalized'
          ? 'Needs review'
          : 'Ready',
    ]);
  }
  return rows.map((row) => row.map(escape).join(',')).join('\r\n') + '\r\n';
}
