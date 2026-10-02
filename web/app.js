import {
  Store,
  id,
  money,
  methods,
  permissions,
  pricingLines,
  finalizationProblems,
  csv,
  STORAGE_KEY,
} from './core.js';
const $ = (selector) => document.querySelector(selector);
const esc = (value) =>
  String(value ?? '').replace(
    /[&<>"']/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c],
  );
const date = (value) =>
  value
    ? new Date(value).toLocaleString([], {
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      })
    : 'Still on site';
const titles = {
  preparing: 'Preparing',
  active: 'Active',
  wrappingUp: 'Wrapping up',
  underReview: 'Under review',
  finalized: 'Finalized',
  pending: 'Not started',
  inProgress: 'In progress',
  completed: 'Completed',
  attention: 'Needs attention',
  skipped: 'Skipped',
  snowfallTier: 'Snowfall tier',
  perPush: 'Per push',
  perVisit: 'Per visit',
  perInch: 'Per inch',
  perApplication: 'Per application',
  hourly: 'Hourly',
  seasonal: 'Seasonal',
  manual: 'Manual review',
};
const badge = (value) => `<span class="badge ${esc(value)}">${esc(titles[value] || value)}</span>`;
const button = (label, action, item = '', className = '', disabled = false) =>
  `<button type="button" data-action="${action}" data-id="${esc(item)}" class="${className}" ${disabled ? 'disabled' : ''}>${esc(label)}</button>`;
const input = (label, name, value = '', type = 'text', extra = '') =>
  `<label>${esc(label)}<input name="${name}" aria-label="${esc(label)}" type="${type}" value="${esc(value)}" ${extra}></label>`;
const textarea = (label, name, value = '') =>
  `<label>${esc(label)}<textarea name="${name}" aria-label="${esc(label)}">${esc(value)}</textarea></label>`;
const check = (label, name, checked = false, extra = '') =>
  `<label class="check"><input type="checkbox" name="${name}" ${checked ? 'checked' : ''} ${extra}>${esc(label)}</label>`;
const select = (label, name, options, value) =>
  `<label>${esc(label)}<select name="${name}" aria-label="${esc(label)}">${options.map(([key, title]) => `<option value="${esc(key)}" ${key === value ? 'selected' : ''}>${esc(title)}</option>`).join('')}</select></label>`;
const empty = (title, description) =>
  `<div class="empty"><strong>${esc(title)}</strong>${esc(description)}</div>`;
let store;
try {
  store = new Store(localStorage);
} catch (error) {
  $('#app').innerHTML =
    `<main><h1>Local data could not be opened</h1><p class="error">${esc(error.message)}</p><p>No reset was performed.</p><button id="recovery">Download preserved data</button></main>`;
  $('#recovery').onclick = () =>
    download('snowops-recovery.json', localStorage.getItem(STORAGE_KEY) ?? '', 'application/json');
}
let page = 'home',
  focusedID = '',
  query = '',
  billFilter = 'all';
const entity = (kind, value) => store.state[kind].find((item) => item.id === value);
const active = () => store.state.storms.find((s) => ['active', 'wrappingUp'].includes(s.status));
const propertyName = (value) => entity('properties', value)?.name || 'Property';
const crewName = (value) => entity('crews', value)?.name || 'Unassigned';
const field = () => store.actor.role === 'field';
const can = (permission) => store.allows(permission);
function toast(message) {
  $('#toast').textContent = message;
  $('#toast').classList.add('show');
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => $('#toast').classList.remove('show'), 4500);
}
function download(name, content, type) {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
const heading = (title, subtitle, action = '') =>
  `<div class="page-head"><div><div class="eyebrow">${esc(subtitle)}</div><h1>${esc(title)}</h1></div>${action}</div>`;
function render() {
  if (!store) return;
  if (field() && !['home', 'dispatch', 'visits', 'visit', 'settings'].includes(page)) page = 'home';
  const links = field()
    ? [
        ['home', '⌂', 'Home'],
        ['dispatch', '≡', 'Your route'],
        ['visits', '◷', 'Visit history'],
        ['settings', '⚙', 'Settings'],
      ]
    : [
        ['home', '⌂', 'Overview'],
        ['storms', '☁', 'Storms'],
        ['dispatch', '≡', 'Dispatch'],
        ['properties', '⌖', 'Properties'],
        ['customers', '▣', 'Customers'],
        ['crews', '♧', 'Crews & people'],
        ...(can('reviewBilling') ? [['billing', '$', 'Invoice prep']] : []),
        ['visits', '◷', 'Visit history'],
        ['audit', '↺', 'Audit history'],
        ['settings', '⚙', 'Settings'],
      ];
  $('#app').innerHTML =
    `<header><div class="brand"><span>❄</span><div>Snow Ops<small>Operations workspace</small></div></div><div class="identity"><span>Development identity</span><select id="identity" aria-label="Development identity">${store.state.employees.map((e) => `<option value="${e.id}" ${e.id === store.actorID ? 'selected' : ''}>${esc(e.name)} · ${e.role}</option>`).join('')}</select></div></header><div class="local-banner"><span>● Saved in this browser · ${store.state.outbox.length} pending changes</span><span>Demo workspace · backend and sign-in are not connected</span></div><div class="layout"><nav aria-label="Main navigation">${links.map(([key, icon, title]) => `<a href="#${key}" data-page="${key}" ${page === key || (page === 'storm' && key === 'storms') || (page === 'visit' && key === 'visits') ? 'class="active" aria-current="page"' : ''}><span aria-hidden="true">${icon}</span>${title}</a>`).join('')}<p class="nav-note">Keep crews moving.<br>Every stop. Every storm.<br><br>Local records stay on this browser. Export backups in Settings.</p></nav><main id="main" tabindex="-1">${content()}</main></div>`;
}
function content() {
  switch (page) {
    case 'home':
      return home();
    case 'storms':
      return storms();
    case 'storm':
      return stormDetail();
    case 'dispatch':
      return dispatch();
    case 'customers':
      return customers();
    case 'properties':
      return properties();
    case 'crews':
      return crews();
    case 'visits':
      return visits();
    case 'visit':
      return visitDetail();
    case 'billing':
      return billing();
    case 'audit':
      return audit();
    case 'settings':
      return settings();
    default:
      return home();
  }
}
function home() {
  const storm = active(),
    route = storm ? store.route(storm.id) : [],
    completed = route.filter((a) => ['completed', 'skipped'].includes(a.status)).length;
  const issues = store.state.issues.filter(
    (i) =>
      !i.resolved &&
      (!field() || route.some((a) => a.propertyID === i.propertyID && a.stormID === i.stormID)),
  );
  const next =
    route.find((a) => a.status === 'inProgress') ||
    route.find((a) => ['pending', 'attention'].includes(a.status));
  return (
    heading(
      field() ? 'Ready for the next stop' : 'Operations overview',
      field() ? crewName(store.actor.crewID) : 'Storm command',
      can('dispatch') ? button('+ New storm', 'new-storm', '', 'primary') : '',
    ) +
    (storm
      ? `<section class="hero"><div style="flex:1;width:100%"><div class="eyebrow">${field() ? 'Your assignment' : 'Live operations'}</div><h2>${esc(storm.name)}</h2><p class="muted">${esc(storm.operationalSnowfall)}″ operational estimate · Forecast ${esc(storm.forecastLow)}–${esc(storm.forecastHigh)}″</p><progress value="${completed}" max="${Math.max(route.length, 1)}" aria-label="Stops accounted for"></progress><div class="muted">${completed} of ${route.length} stops accounted for</div></div><div class="hero-actions">${button(field() ? 'Open your route →' : 'Open dispatch →', 'route', storm.id, 'primary')}${!field() ? button('Storm details', 'storm', storm.id) : ''}</div></section>`
      : `<div class="panel">${empty('No active storm', can('dispatch') ? 'Prepare a storm to dispatch your crews.' : 'Your route will appear when a storm is activated.')}</div>`) +
    `<div class="stats"><div class="stat"><strong>${route.length - completed}</strong><span>Stops remaining</span></div><div class="stat"><strong>${route.filter((a) => a.status === 'inProgress').length}</strong><span>Crews on site</span></div><div class="stat"><strong>${completed}</strong><span>Stops accounted for</span></div><div class="stat"><strong>${issues.length}</strong><span>Open issues</span></div></div><div class="grid"><section class="panel"><div class="section-head"><h2>${field() ? 'Your next stop' : 'Route activity'}</h2>${badge(storm?.status || 'preparing')}</div>${next ? stopRow(next) : empty('All clear', 'No pending stops on your route.')}${
      !field()
        ? route
            .filter((a) => a.status === 'inProgress' && a.id !== next?.id)
            .map(stopRow)
            .join('')
        : ''
    }</section><section class="panel"><h2>Needs attention</h2>${issues.length ? issues.map(issueRow).join('') : empty('No open issues', 'Site issues will appear here when reported.')}</section></div>${!field() ? `<section class="panel"><div class="section-head"><h2>Recent storms</h2><a href="#storms" data-page="storms">View all →</a></div>${store.state.storms.slice().reverse().slice(0, 3).map(stormRow).join('')}</section>` : ''}`
  );
}
function stormRow(storm) {
  return `<div class="row"><div><h3>${esc(storm.name)}</h3><div class="muted">${date(storm.start)}</div></div><div class="actions">${badge(storm.status)}${button('Open', 'storm', storm.id)}</div></div>`;
}
function storms() {
  return (
    heading(
      'Storms',
      'Plan, dispatch, review',
      can('dispatch') ? button('+ New storm', 'new-storm', '', 'primary') : '',
    ) +
    `<section class="panel">${store.state.storms.slice().reverse().map(stormRow).join('')}</section>`
  );
}
function stormDetail() {
  const storm = entity('storms', focusedID);
  if (!storm) return empty('Storm not found', 'Return to Storms.');
  const route = store.route(storm.id),
    bills = store.state.billing.filter((b) => b.stormID === storm.id),
    problems = finalizationProblems(store.state, storm);
  const next = {
    preparing: ['active', 'Activate storm'],
    active: ['wrappingUp', 'Wrap up operations'],
    wrappingUp: ['underReview', 'Move to review'],
    underReview: ['finalized', 'Finalize storm'],
  }[storm.status];
  return (
    heading(storm.name, `Storm details · ${date(storm.start)}`, badge(storm.status)) +
    `<div class="panel"><div class="section-head"><h2>Operations</h2><div class="actions">${button('Open dispatch', 'route', storm.id)}${next && can(next[0] === 'finalized' ? 'finalizeStorm' : 'dispatch') ? button(next[1], 'status', storm.id, 'primary', next[0] === 'finalized' && problems.length > 0) : ''}</div></div><p>${route.filter((a) => a.status === 'completed').length} completed · ${route.length} stops · ${esc(storm.operationalSnowfall)}″ estimate</p></div>` +
    (can('reviewBilling') && ['underReview', 'finalized'].includes(storm.status)
      ? `<section class="panel"><h2>Snowfall & billing review</h2>${storm.status === 'underReview' ? `<form id="snowfall-form" class="toolbar">${input('Final verified inches', 'snowfall', storm.finalSnowfall ?? storm.operationalSnowfall, 'text', 'inputmode="decimal" required')}<button class="primary">Verify & recalculate</button></form>` : `<p>Final snowfall: ${esc(storm.finalSnowfall)}″ · Records locked</p>`}<div class="table-scroll"><table><thead><tr><th>Property</th><th class="amount">Calculated</th><th class="amount">Final</th><th>Review</th><th></th></tr></thead><tbody>${bills.map((b) => `<tr><td>${esc(propertyName(b.propertyID))}</td><td class="amount">${money(b.calculated)}</td><td class="amount">${money(b.override ?? b.calculated)}${b.override !== null ? '<div class="muted">Override preserved</div>' : ''}</td><td>${badge(b.needsReview ? 'review' : 'ready')}</td><td>${button('Details', 'bill', b.id)}</td></tr>`).join('')}</tbody></table></div>${!bills.length ? empty('No billing calculated', 'Verify snowfall to calculate completed services.') : ''}</section>${storm.status !== 'finalized' ? `<section class="panel"><h2>Before finalization</h2>${problems.length ? `<ul>${problems.map((p) => `<li>${esc(p)}</li>`).join('')}</ul>` : '<p>Everything is ready for finalization.</p>'}</section>` : ''}`
      : '') +
    `<section class="panel"><h2>Site issues</h2>${
      store.state.issues
        .filter((i) => i.stormID === storm.id)
        .map(issueRow)
        .join('') || empty('No issues', 'No site issues have been reported.')
    }</section>`
  );
}
function stopRow(assignment) {
  const property = entity('properties', assignment.propertyID),
    visit = store.state.visits.find(
      (v) => v.assignmentID === assignment.id && !v.canceled && v.departure,
    );
  return `<div class="row"><div class="row-main"><h3>${esc(property.name)}</h3><div class="muted">${esc(property.address)}</div><p>${badge(assignment.status)} <span class="muted">${esc(crewName(assignment.crewID))}</span></p>${assignment.reason ? `<p class="muted">${esc(assignment.reason)}</p>` : ''}</div><div class="actions">${['pending', 'attention', 'inProgress'].includes(assignment.status) ? button(assignment.status === 'inProgress' ? 'Continue visit' : 'Start visit', 'start', assignment.id, 'primary', !['active', 'wrappingUp'].includes(entity('storms', assignment.stormID).status)) : visit ? button('View record', 'visit', visit.id) : ''}${button('Site details', 'site', property.id)}${can('dispatch') && entity('storms', assignment.stormID).status !== 'finalized' ? button('Manage stop', 'manage-stop', assignment.id) : ''}</div></div>`;
}
function dispatch() {
  const storm = entity('storms', focusedID) || active();
  if (!storm)
    return (
      heading(field() ? 'Your route' : 'Dispatch', 'Assigned stops') +
      empty('No active route', 'Activate a storm to see assigned properties.')
    );
  const route = store
    .route(storm.id)
    .filter(
      (a) =>
        !query ||
        `${propertyName(a.propertyID)} ${entity('properties', a.propertyID).address}`
          .toLowerCase()
          .includes(query.toLowerCase()),
    );
  return (
    heading(field() ? 'Your route' : 'Dispatch board', storm.name, badge(storm.status)) +
    `<div class="toolbar"><input id="search" aria-label="Search stops" placeholder="Search properties or addresses" value="${esc(query)}"></div>` +
    store.state.crews
      .filter((c) => route.some((a) => a.crewID === c.id))
      .map(
        (c) =>
          `<section class="panel"><div class="section-head"><div><h2>${esc(c.name)}</h2><p class="muted">${esc(c.equipment)}</p></div><span class="muted">${route.filter((a) => a.crewID === c.id && a.status === 'completed').length}/${route.filter((a) => a.crewID === c.id).length} complete</span></div>${route
            .filter((a) => a.crewID === c.id)
            .map(stopRow)
            .join('')}</section>`,
      )
      .join('') +
    (!route.length
      ? empty(
          'No assigned stops',
          field()
            ? 'An administrator must assign your crew to this storm.'
            : 'No matching properties.',
        )
      : '')
  );
}
function customers() {
  return (
    heading(
      'Customers',
      'Contacts & service locations',
      can('manageCustomers') ? button('+ Add customer', 'customer', '', 'primary') : '',
    ) +
    `<div class="toolbar"><input id="search" aria-label="Search customers" placeholder="Search customers" value="${esc(query)}"></div><section class="panel">${store.state.customers
      .filter((c) => c.name.toLowerCase().includes(query.toLowerCase()))
      .map(
        (c) =>
          `<div class="row"><div><h3>${esc(c.name)}</h3><div class="muted">${esc(c.contact || 'No contact added')} · ${store.state.properties.filter((p) => p.customerID === c.id).length} properties</div><p class="muted">${esc(c.email)} ${esc(c.phone)}</p>${!c.active ? badge('Archived') : ''}</div>${can('manageCustomers') ? button('Edit', 'customer', c.id) : ''}</div>`,
      )
      .join('')}</section>`
  );
}
function properties() {
  return (
    heading(
      'Properties',
      'Service agreements & site instructions',
      can('manageProperties') ? button('+ Add property', 'property', '', 'primary') : '',
    ) +
    `<div class="toolbar"><input id="search" aria-label="Search properties" placeholder="Search properties or addresses" value="${esc(query)}"></div><div class="grid">${store.state.properties
      .filter((p) => `${p.name} ${p.address}`.toLowerCase().includes(query.toLowerCase()))
      .map(
        (p) =>
          `<section class="panel"><h2>${esc(p.name)}</h2><p class="muted">${esc(p.address)}</p><p class="muted">${esc(entity('customers', p.customerID)?.name)} · ${esc(crewName(p.crewID))}</p><p>${p.services.map((s) => esc(s.name)).join(' · ')}</p><div class="actions">${button('Site details', 'site', p.id)}${can('manageProperties') ? button('Edit', 'property', p.id) + button('Duplicate', 'duplicate-property', p.id) : ''}</div></section>`,
      )
      .join('')}</div>`
  );
}
function crews() {
  return (
    heading(
      'Crews & people',
      'Assignments & equipment',
      can('manageCrews') ? button('+ Add crew', 'crew', '', 'primary') : '',
    ) +
    `<div class="grid">${store.state.crews
      .map(
        (c) =>
          `<section class="panel"><div class="section-head"><h2>${esc(c.name)}</h2>${can('manageCrews') ? button('Edit', 'crew', c.id) : ''}</div><p class="muted">${esc(c.equipment)}</p>${
            store.state.employees
              .filter((e) => e.crewID === c.id)
              .map(
                (e) =>
                  `<div class="row"><div>${esc(e.name)}<div class="muted">${e.role}</div></div>${can('manageCrews') ? button('Edit', 'employee', e.id) : ''}</div>`,
              )
              .join('') || '<p class="muted">No employees assigned</p>'
          }</section>`,
      )
      .join(
        '',
      )}</div><section class="panel"><div class="section-head"><h2>All employees</h2>${store.actor.role === 'admin' ? button('+ Add employee', 'employee') : ''}</div>${store.state.employees.map((e) => `<div class="row"><div>${esc(e.name)}<div class="muted">${e.role} · ${esc(crewName(e.crewID))}</div></div>${can('manageCrews') ? button('Edit', 'employee', e.id) : ''}</div>`).join('')}</section>`
  );
}
function visits() {
  const records = store.state.visits
    .filter(
      (v) =>
        (!field() || (store.actor.crewID && v.crewID === store.actor.crewID)) &&
        `${propertyName(v.propertyID)} ${v.notes}`.toLowerCase().includes(query.toLowerCase()),
    )
    .sort((a, b) => b.arrival.localeCompare(a.arrival));
  return (
    heading('Visit history', 'Original records & audited corrections') +
    `<div class="toolbar"><input id="search" aria-label="Search visit history" placeholder="Search properties or notes" value="${esc(query)}"></div><section class="panel">${records.map((v) => `<div class="row"><div><h3>${esc(propertyName(v.propertyID))}</h3><div class="muted">${date(v.arrival)} · ${esc(crewName(v.crewID))}</div><p>${badge(v.canceled ? 'canceled' : v.departure ? 'completed' : 'inProgress')}</p></div>${button('Open visit', 'visit', v.id)}</div>`).join('') || empty('No visits found', 'Start a visit from your route.')}</section>`
  );
}
function visitDetail() {
  const visit = entity('visits', focusedID);
  if (!visit || (field() && (!store.actor.crewID || visit.crewID !== store.actor.crewID)))
    return empty('Visit unavailable', 'Open a visit assigned to your crew.');
  return (
    heading(
      propertyName(visit.propertyID),
      'Service record',
      badge(visit.canceled ? 'canceled' : visit.departure ? 'completed' : 'inProgress'),
    ) +
    `<section class="panel"><div class="form-grid"><div><h3>Arrival</h3><p>${date(visit.arrival)}</p></div><div><h3>Departure</h3><p>${date(visit.departure)}</p></div></div><p class="muted">${esc(crewName(visit.crewID))} · Created ${date(visit.createdAt)}</p><div class="actions">${!visit.departure ? button('Edit active visit', 'edit-visit', visit.id, 'primary') : can('reviewVisits') && entity('storms', visit.stormID).status !== 'finalized' ? button('Correct completed record', 'correct-visit', visit.id) : ''}${button('Report issue', 'issue', visit.id, '', entity('storms', visit.stormID).status === 'finalized')}</div></section><div class="grid"><section class="panel"><h2>Services performed</h2>${visit.services.map((s) => `<div class="row"><div>${esc(s.name)}<div class="muted">${esc(titles[s.method])} · Quantity ${esc(s.quantity)}</div></div>${badge(s.performed ? 'completed' : 'skipped')}</div>`).join('')}<h3>Materials</h3>${visit.materials.map((m) => `<p>${esc(m.name)} · ${esc(m.quantity)} ${esc(m.unit)}</p>`).join('') || '<p class="muted">None recorded</p>'}</section><section class="panel"><h2>Checklist</h2>${visit.checklist.map((c) => `<p>${c.answer ? '✓' : '○'} ${esc(c.title)} ${typeof c.answer === 'string' && c.kind !== 'photo' ? `· ${esc(c.answer)}` : ''}</p>`).join('')}<p class="muted">${esc(visit.overrideReason)}</p></section></div><section class="panel"><h2>Documentation</h2><p>${esc(visit.notes || 'No notes recorded.')}</p><div class="photos">${visit.photos.map((p) => `<img src="${esc(p.data)}" alt="${esc(p.name)}">`).join('')}</div></section>`
  );
}
function billingRecords() {
  return store.state.billing.filter((b) => {
    const ready = !b.needsReview && entity('storms', b.stormID).status === 'finalized';
    return (
      billFilter === 'all' ||
      (billFilter === 'entered' && b.entered) ||
      (billFilter === 'ready' && ready && !b.entered) ||
      (billFilter === 'review' && !ready)
    );
  });
}
function billing() {
  if (!can('reviewBilling')) return empty('Unavailable', 'Billing permission is required.');
  const records = billingRecords();
  return (
    heading(
      'Invoice preparation',
      'Export totals for your invoicing system',
      `<div class="actions">${button('Export CSV', 'csv')}${button('Print / Save PDF', 'print')}</div>`,
    ) +
    `<p class="notice">One row per property and storm. This app prepares records; it does not create invoices.</p><div class="toolbar" style="margin-top:20px">${select(
      'Show records',
      'billing-filter',
      [
        ['all', 'All'],
        ['ready', 'Ready'],
        ['review', 'Needs review'],
        ['entered', 'Entered'],
      ],
      billFilter,
    )}</div><section class="panel"><div class="table-scroll"><table><thead><tr><th>Customer / property</th><th>Storm</th><th class="amount">Calculated</th><th class="amount">Final amount</th><th>Status</th><th></th></tr></thead><tbody>${records
      .map((b) => {
        const p = entity('properties', b.propertyID),
          storm = entity('storms', b.stormID),
          ready = !b.needsReview && storm.status === 'finalized';
        return `<tr><td>${esc(entity('customers', p.customerID)?.name)}<div class="muted">${esc(p.name)}</div></td><td>${esc(storm.name)}</td><td class="amount">${money(b.calculated)}</td><td class="amount">${money(b.override ?? b.calculated)}</td><td>${badge(b.entered ? 'Entered' : ready ? 'ready' : 'review')}</td><td><div class="actions">${button('Details', 'bill', b.id)}${ready && !b.entered ? button('Mark entered', 'entered', b.id) : ''}</div></td></tr>`;
      })
      .join(
        '',
      )}</tbody></table></div>${!records.length ? empty('No matching billing records', 'Move a storm to review and verify snowfall first.') : ''}</section>`
  );
}
function issueRow(issue) {
  return `<div class="row issue"><div><h3>${esc(issue.category)} ${badge(issue.resolved ? 'Resolved' : issue.severity)}</h3><div class="muted">${esc(propertyName(issue.propertyID))}</div><p>${esc(issue.note)}</p></div>${can('reviewVisits') && !issue.resolved && entity('storms', issue.stormID).status !== 'finalized' ? button('Resolve', 'resolve', issue.id) : ''}</div>`;
}
function audit() {
  return (
    heading('Audit history', 'Who changed what and why') +
    `<section class="panel">${
      store.state.audit
        .slice()
        .reverse()
        .map(
          (a) =>
            `<div class="row"><div><h3>${esc(a.action)}</h3><div class="muted">${esc(entity('employees', a.actorID)?.name)} · ${date(a.timestamp)}</div><p>${esc(a.reason)}</p></div>${button('View original / updated', 'audit-detail', a.id)}</div>`,
        )
        .join('') || empty('No changes yet', 'Saved changes will appear here.')
    }</section>`
  );
}
function settings() {
  return (
    heading('Settings', 'Local workspace & recovery') +
    `<section class="panel"><h2>Development mode</h2><p>The identity selector previews roles. It is not secure authentication. Sign-in, backend sync, notifications, and cross-device dispatch are not connected.</p><p>${store.state.outbox.length} changes are pending. This build never marks them synced.</p></section><section class="panel"><h2>Protect your local records</h2><p>Data and attached photos are stored in this browser on this site. Clearing site data removes them. Use a stable site address and download backups regularly.</p><p class="muted">Native iOS records are not automatically imported. Keep the original iOS data until a migration has been built and verified.</p>${button('Download workspace backup', 'backup', '', 'primary')}</section><section class="panel"><h2>Web application</h2><p>Plain HTML, CSS, and JavaScript. No Xcode, signing, or Swift package setup is needed.</p><p>For PDF reports, open Invoice prep and choose Print / Save PDF.</p></section>`
  );
}
let onSave, modalDraft, modalType;
function modal(title, fields, save, description = '') {
  onSave = save;
  $('#editor').innerHTML =
    `<form id="editor-form"><div class="section-head"><h2>${esc(title)}</h2>${button('Close', 'close')}</div>${description ? `<p class="muted">${esc(description)}</p>` : ''}<div id="form-error" class="error" role="alert" hidden></div><div id="fields" class="stack">${fields}</div><div class="form-actions">${button('Cancel', 'close')} ${save ? '<button class="primary" type="submit">Save changes</button>' : ''}</div></form>`;
  $('#editor').showModal();
}
function customerEditor(value) {
  const c = entity('customers', value) || {
    id: id(),
    name: '',
    contact: '',
    email: '',
    phone: '',
    notes: '',
    active: true,
  };
  modal(
    value ? 'Edit customer' : 'Add customer',
    `<div class="form-grid">${input('Customer name', 'name', c.name, 'text', 'required')}${input('Contact', 'contact', c.contact)}${input('Email', 'email', c.email, 'email')}${input('Phone', 'phone', c.phone, 'tel')}</div>${textarea('Notes', 'notes', c.notes)}${check('Active customer', 'active', c.active)}`,
    (form) =>
      store.saveCustomer({
        ...c,
        ...formValues(form, ['name', 'contact', 'email', 'phone', 'notes']),
        active: form.elements.active.checked,
      }),
  );
}
const formValues = (form, names) =>
  Object.fromEntries(names.map((name) => [name, form.elements[name].value.trim()]));
function propertyEditor(value, duplicate = false) {
  modalType = 'property';
  modalDraft = structuredClone(
    entity('properties', value) || {
      id: id(),
      name: '',
      address: '',
      customerID: store.state.customers[0]?.id || '',
      crewID: store.state.crews[0]?.id || '',
      active: true,
      instructions: '',
      hazards: '',
      services: [
        {
          id: id(),
          name: 'Snow plowing',
          method: 'perPush',
          rate: '0',
          trigger: '1',
          tiers: [],
          photoRequired: false,
        },
      ],
      checklist: [],
    },
  );
  if (duplicate) {
    modalDraft.id = id();
    modalDraft.name += ' copy';
    modalDraft.services.forEach((s) => (s.id = id()));
    modalDraft.checklist.forEach((c) => (c.id = id()));
  }
  modal(
    duplicate ? 'Duplicate property' : value ? 'Edit property' : 'Add property',
    propertyFields(),
    (form) => {
      captureProperty(form);
      store.saveProperty(modalDraft);
    },
    'Configure the site, service pricing, and required work. Snowfall tiers use inclusive lower and exclusive upper bounds.',
  );
}
function propertyFields() {
  const p = modalDraft;
  return `<div class="form-grid">${input('Property name', 'name', p.name, 'text', 'required')}${input('Address', 'address', p.address, 'text', 'required')}${select(
    'Customer',
    'customerID',
    store.state.customers.map((c) => [c.id, c.name]),
    p.customerID,
  )}${select('Default crew', 'crewID', [['', 'Unassigned'], ...store.state.crews.map((c) => [c.id, c.name])], p.crewID)}</div>${check('Active property', 'active', p.active)}${textarea('Site instructions', 'instructions', p.instructions)}${textarea('Hazards', 'hazards', p.hazards)}<div><div class="section-head"><h3>Services & pricing</h3>${button('+ Add service', 'add-service')}</div>${p.services
    .map(
      (s, i) =>
        `<div class="service" data-service="${i}"><div class="form-grid">${input('Service name', `service-name-${i}`, s.name, 'text', 'required')}${select(
          'Pricing method',
          `service-method-${i}`,
          methods.map((m) => [m, titles[m]]),
          s.method,
        )}${input('Rate ($)', `service-rate-${i}`, s.rate, 'text', 'inputmode="decimal" required')}${input('Trigger (inches)', `service-trigger-${i}`, s.trigger, 'text', 'inputmode="decimal" required')}</div>${check('Photo required', `service-photo-${i}`, s.photoRequired)}${s.method === 'snowfallTier' ? `<div class="stack"><p class="muted">One tier per line: lower, upper, amount, extra rate. Leave upper blank for an open-ended tier.</p>${textarea('Snowfall tiers', `service-tiers-${i}`, s.tiers.map((t) => `${t.lower},${t.upper},${t.amount},${t.additional}`).join('\n'))}</div>` : ''}${button('Remove service', 'remove-service', String(i), 'danger')}</div>`,
    )
    .join(
      '',
    )}</div><div><div class="section-head"><h3>Checklist</h3>${button('+ Add item', 'add-checklist')}</div>${p.checklist
    .map(
      (c, i) =>
        `<div class="service"><div class="form-grid">${input('Item title', `check-title-${i}`, c.title, 'text', 'required')}${select(
          'Response type',
          `check-kind-${i}`,
          ['checkbox', 'yesNo', 'number', 'text', 'photo', 'confirmation'].map((k) => [k, k]),
          c.kind,
        )}</div>${check('Required', `check-required-${i}`, c.required)}${button('Remove item', 'remove-checklist', String(i), 'danger')}</div>`,
    )
    .join('')}</div>`;
}
function captureProperty(form) {
  Object.assign(
    modalDraft,
    formValues(form, ['name', 'address', 'customerID', 'crewID', 'instructions', 'hazards']),
    { active: form.elements.active.checked },
  );
  modalDraft.services.forEach((s, i) => {
    s.name = form.elements[`service-name-${i}`].value;
    s.method = form.elements[`service-method-${i}`].value;
    s.rate = form.elements[`service-rate-${i}`].value;
    s.trigger = form.elements[`service-trigger-${i}`].value;
    s.photoRequired = form.elements[`service-photo-${i}`].checked;
    const tiers = form.elements[`service-tiers-${i}`];
    if (tiers)
      s.tiers = tiers.value
        .trim()
        .split('\n')
        .filter(Boolean)
        .map((line) => {
          const [lower = '', upper = '', amount = '', additional = '0'] = line
            .split(',')
            .map((v) => v.trim());
          return { lower, upper, amount, additional };
        });
  });
  modalDraft.checklist.forEach((c, i) => {
    c.title = form.elements[`check-title-${i}`].value;
    c.kind = form.elements[`check-kind-${i}`].value;
    c.required = form.elements[`check-required-${i}`].checked;
    c.answer = ['checkbox', 'confirmation'].includes(c.kind) ? false : '';
  });
}
function stormEditor() {
  const fields = `<div class="form-grid">${input('Storm name', 'name', '', 'text', 'required')}${select(
    'Start status',
    'status',
    [
      ['preparing', 'Preparing'],
      ['active', 'Activate immediately'],
    ],
    'preparing',
  )}${input('Forecast low (inches)', 'forecastLow', '0', 'text', 'inputmode="decimal" required')}${input('Forecast high (inches)', 'forecastHigh', '0', 'text', 'inputmode="decimal" required')}${input('Operational estimate (inches)', 'operationalSnowfall', '0', 'text', 'inputmode="decimal" required')}</div><h3>Select properties & assign crews</h3>${store.state.properties
    .filter((p) => p.active)
    .map(
      (p) =>
        `<div class="service">${check(p.name, `property-${p.id}`, true)}${select('Assigned crew', `crew-${p.id}`, [['', 'Choose a crew'], ...store.state.crews.map((c) => [c.id, c.name])], p.crewID)}</div>`,
    )
    .join('')}`;
  modal('Prepare a storm', fields, (form) => {
    const selected = store.state.properties
        .filter((p) => form.elements[`property-${p.id}`]?.checked)
        .map((p) => p.id),
      crews = Object.fromEntries(selected.map((p) => [p, form.elements[`crew-${p}`].value]));
    store.createStorm(
      {
        id: id(),
        ...formValues(form, [
          'name',
          'forecastLow',
          'forecastHigh',
          'operationalSnowfall',
          'status',
        ]),
        start: new Date().toISOString(),
        finalSnowfall: null,
      },
      selected,
      crews,
    );
  });
}
function crewEditor(value) {
  const c = entity('crews', value) || { id: id(), name: '', equipment: '' };
  modal(
    'Crew equipment',
    input('Crew name', 'name', c.name, 'text', 'required') +
      textarea('Vehicle / equipment', 'equipment', c.equipment),
    (form) => store.saveCrew({ ...c, ...formValues(form, ['name', 'equipment']) }),
  );
}
function employeeEditor(value) {
  const e = entity('employees', value) || {
      id: id(),
      name: '',
      role: 'field',
      crewID: '',
      grants: [],
    },
    admin = store.actor.role === 'admin';
  modal(
    'Employee assignment',
    input('Employee name', 'name', e.name, 'text', admin ? 'required' : 'readonly') +
      select(
        'Role',
        'role',
        (admin ? ['admin', 'manager', 'field'] : [e.role]).map((r) => [r, r]),
        e.role,
      ) +
      select(
        'Crew',
        'crewID',
        [['', 'Unassigned'], ...store.state.crews.map((c) => [c.id, c.name])],
        e.crewID,
      ) +
      (admin
        ? `<h3>Manager permissions</h3>${permissions.map((p) => check(p, `grant-${p}`, e.grants.includes(p))).join('')}`
        : ''),
    (form) => {
      const updated = {
        ...e,
        ...formValues(form, ['name', 'role', 'crewID']),
        grants: admin ? permissions.filter((p) => form.elements[`grant-${p}`].checked) : e.grants,
      };
      store.transaction('Employee saved', e.id, '', (state) => {
        store.require('manageCrews');
        if (!admin && !entity('employees', e.id))
          throw new Error('Only administrators add employees.');
        if (state.visits.some((v) => !v.departure && !v.canceled && v.employeeIDs.includes(e.id)))
          throw new Error('Complete the employee’s active visit before changing assignments.');
        const index = state.employees.findIndex((item) => item.id === e.id);
        if (index < 0) state.employees.push(updated);
        else state.employees[index] = updated;
      });
    },
    'Development identities only. Production invitations and sign-in require a backend.',
  );
}
function manageStop(value) {
  const a = entity('assignments', value);
  modal(
    'Manage stop',
    `<h3>${esc(propertyName(a.propertyID))}</h3>${select(
      'Assigned crew',
      'crewID',
      store.state.crews.map((c) => [c.id, c.name]),
      a.crewID,
    )}<div class="actions">${button('Save crew', 'reassign', a.id)}${button('Move up', 'up', a.id)}${button('Move down', 'down', a.id)}${button('Dispatch additional visit', 'additional', a.id)}</div>${textarea('Reason for no service', 'reason')} ${button('Account for without service', 'skip', a.id, 'danger')}`,
    null,
  );
}
function site(value) {
  const p = entity('properties', value);
  modal(
    p.name,
    `<p>${esc(p.address)}</p><p>${esc(p.instructions)}</p><p class="notice">${esc(p.hazards)}</p><h3>Services</h3>${p.services.map((s) => `<p>${esc(s.name)} · ${field() ? `Trigger ${esc(s.trigger)}″` : `${esc(titles[s.method])} · $${esc(s.rate)}`}</p>`).join('')}<a class="button primary" target="_blank" rel="noopener noreferrer" href="https://maps.apple.com/?daddr=${encodeURIComponent(p.address)}&dirflg=d">Open directions ↗</a>`,
    null,
  );
}
function visitEditor(value, correction = false) {
  modalType = correction ? 'correction' : 'visit';
  modalDraft = structuredClone(entity('visits', value));
  modal(
    correction ? 'Correct completed visit' : 'Active visit',
    visitFields(correction),
    (form) => {
      captureVisit(form);
      store.saveVisit(modalDraft, false, correction ? form.elements.reason.value : '');
    },
    correction
      ? 'Original values remain in audit history. Billing must be recalculated and reviewed.'
      : 'Save changes before closing. Photos and edits stay in this browser.',
  );
  if (!correction)
    $('#editor-form .form-actions').insertAdjacentHTML(
      'beforeend',
      button('Complete service', 'complete', value, 'primary'),
    );
}
function visitFields(correction) {
  const v = modalDraft;
  return `<p class="notice">${esc(propertyName(v.propertyID))} · Arrival ${date(v.arrival)}</p>${correction ? `<div class="form-grid">${input('Arrival', 'arrival', v.arrival)}${input('Departure', 'departure', v.departure)}</div>` : ''}<h3>Required work</h3>${v.checklist
    .map((c, i) =>
      ['checkbox', 'confirmation'].includes(c.kind)
        ? check(c.title + (c.required ? ' *' : ''), `answer-${i}`, c.answer === true)
        : c.kind === 'yesNo'
          ? select(
              c.title + (c.required ? ' *' : ''),
              `answer-${i}`,
              [
                ['', 'Choose'],
                ['Yes', 'Yes'],
                ['No', 'No'],
              ],
              c.answer,
            )
          : c.kind === 'photo'
            ? select(
                c.title + (c.required ? ' *' : ''),
                `answer-${i}`,
                [['', 'Choose attached photo'], ...v.photos.map((p) => [p.id, p.name])],
                c.answer,
              )
            : input(
                c.title + (c.required ? ' *' : ''),
                `answer-${i}`,
                c.answer,
                'text',
                c.kind === 'number' ? 'inputmode="decimal"' : '',
              ),
    )
    .join('')}<h3>Services</h3>${v.services
    .map(
      (s, i) =>
        `<div class="service">${check(s.name, `performed-${i}`, s.performed)}${input('Quantity', `quantity-${i}`, s.quantity, 'text', 'inputmode="decimal"')}${
          correction && can('reviewBilling')
            ? `<div class="form-grid">${select(
                'Pricing',
                `method-${i}`,
                methods.map((m) => [m, titles[m]]),
                s.method,
              )}${input('Rate ($)', `rate-${i}`, s.rate, 'text', 'inputmode="decimal"')}</div>`
            : ''
        }</div>`,
    )
    .join(
      '',
    )}<h3>Materials</h3>${textarea('One per line: name, quantity, unit', 'materials', v.materials.map((m) => `${m.name},${m.quantity},${m.unit}`).join('\n'))}${textarea('Service notes', 'notes', v.notes)}${!correction ? '<label>Attach service photo (maximum 10 MB; resized for storage)<input type="file" id="photo" accept="image/jpeg,image/png,image/webp"></label>' : ''}<div class="photos">${v.photos.map((p) => `<img src="${esc(p.data)}" alt="${esc(p.name)}">`).join('')}</div>${can('reviewVisits') ? textarea('Required-work override reason', 'overrideReason', v.overrideReason) : ''}${correction ? `${check('Cancel erroneous visit', 'canceled', v.canceled)}${can('reviewBilling') ? check('Billable visit', 'billable', v.billable) : ''}${textarea('Correction reason (required)', 'reason')}` : ''}`;
}
function captureVisit(form) {
  modalDraft.checklist.forEach(
    (c, i) =>
      (c.answer = ['checkbox', 'confirmation'].includes(c.kind)
        ? form.elements[`answer-${i}`].checked
        : form.elements[`answer-${i}`].value),
  );
  modalDraft.services.forEach((s, i) => {
    s.performed = form.elements[`performed-${i}`].checked;
    s.quantity = form.elements[`quantity-${i}`].value;
    if (form.elements[`rate-${i}`]) {
      s.rate = form.elements[`rate-${i}`].value;
      s.method = form.elements[`method-${i}`].value;
    }
  });
  modalDraft.notes = form.elements.notes.value;
  modalDraft.materials = form.elements.materials.value
    .split('\n')
    .filter((line) => line.trim())
    .map((line) => {
      const [name, quantity, unit] = line.split(',').map((v) => v.trim());
      if (!name || quantity === undefined || !unit)
        throw new Error('Materials use: name, quantity, unit.');
      return { id: id(), name, quantity, unit };
    });
  if (form.elements.overrideReason) modalDraft.overrideReason = form.elements.overrideReason.value;
  if (modalType === 'correction') {
    modalDraft.arrival = form.elements.arrival.value;
    modalDraft.departure = form.elements.departure.value;
    modalDraft.canceled = form.elements.canceled.checked;
    if (form.elements.billable) modalDraft.billable = form.elements.billable.checked;
  }
}
function billEditor(value) {
  const b = entity('billing', value),
    storm = entity('storms', b.stormID);
  let lines = [];
  try {
    lines = pricingLines(
      store.state.visits.filter((v) => v.stormID === b.stormID && v.propertyID === b.propertyID),
      storm.finalSnowfall ?? '0',
    );
  } catch (error) {
    lines = [{ service: error.message, cents: '0' }];
  }
  modal(
    'Property billing review',
    `<h3>${esc(propertyName(b.propertyID))}</h3><p class="muted">${esc(storm.name)}</p>${lines.map((l) => `<div class="row"><span>${esc(l.service)}</span><strong>${money(l.cents)}</strong></div>`).join('')}<div class="row"><strong>Calculated total</strong><strong>${money(b.calculated)}</strong></div><div class="row"><strong>Final total</strong><strong>${money(b.override ?? b.calculated)}</strong></div>${storm.status !== 'finalized' ? `${check('Override calculated amount', 'useOverride', b.override !== null)}${input('Final amount ($)', 'amount', (BigInt(b.override ?? b.calculated) / 100n).toString() + '.' + String(BigInt(b.override ?? b.calculated) % 100n).padStart(2, '0'), 'text', 'inputmode="decimal"')}${textarea('Adjustment reason', 'reason', b.reason)}` : `<p>Finalized · ${esc(b.reason)}</p>`}`,
    storm.status !== 'finalized'
      ? (form) =>
          store.reviewBilling(
            b.id,
            form.elements.useOverride.checked ? form.elements.amount.value : null,
            form.elements.reason.value ||
              (form.elements.useOverride.checked ? '' : 'Calculation accepted'),
          )
      : null,
  );
}
function issueEditor(value) {
  const v = entity('visits', value);
  modal(
    'Report a site issue',
    `<h3>${esc(propertyName(v.propertyID))}</h3>${select(
      'Category',
      'category',
      [
        'Vehicle blocking lot',
        'Property inaccessible',
        'Heavy drifting',
        'Ice condition',
        'Equipment problem',
        'Customer request',
        'Damage concern',
        'Service cannot be completed',
      ].map((c) => [c, c]),
      'Vehicle blocking lot',
    )}${select(
      'Severity',
      'severity',
      ['normal', 'high', 'critical'].map((s) => [s, s]),
      'normal',
    )}${textarea('What happened?', 'note')}`,
    (form) =>
      store.reportIssue({
        id: id(),
        stormID: v.stormID,
        propertyID: v.propertyID,
        ...formValues(form, ['category', 'severity', 'note']),
      }),
  );
}
async function resizePhoto(file) {
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    const scale = Math.min(1, 1280 / Math.max(image.naturalWidth, image.naturalHeight));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    const context = canvas.getContext('2d');
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    let data = canvas.toDataURL('image/jpeg', 0.75);
    if (data.length > 600000) data = canvas.toDataURL('image/jpeg', 0.45);
    if (data.length > 600000)
      throw new Error('Photo is too large after resizing. Choose a smaller image.');
    return data;
  } finally {
    URL.revokeObjectURL(url);
  }
}
function errorInModal(error) {
  $('#form-error').hidden = false;
  $('#form-error').textContent = error.message;
  $('#form-error').scrollIntoView({ block: 'nearest' });
}
function navigate(next, value = '') {
  page = next;
  focusedID = value;
  query = '';
  render();
  $('#main').focus();
  window.scrollTo(0, 0);
}
if (store) {
  render();
  document.addEventListener('click', (event) => {
    const link = event.target.closest('[data-page]');
    if (link) {
      event.preventDefault();
      navigate(link.dataset.page);
      return;
    }
    const target = event.target.closest('[data-action]');
    if (!target) return;
    const action = target.dataset.action,
      value = target.dataset.id;
    try {
      switch (action) {
        case 'close':
          if (onSave && !confirm('Close without saving these edits?')) return;
          $('#editor').close();
          return;
        case 'storm':
          navigate('storm', value);
          return;
        case 'route':
          navigate('dispatch', value);
          return;
        case 'visit':
          navigate('visit', value);
          return;
        case 'new-storm':
          stormEditor();
          return;
        case 'customer':
          customerEditor(value);
          return;
        case 'property':
          propertyEditor(value);
          return;
        case 'duplicate-property':
          propertyEditor(value, true);
          return;
        case 'crew':
          crewEditor(value);
          return;
        case 'employee':
          employeeEditor(value);
          return;
        case 'site':
          site(value);
          return;
        case 'manage-stop':
          manageStop(value);
          return;
        case 'bill':
          billEditor(value);
          return;
        case 'issue':
          issueEditor(value);
          return;
        case 'edit-visit':
          visitEditor(value);
          return;
        case 'correct-visit':
          visitEditor(value, true);
          return;
        case 'start': {
          const visitID = store.start(value);
          navigate('visit', visitID);
          visitEditor(visitID);
          return;
        }
        case 'status': {
          const storm = entity('storms', value),
            next = {
              preparing: 'active',
              active: 'wrappingUp',
              wrappingUp: 'underReview',
              underReview: 'finalized',
            }[storm.status];
          if (!confirm(`Change storm to ${titles[next]}? This is recorded in audit history.`))
            return;
          store.setStatus(value, next);
          break;
        }
        case 'resolve':
          store.resolveIssue(value);
          break;
        case 'entered':
          store.markEntered(value);
          break;
        case 'reassign':
          store.dispatch(value, action, $('#editor-form').elements.crewID.value);
          $('#editor').close();
          break;
        case 'skip':
          store.dispatch(value, action, $('#editor-form').elements.reason.value);
          $('#editor').close();
          break;
        case 'up':
        case 'down':
        case 'additional':
          store.dispatch(value, action, '');
          $('#editor').close();
          break;
        case 'add-service':
        case 'remove-service':
        case 'add-checklist':
        case 'remove-checklist': {
          captureProperty($('#editor-form'));
          if (action === 'add-service')
            modalDraft.services.push({
              id: id(),
              name: '',
              rate: '0',
              trigger: '0',
              method: 'perPush',
              tiers: [],
              photoRequired: false,
            });
          if (action === 'remove-service') modalDraft.services.splice(Number(value), 1);
          if (action === 'add-checklist')
            modalDraft.checklist.push({
              id: id(),
              title: '',
              kind: 'checkbox',
              required: true,
              answer: false,
            });
          if (action === 'remove-checklist') modalDraft.checklist.splice(Number(value), 1);
          $('#fields').innerHTML = propertyFields();
          return;
        }
        case 'complete':
          captureVisit($('#editor-form'));
          store.saveVisit(modalDraft, true);
          $('#editor').close();
          break;
        case 'csv':
          download('snowops-invoice-prep.csv', csv(store.state, billingRecords()), 'text/csv');
          return;
        case 'print':
          window.print();
          return;
        case 'backup':
          download(
            'snowops-workspace-backup.json',
            JSON.stringify(store.state, null, 2),
            'application/json',
          );
          return;
        case 'audit-detail': {
          const a = entity('audit', value);
          modal(
            a.action,
            `<p>${esc(a.reason)}</p><details><summary>Original snapshot</summary><pre style="overflow:auto">${esc(JSON.stringify(a.before, null, 2))}</pre></details><details><summary>Updated snapshot</summary><pre style="overflow:auto">${esc(JSON.stringify(a.after, null, 2))}</pre></details>`,
            null,
          );
          return;
        }
      }
      render();
      toast('Saved in this browser.');
    } catch (error) {
      if ($('#editor').open) errorInModal(error);
      else toast(error.message);
    }
  });
  document.addEventListener('submit', (event) => {
    event.preventDefault();
    try {
      if (event.target.id === 'editor-form') {
        onSave(event.target);
        $('#editor').close();
      } else if (event.target.id === 'snowfall-form')
        store.recalculate(focusedID, event.target.elements.snowfall.value);
      render();
      toast('Saved in this browser.');
    } catch (error) {
      if ($('#editor').open) errorInModal(error);
      else toast(error.message);
    }
  });
  document.addEventListener('input', (event) => {
    if (event.target.id === 'search') {
      query = event.target.value;
      const start = event.target.selectionStart;
      render();
      $('#search').focus();
      $('#search').setSelectionRange(start, start);
    }
  });
  document.addEventListener('change', async (event) => {
    if (event.target.id === 'identity') {
      store.actorID = event.target.value;
      navigate('home');
    }
    if (event.target.name === 'billing-filter') {
      billFilter = event.target.value;
      render();
    }
    if (event.target.name?.startsWith('service-method-')) {
      captureProperty($('#editor-form'));
      const service = modalDraft.services[Number(event.target.name.split('-').at(-1))];
      if (service.method === 'snowfallTier' && !service.tiers.length)
        service.tiers = [
          { lower: '0', upper: '3', amount: '250', additional: '0' },
          { lower: '3', upper: '', amount: '475', additional: '80' },
        ];
      $('#fields').innerHTML = propertyFields();
    }
    if (event.target.id === 'photo') {
      const file = event.target.files[0];
      if (!file) return;
      try {
        if (
          !['image/jpeg', 'image/png', 'image/webp'].includes(file.type) ||
          file.size > 10 * 1024 * 1024
        )
          throw new Error('Choose a JPEG, PNG, or WebP photo under 10 MB.');
        captureVisit($('#editor-form'));
        const form = $('#editor-form'),
          draft = modalDraft;
        form.querySelectorAll('button').forEach((b) => (b.disabled = true));
        try {
          const data = await resizePhoto(file);
          if (!$('#editor').open || modalDraft !== draft) return;
          draft.photos.push({ id: id(), name: file.name, data });
          $('#fields').innerHTML = visitFields(false);
        } finally {
          form.querySelectorAll('button').forEach((b) => (b.disabled = false));
        }
      } catch (error) {
        errorInModal(error);
      }
    }
  });
  $('#editor').addEventListener('cancel', (event) => {
    if (onSave && !confirm('Close without saving these edits?')) event.preventDefault();
  });
  window.addEventListener('storage', (event) => {
    if (event.key === STORAGE_KEY)
      toast('Another tab updated this workspace. Reload before editing.');
  });
}
