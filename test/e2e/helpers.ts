import { Page, expect } from '@playwright/test';

/**
 * Navigate to a page under the Sessions.jl base path and wait for it to load.
 */
export async function gotoPage(page: Page, path: string) {
  // baseURL already includes trailing slash and /Sessions.jl/ prefix via serve symlink
  await page.goto(`./${path}`);
  await page.waitForLoadState('domcontentloaded');
}

/**
 * Assert that a notebook page has at least `minCells` rendered cells.
 * Cells are identified by the `data-cell-id` attribute.
 */
export async function expectNotebookCells(page: Page, minCells: number) {
  const cells = page.locator('[data-cell-id]');
  await expect(cells.first()).toBeVisible({ timeout: 10000 });
  const count = await cells.count();
  expect(count).toBeGreaterThanOrEqual(minCells);
  return cells;
}
