// Optional browser check: npm install --no-save playwright, then node scripts/test-web-browser.mjs.
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const browser = await chromium.launch({
  executablePath:
    process.env.CHROMIUM_PATH ||
    (existsSync('/usr/bin/chromium') ? '/usr/bin/chromium' : undefined),
  args: ['--no-sandbox'],
});
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage(),
  errors = [];
page.on('pageerror', (error) => errors.push(error.message));
page.on('dialog', (dialog) => dialog.accept());
const nav = (name) => page.getByRole('navigation').getByRole('link', { name, exact: true }).click();
const button = (name) => page.getByRole('button', { name, exact: true });
try {
  await page.goto(process.env.SNOWOPS_URL || 'http://127.0.0.1:3000');
  await page.getByRole('heading', { name: 'Operations overview' }).waitFor();
  await page.screenshot({ path: '/tmp/snowops-desktop.png', fullPage: true });
  // Customer creation, escaped user input, and persistence after reload.
  await nav('Customers');
  await button('+ Add customer').click();
  await page
    .getByLabel('Customer name', { exact: true })
    .fill('<img src=x onerror=alert(1)> Test customer');
  await button('Save changes').click();
  assert.equal(await page.locator('main img').count(), 0);
  await page.reload();
  await nav('Customers');
  await page.getByRole('heading', { name: '<img src=x onerror=alert(1)> Test customer' }).waitFor();
  // Property editor, pricing-method redraw, checklist, and successful save.
  await nav('Properties');
  await button('+ Add property').click();
  await page.getByLabel('Property name', { exact: true }).fill('Browser test property');
  await page.getByLabel('Address', { exact: true }).fill('100 Main Street, Bethlehem, PA');
  await page.getByLabel('Pricing method', { exact: true }).selectOption('snowfallTier');
  await page.getByLabel('Snowfall tiers', { exact: true }).fill('0,3,250,0\n3,,475,80');
  await button('+ Add item').click();
  await page.getByLabel('Item title', { exact: true }).fill('Inspect site');
  await button('Save changes').click();
  await page.getByRole('heading', { name: 'Browser test property' }).waitFor();
  // Crew-scoped field workflow; required work blocks completion, photo and notes survive restart.
  const identity = page.getByLabel('Development identity', { exact: true });
  await identity.selectOption({ label: 'Cameron Davis · field' });
  assert.equal(
    await page
      .getByRole('navigation')
      .getByRole('link', { name: 'Customers', exact: true })
      .count(),
    0,
  );
  await nav('Your route');
  assert.equal(await page.getByRole('heading', { name: 'Snow 2', exact: true }).count(), 0);
  await button('Start visit').first().click();
  await button('Complete service').click();
  await page.locator('#form-error').filter({ hasText: 'Complete required work' }).waitFor();
  for (const checkbox of await page.locator('#editor input[type=checkbox][name^=answer]').all())
    await checkbox.check();
  await page.getByLabel('Service notes', { exact: true }).fill('North gate inspected in browser');
  await page
    .locator('#photo')
    .setInputFiles({ name: 'site.png', mimeType: 'image/png', buffer: await page.screenshot() });
  await page.locator('#editor .photos img').waitFor();
  await button('Complete service').click();
  await page
    .locator('main')
    .getByText('North gate inspected in browser', { exact: true })
    .waitFor();
  await page.reload();
  await page
    .getByLabel('Development identity', { exact: true })
    .selectOption({ label: 'Cameron Davis · field' });
  await nav('Visit history');
  await page.getByLabel('Search visit history').fill('North gate inspected');
  await button('Open visit').click();
  await page
    .locator('main')
    .getByText('North gate inspected in browser', { exact: true })
    .waitFor();
  assert.equal(await page.locator('main .photos img').count(), 1);
  // Admin issue, dispatch accounting, review and finalize through actual controls.
  await page
    .getByLabel('Development identity', { exact: true })
    .selectOption({ label: 'Alex Morgan · admin' });
  await nav('Dispatch');
  for (let i = 0; i < 6; i++) {
    const row = page
      .locator('.row')
      .filter({ has: page.getByRole('button', { name: 'Start visit', exact: true }) })
      .first();
    await row.getByRole('button', { name: 'Manage stop', exact: true }).click();
    await page
      .getByLabel('Reason for no service', { exact: true })
      .fill('Customer requested no service');
    await button('Account for without service').click();
  }
  await nav('Storms');
  await button('Open').first().click();
  await button('Wrap up operations').click();
  await button('Move to review').click();
  await page.getByLabel('Final verified inches', { exact: true }).fill('5');
  await button('Verify & recalculate').click();
  const count = await button('Details').count();
  assert(count > 0);
  for (let i = 0; i < count; i++) {
    await button('Details').nth(i).click();
    await button('Save changes').click();
  }
  await button('Finalize storm').click();
  await page.getByText('Final snowfall: 5″ · Records locked', { exact: true }).waitFor();
  await nav('Invoice prep');
  await button('Mark entered').first().click();
  await page.getByLabel('Show records').selectOption('entered');
  assert.equal(await page.locator('tbody tr').count(), 1);
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    button('Export CSV').click(),
  ]);
  assert.equal(download.suggestedFilename(), 'snowops-invoice-prep.csv');
  // Preparing storm creation and mobile overflow check.
  await nav('Storms');
  await button('+ New storm').click();
  await page.getByLabel('Storm name', { exact: true }).fill('Browser winter storm');
  await button('Save changes').click();
  await page.getByRole('heading', { name: 'Browser winter storm' }).waitFor();
  await page.setViewportSize({ width: 390, height: 844 });
  await nav('Overview');
  assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
  await page.screenshot({ path: '/tmp/snowops-mobile.png', fullPage: true });
  assert.deepEqual(errors, []);
  console.log(
    'PASS: desktop/mobile UI, customer/property/storm creation, safe rendering, crew routes, required checklist, photo persistence, completion, dispatch exceptions, billing review, finalization, invoice marking and CSV download; no browser errors.',
  );
} finally {
  await browser.close();
}
