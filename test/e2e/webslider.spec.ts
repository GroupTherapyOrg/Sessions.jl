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

    // Should NOT be a pre-rendered gallery (only the table cell uses gallery)
    const galleries = page.locator('.notebook-html-gallery');
    expect(await galleries.count()).toBe(1); // only planets[1:n] table
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

test.describe('Pre-rendered gallery — planets table (fallback for complex outputs)', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(NOTEBOOK_URL);
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3000);
  });

  test('planets table uses pre-rendered gallery with 8 variants', async ({ page }) => {
    const gallery = page.locator('.notebook-html-gallery:has(table)');
    await expect(gallery).toBeAttached({ timeout: 3000 });

    const variants = gallery.locator('> [data-slider-value]');
    expect(await variants.count()).toBe(8);
  });

  test('default table shows 8 rows, others hidden', async ({ page }) => {
    const gallery = page.locator('.notebook-html-gallery:has(table)');
    const visible = gallery.locator('> [data-slider-value="8"]');
    const visibleStyle = await visible.evaluate(el => el.style.display);
    expect(visibleStyle).not.toBe('none');

    const hidden = gallery.locator('> [data-slider-value="1"]');
    expect(await hidden.evaluate(el => el.style.display)).toBe('none');
  });

  test('moving slider swaps planets table', async ({ page }) => {
    const slider = page.locator('[data-bind-slider-id] therapy-island input[type="range"]').first();
    await expect(slider).toBeAttached({ timeout: 5000 });

    const gallery = page.locator('.notebook-html-gallery:has(table)');

    await slider.fill('3');
    await page.waitForTimeout(300);

    // 3-row table should be visible
    const variant3 = gallery.locator('> [data-slider-value="3"]');
    expect(await variant3.evaluate(el => el.style.display)).not.toBe('none');
    expect(await variant3.locator('tbody tr').count()).toBe(3);

    // 8-row table should be hidden
    const variant8 = gallery.locator('> [data-slider-value="8"]');
    expect(await variant8.evaluate(el => el.style.display)).toBe('none');
  });

  test('bond container has data-bind-var and data-bind-slider-id', async ({ page }) => {
    const bondContainer = page.locator('[data-bind-var="n"]');
    await expect(bondContainer).toBeAttached({ timeout: 3000 });
    expect(await bondContainer.getAttribute('data-bind-slider-id')).toBeTruthy();
  });
});
