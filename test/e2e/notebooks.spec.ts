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

test.describe('notebooks index', () => {
  test('links to both notebooks', async ({ page }) => {
    await gotoPage(page, 'notebooks/');

    await expect(page.locator('a[href*="hello-sessions"]')).toBeVisible();
    await expect(page.locator('a[href*="data-exploration"]')).toBeVisible();
  });
});
