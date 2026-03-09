import { test, expect } from '@playwright/test';
import { gotoPage } from './helpers';

test.describe('Sessions.jl Docs Smoke Tests', () => {
  test('homepage loads with Sessions title', async ({ page }) => {
    await gotoPage(page, '');
    await expect(page).toHaveTitle(/Sessions/);
  });

  test('getting started page loads', async ({ page }) => {
    await gotoPage(page, 'getting-started/');
    await expect(page.locator('h1')).toContainText(/Getting Started/i);
  });

  test('notebooks index has links to exported notebooks', async ({ page }) => {
    await gotoPage(page, 'notebooks/');
    // Should have at least 2 notebook cards linking to individual notebooks
    const links = page.locator('a[href*="hello-sessions"], a[href*="data-exploration"]');
    await expect(links.first()).toBeVisible({ timeout: 10000 });
    const count = await links.count();
    expect(count).toBeGreaterThanOrEqual(2);
  });
});
