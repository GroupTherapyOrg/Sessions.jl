import { test, expect } from '@playwright/test';

const BASE_URL = 'http://localhost:8080';
const NOTEBOOK_URL = `${BASE_URL}/notebooks/data-exploration/`;

test.describe('WebSlider island — interactive @bind slider', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(NOTEBOOK_URL);
    await page.waitForLoadState('domcontentloaded');
    // Wait for WASM hydration
    await page.waitForTimeout(3000);
  });

  test('renders therapy-island with webslider component', async ({ page }) => {
    const islands = page.locator('therapy-island[data-component="webslider"]');
    const count = await islands.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  test('webslider island gets hydrated', async ({ page }) => {
    const hydrated = page.locator('therapy-island[data-component="webslider"][data-hydrated]');
    await expect(hydrated.first()).toBeAttached({ timeout: 10000 });
  });

  test('slider has correct min/max/step attributes', async ({ page }) => {
    const slider = page.locator('therapy-island[data-component="webslider"] input[type="range"]').first();
    await expect(slider).toBeAttached({ timeout: 5000 });

    const min = await slider.getAttribute('min');
    const max = await slider.getAttribute('max');
    const step = await slider.getAttribute('step');

    expect(min).toBe('1');
    expect(max).toBe('8');
    expect(step).toBe('1');
  });

  test('slider shows initial value', async ({ page }) => {
    const island = page.locator('therapy-island[data-component="webslider"]').first();
    await expect(island).toBeAttached({ timeout: 5000 });

    const valueDisplay = island.locator('span').first();
    const text = await valueDisplay.textContent();
    expect(text?.trim()).toBe('8');
  });

  test('moving slider updates displayed value', async ({ page }) => {
    const island = page.locator('therapy-island[data-component="webslider"]').first();
    const slider = island.locator('input[type="range"]');
    const valueDisplay = island.locator('span').first();

    await expect(slider).toBeAttached({ timeout: 5000 });
    await slider.fill('3');
    await expect(valueDisplay).toHaveText('3', { timeout: 3000 });
  });

  test('slider responds to multiple value changes', async ({ page }) => {
    const island = page.locator('therapy-island[data-component="webslider"]').first();
    const slider = island.locator('input[type="range"]');
    const valueDisplay = island.locator('span').first();

    await expect(slider).toBeAttached({ timeout: 5000 });

    await slider.fill('1');
    await expect(valueDisplay).toHaveText('1', { timeout: 3000 });

    await slider.fill('5');
    await expect(valueDisplay).toHaveText('5', { timeout: 3000 });

    await slider.fill('8');
    await expect(valueDisplay).toHaveText('8', { timeout: 3000 });
  });

  test('variable name label is displayed', async ({ page }) => {
    const label = page.locator('.notebook-slider');
    await expect(label).toBeAttached({ timeout: 5000 });

    const text = await label.textContent();
    expect(text).toContain('n');
  });

  test('webslider.wasm file is accessible', async ({ page }) => {
    const response = await page.request.get(`${BASE_URL}/webslider.wasm`);
    expect(response.status()).toBe(200);
    expect(response.headers()['content-type']).toBe('application/wasm');
  });

  test('no wasm traps or hydration errors', async ({ page }) => {
    const errors: string[] = [];
    const warnings: string[] = [];

    page.on('console', msg => {
      if (msg.type() === 'error') errors.push(msg.text());
      if (msg.type() === 'warning') warnings.push(msg.text());
    });
    page.on('pageerror', err => errors.push(err.message));

    await page.goto(NOTEBOOK_URL);
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3000);

    const wasmErrors = [...errors, ...warnings].filter(e =>
      e.includes('wasm trap') || e.includes('unreachable') || e.includes('RuntimeError')
    );

    if (wasmErrors.length > 0) {
      console.log('WASM errors:', wasmErrors);
    }
    expect(wasmErrors).toHaveLength(0);
  });
});

test.describe('BoundValue — live WASM reactive cell (no pre-rendering)', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(NOTEBOOK_URL);
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3000);
  });

  test('n cell renders as BoundValue island, not pre-rendered gallery', async ({ page }) => {
    // BoundValue island should exist for the "n" cell
    const boundValue = page.locator('[data-bound-to] therapy-island[data-component="boundvalue"]');
    await expect(boundValue).toBeAttached({ timeout: 5000 });

    // Should NOT be any pre-rendered galleries (table uses reactive table, n uses BoundValue)
    const galleries = page.locator('.notebook-html-gallery');
    expect(await galleries.count()).toBe(0);
  });

  test('BoundValue island hydrates and shows initial value', async ({ page }) => {
    const island = page.locator('therapy-island[data-component="boundvalue"]').first();
    await expect(island).toBeAttached({ timeout: 5000 });

    // Wait for hydration
    const hydrated = page.locator('therapy-island[data-component="boundvalue"][data-hydrated]');
    await expect(hydrated.first()).toBeAttached({ timeout: 10000 });

    // Should show default value 8
    const span = island.locator('span').first();
    await expect(span).toHaveText('8', { timeout: 3000 });
  });

  test('moving slider updates BoundValue via WASM signal (no gallery swap)', async ({ page }) => {
    const slider = page.locator('[data-bind-slider-id] therapy-island input[type="range"]').first();
    await expect(slider).toBeAttached({ timeout: 5000 });

    // Wait for BoundValue hydration
    const boundIsland = page.locator('therapy-island[data-component="boundvalue"][data-hydrated]');
    await expect(boundIsland.first()).toBeAttached({ timeout: 10000 });

    const valueSpan = boundIsland.first().locator('span').first();
    await expect(valueSpan).toHaveText('8', { timeout: 3000 });

    // Move slider — BoundValue updates via WASM, not gallery swap
    await slider.fill('3');
    await expect(valueSpan).toHaveText('3', { timeout: 3000 });
  });

  test('BoundValue responds to multiple slider changes', async ({ page }) => {
    const slider = page.locator('[data-bind-slider-id] therapy-island input[type="range"]').first();
    const boundIsland = page.locator('therapy-island[data-component="boundvalue"][data-hydrated]');
    await expect(boundIsland.first()).toBeAttached({ timeout: 10000 });
    const valueSpan = boundIsland.first().locator('span').first();

    await slider.fill('1');
    await expect(valueSpan).toHaveText('1', { timeout: 3000 });

    await slider.fill('5');
    await expect(valueSpan).toHaveText('5', { timeout: 3000 });

    await slider.fill('8');
    await expect(valueSpan).toHaveText('8', { timeout: 3000 });
  });

  test('boundvalue.wasm file is accessible', async ({ page }) => {
    const response = await page.request.get(`${BASE_URL}/boundvalue.wasm`);
    expect(response.status()).toBe(200);
    expect(response.headers()['content-type']).toBe('application/wasm');
  });
});

test.describe('Reactive table — planets table (SSR all rows, JS row toggling)', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(NOTEBOOK_URL);
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3000);
  });

  test('planets table renders as reactive table (not pre-rendered gallery)', async ({ page }) => {
    const reactiveTable = page.locator('.notebook-reactive-table[data-slider-table]');
    await expect(reactiveTable).toBeAttached({ timeout: 3000 });

    // Should NOT have a pre-rendered gallery for the table
    const gallery = page.locator('.notebook-html-gallery:has(table)');
    expect(await gallery.count()).toBe(0);
  });

  test('table has all 8 rows with data-row-index attributes', async ({ page }) => {
    const table = page.locator('.notebook-reactive-table table');
    await expect(table).toBeAttached({ timeout: 3000 });

    const rows = table.locator('tbody tr[data-row-index]');
    expect(await rows.count()).toBe(8);

    // Verify indices are 1-8
    for (let i = 1; i <= 8; i++) {
      const row = table.locator(`tbody tr[data-row-index="${i}"]`);
      expect(await row.count()).toBe(1);
    }
  });

  test('default shows 8 rows visible, none hidden', async ({ page }) => {
    const table = page.locator('.notebook-reactive-table table');
    await expect(table).toBeAttached({ timeout: 3000 });

    // All 8 rows should be visible at default (n=8)
    for (let i = 1; i <= 8; i++) {
      const row = table.locator(`tbody tr[data-row-index="${i}"]`);
      const display = await row.evaluate(el => el.style.display);
      expect(display).not.toBe('none');
    }
  });

  test('moving slider hides rows beyond slider value', async ({ page }) => {
    const slider = page.locator('[data-bind-slider-id] therapy-island input[type="range"]').first();
    await expect(slider).toBeAttached({ timeout: 5000 });

    const table = page.locator('.notebook-reactive-table table');

    await slider.fill('3');
    await page.waitForTimeout(300);

    // Rows 1-3 visible, rows 4-8 hidden
    for (let i = 1; i <= 3; i++) {
      const row = table.locator(`tbody tr[data-row-index="${i}"]`);
      expect(await row.evaluate(el => el.style.display)).not.toBe('none');
    }
    for (let i = 4; i <= 8; i++) {
      const row = table.locator(`tbody tr[data-row-index="${i}"]`);
      expect(await row.evaluate(el => el.style.display)).toBe('none');
    }
  });

  test('slider changes update visible row count', async ({ page }) => {
    const slider = page.locator('[data-bind-slider-id] therapy-island input[type="range"]').first();
    await expect(slider).toBeAttached({ timeout: 5000 });

    const table = page.locator('.notebook-reactive-table table');

    // Set to 1 — only first row visible
    await slider.fill('1');
    await page.waitForTimeout(300);
    const visibleAt1 = await table.locator('tbody tr[data-row-index]').evaluateAll(
      rows => rows.filter(r => r.style.display !== 'none').length
    );
    expect(visibleAt1).toBe(1);

    // Set to 5 — five rows visible
    await slider.fill('5');
    await page.waitForTimeout(300);
    const visibleAt5 = await table.locator('tbody tr[data-row-index]').evaluateAll(
      rows => rows.filter(r => r.style.display !== 'none').length
    );
    expect(visibleAt5).toBe(5);

    // Set back to 8 — all rows visible
    await slider.fill('8');
    await page.waitForTimeout(300);
    const visibleAt8 = await table.locator('tbody tr[data-row-index]').evaluateAll(
      rows => rows.filter(r => r.style.display !== 'none').length
    );
    expect(visibleAt8).toBe(8);
  });

  test('bond container has data-bind-var and data-bind-slider-id', async ({ page }) => {
    const bondContainer = page.locator('[data-bind-var="n"]');
    await expect(bondContainer).toBeAttached({ timeout: 3000 });
    expect(await bondContainer.getAttribute('data-bind-slider-id')).toBeTruthy();
  });
});
