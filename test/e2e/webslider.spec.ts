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

test.describe('WebSlider @bind reactivity — downstream cell updates', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(NOTEBOOK_URL);
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3000);
  });

  test('pre-rendered HTML galleries are embedded in the page', async ({ page }) => {
    // Two dependent cells should have gallery containers
    const galleries = page.locator('.notebook-html-gallery[data-slider-html]');
    const count = await galleries.count();
    expect(count).toBeGreaterThanOrEqual(2); // n cell + planets[1:n] cell
  });

  test('each gallery has 8 pre-rendered variants', async ({ page }) => {
    const galleries = page.locator('.notebook-html-gallery[data-slider-html]');
    const count = await galleries.count();

    for (let i = 0; i < count; i++) {
      const gallery = galleries.nth(i);
      const variants = gallery.locator('> [data-slider-value]');
      expect(await variants.count()).toBe(8);
    }
  });

  test('default value variant is visible, others hidden', async ({ page }) => {
    const gallery = page.locator('.notebook-html-gallery').first();
    const visible = gallery.locator('> [data-slider-value]:not([style*="display:none"])');
    const hidden = gallery.locator('> [data-slider-value][style*="display:none"]');

    expect(await visible.count()).toBe(1);
    expect(await hidden.count()).toBe(7);

    // Default variant should be value 8
    const visibleValue = await visible.first().getAttribute('data-slider-value');
    expect(visibleValue).toBe('8');
  });

  test('moving slider swaps visible variant for n cell', async ({ page }) => {
    const slider = page.locator('[data-bind-slider-id] therapy-island input[type="range"]').first();
    await expect(slider).toBeAttached({ timeout: 5000 });

    const galleries = page.locator('.notebook-html-gallery[data-slider-html]');

    // Move slider to 3
    await slider.fill('3');
    await page.waitForTimeout(300);

    // Check that variant "3" is now visible in at least one gallery
    let found = false;
    const count = await galleries.count();
    for (let i = 0; i < count; i++) {
      const gallery = galleries.nth(i);
      const variant3 = gallery.locator('> [data-slider-value="3"]');
      const isVisible = await variant3.evaluate(el => el.style.display !== 'none');
      if (isVisible) {
        found = true;
        break;
      }
    }
    expect(found).toBe(true);
  });

  test('moving slider hides old variant and shows new one', async ({ page }) => {
    const slider = page.locator('[data-bind-slider-id] therapy-island input[type="range"]').first();
    await expect(slider).toBeAttached({ timeout: 5000 });

    const gallery = page.locator('.notebook-html-gallery').first();

    // Initially value 8 visible
    const variant8 = gallery.locator('> [data-slider-value="8"]');
    const initial8 = await variant8.evaluate(el => el.style.display);
    expect(initial8).not.toBe('none');

    // Move to 3
    await slider.fill('3');
    await page.waitForTimeout(300);

    // Value 8 should now be hidden, value 3 visible
    const variant3 = gallery.locator('> [data-slider-value="3"]');
    expect(await variant8.evaluate(el => el.style.display)).toBe('none');
    expect(await variant3.evaluate(el => el.style.display)).not.toBe('none');
  });

  test('planets table updates when slider changes', async ({ page }) => {
    const slider = page.locator('[data-bind-slider-id] therapy-island input[type="range"]').first();
    await expect(slider).toBeAttached({ timeout: 5000 });

    // Find the table gallery (the one containing <table> elements)
    const tableGallery = page.locator('.notebook-html-gallery:has(table)');
    await expect(tableGallery).toBeAttached({ timeout: 3000 });

    // Default: 8 planets → 8 data rows
    const defaultVariant = tableGallery.locator('> [data-slider-value="8"]');
    const defaultRows = defaultVariant.locator('tbody tr');
    expect(await defaultRows.count()).toBe(8);

    // Move to 3 → should show 3 data rows
    await slider.fill('3');
    await page.waitForTimeout(300);

    const variant3 = tableGallery.locator('> [data-slider-value="3"]');
    const variant3Rows = variant3.locator('tbody tr');
    expect(await variant3.getAttribute('style')).not.toContain('display:none');
    expect(await variant3Rows.count()).toBe(3);
  });

  test('bond container has data-bind-var and data-bind-slider-id', async ({ page }) => {
    const bondContainer = page.locator('[data-bind-var="n"]');
    await expect(bondContainer).toBeAttached({ timeout: 3000 });

    const sliderId = await bondContainer.getAttribute('data-bind-slider-id');
    expect(sliderId).toBeTruthy();
  });
});
