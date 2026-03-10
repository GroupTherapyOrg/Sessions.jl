import { test, expect } from '@playwright/test';

const BASE_URL = 'http://localhost:8082';
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

    // The span showing current value should display the default
    const valueDisplay = island.locator('span').first();
    const text = await valueDisplay.textContent();
    expect(text?.trim()).toBe('8');
  });

  test('moving slider updates displayed value', async ({ page }) => {
    const island = page.locator('therapy-island[data-component="webslider"]').first();
    const slider = island.locator('input[type="range"]');
    const valueDisplay = island.locator('span').first();

    await expect(slider).toBeAttached({ timeout: 5000 });

    // Get initial value
    const initialValue = await valueDisplay.textContent();
    expect(initialValue?.trim()).toBe('8');

    // Move slider to a different value by filling
    await slider.fill('3');

    // Value display should update via WASM signal
    await expect(valueDisplay).toHaveText('3', { timeout: 3000 });
  });

  test('slider responds to multiple value changes', async ({ page }) => {
    const island = page.locator('therapy-island[data-component="webslider"]').first();
    const slider = island.locator('input[type="range"]');
    const valueDisplay = island.locator('span').first();

    await expect(slider).toBeAttached({ timeout: 5000 });

    // Move to 1
    await slider.fill('1');
    await expect(valueDisplay).toHaveText('1', { timeout: 3000 });

    // Move to 5
    await slider.fill('5');
    await expect(valueDisplay).toHaveText('5', { timeout: 3000 });

    // Move to 8
    await slider.fill('8');
    await expect(valueDisplay).toHaveText('8', { timeout: 3000 });
  });

  test('variable name label is displayed', async ({ page }) => {
    // The bond label "n = " should appear before the slider
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

    // No wasm traps
    const wasmErrors = [...errors, ...warnings].filter(e =>
      e.includes('wasm trap') || e.includes('unreachable') || e.includes('RuntimeError')
    );

    if (wasmErrors.length > 0) {
      console.log('WASM errors:', wasmErrors);
    }
    expect(wasmErrors).toHaveLength(0);
  });
});
