import { test, expect } from '@playwright/test';
import { gotoPage, expectNotebookCells } from './helpers';

test.describe('hello-sessions notebook', () => {
  test('renders with code blocks, prose, and outputs', async ({ page }) => {
    await gotoPage(page, 'notebooks/hello-sessions/');

    // Should have multiple rendered cells (prose + code)
    await expectNotebookCells(page, 5);

    // Should have code blocks
    const codeBlocks = page.locator('pre code');
    await expect(codeBlocks.first()).toBeVisible();
  });

  test('shows fibonacci output 55', async ({ page }) => {
    await gotoPage(page, 'notebooks/hello-sessions/');

    // The fibonacci(10) cell should produce output "55"
    await expect(page.getByText('55', { exact: true })).toBeVisible({ timeout: 10000 });
  });

  test('code blocks render with pre+code elements', async ({ page }) => {
    await gotoPage(page, 'notebooks/hello-sessions/');

    // CodeBlock renders code in pre > code elements
    const codeElements = page.locator('pre code');
    await expect(codeElements.first()).toBeVisible({ timeout: 10000 });
    const count = await codeElements.count();
    expect(count).toBeGreaterThanOrEqual(3);
  });

  test('runtime badges visible on code cells', async ({ page }) => {
    await gotoPage(page, 'notebooks/hello-sessions/');

    const badges = page.locator('.runtime-badge');
    await expect(badges.first()).toBeVisible({ timeout: 10000 });
  });
});

test.describe('data-exploration notebook', () => {
  test('renders table elements', async ({ page }) => {
    await gotoPage(page, 'notebooks/data-exploration/');

    // Should have at least one HTML table from NamedTuple rendering
    const tables = page.locator('table');
    await expect(tables.first()).toBeVisible({ timeout: 10000 });
  });

  test('renders with cells', async ({ page }) => {
    await gotoPage(page, 'notebooks/data-exploration/');

    await expectNotebookCells(page, 4);
  });
});

test.describe('interactive-plots notebook', () => {
  test('renders slider inputs', async ({ page }) => {
    await gotoPage(page, 'notebooks/interactive-plots/');

    // Should have 2 slider inputs (w and periods)
    const sliders = page.locator('input[type="range"]');
    await expect(sliders.first()).toBeVisible({ timeout: 30000 });
    const count = await sliders.count();
    expect(count).toBe(2);
  });

  test('slider has correct min/max attributes', async ({ page }) => {
    await gotoPage(page, 'notebooks/interactive-plots/');

    // First slider: w (2:12)
    const firstSlider = page.locator('input[type="range"]').first();
    await expect(firstSlider).toBeVisible({ timeout: 30000 });
    await expect(firstSlider).toHaveAttribute('min', '2');
    await expect(firstSlider).toHaveAttribute('max', '12');
    await expect(firstSlider).toHaveAttribute('value', '6');
  });

  test('plot images visible as base64 img tags', async ({ page }) => {
    await gotoPage(page, 'notebooks/interactive-plots/');

    // Should have img tags with data-slider-value attributes (pre-rendered gallery)
    const galleryImages = page.locator('img[data-slider-value]');
    const totalCount = await galleryImages.count();
    expect(totalCount).toBe(17); // 11 for w + 6 for periods

    // Default images should be visible (display:block) — one per gallery
    const defaultW = page.locator('img[data-slider-value="6"][style*="display:block"]').first();
    await expect(defaultW).toBeVisible({ timeout: 30000 });
    const defaultP = page.locator('img[data-slider-value="3"][style*="display:block"]').first();
    await expect(defaultP).toBeVisible();
  });

  test('slider interaction swaps image and updates label', async ({ page }) => {
    await gotoPage(page, 'notebooks/interactive-plots/');

    const firstSlider = page.locator('input[type="range"]').first();
    await expect(firstSlider).toBeVisible({ timeout: 30000 });

    // Get the slider display element
    const sliderId = await firstSlider.getAttribute('data-notebook-slider');
    const display = page.locator(`[data-slider-display="${sliderId}"]`);
    await expect(display).toHaveText('6'); // default value

    // Change slider value
    await firstSlider.fill('8');
    await firstSlider.dispatchEvent('input');

    // Label should update
    await expect(display).toHaveText('8');

    // Image for value 8 should be visible, value 6 should be hidden
    const gallery = page.locator(`[data-slider-images="${sliderId}"]`);
    const img8 = gallery.locator('img[data-slider-value="8"]');
    const img6 = gallery.locator('img[data-slider-value="6"]');
    await expect(img8).toHaveCSS('display', 'block');
    await expect(img6).toHaveCSS('display', 'none');
  });

  test('renders with prose and code cells', async ({ page }) => {
    await gotoPage(page, 'notebooks/interactive-plots/');

    // Should have cells rendered (prose + code + slider + plots)
    await expectNotebookCells(page, 4);
  });
});

test.describe('notebooks index', () => {
  test('links to all three notebooks', async ({ page }) => {
    await gotoPage(page, 'notebooks/');

    await expect(page.locator('a[href*="hello-sessions"]')).toBeVisible();
    await expect(page.locator('a[href*="data-exploration"]')).toBeVisible();
    await expect(page.locator('a[href*="interactive-plots"]')).toBeVisible();
  });
});
