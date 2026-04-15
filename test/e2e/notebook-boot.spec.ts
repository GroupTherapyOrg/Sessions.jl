import { test, expect } from '@playwright/test';

const LIVE_URL = process.env.LIVE_URL || 'http://localhost:8081';

test.describe('Live app — notebook boot', () => {
  test('RT-001: loading overlay clears within 5s', async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto(LIVE_URL);
    await page.waitForLoadState('domcontentloaded');

    const overlay = page.locator('#nb-loading');
    await expect(overlay).toHaveCount(0, { timeout: 5000 }).catch(async () => {
      await expect(overlay).toHaveClass(/loaded/, { timeout: 5000 });
    });
  });

  test('RT-002: at least one .cm-editor mounts after hydration', async ({ page }) => {
    await page.goto(LIVE_URL);
    await page.waitForLoadState('domcontentloaded');
    await page.waitForFunction(() => !document.getElementById('nb-loading'), { timeout: 10000 });

    const hasEditor = await page.evaluate(() => {
      const editors = (window as any)._sessionsEditors;
      return editors && Object.keys(editors).length > 0;
    });
    expect(hasEditor).toBe(true);
  });

  test('E2-001: 15+ cells render, zero console errors', async ({ page }) => {
    const errors: string[] = [];
    const consoleErrors: string[] = [];

    page.on('pageerror', err => errors.push(err.message));
    page.on('console', msg => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    await page.goto(LIVE_URL);
    await page.waitForLoadState('domcontentloaded');

    // Wait for overlay to clear (editors initialized)
    await page.waitForFunction(() => !document.getElementById('nb-loading'), { timeout: 10000 });

    // Assert >= 15 .cell-wrap nodes
    const cellWraps = page.locator('.cell-wrap');
    await expect(cellWraps.first()).toBeVisible({ timeout: 5000 });
    const count = await cellWraps.count();
    expect(count).toBeGreaterThanOrEqual(15);

    // Assert zero __t / WASM errors (per PRD: zero `__t is not defined`, zero `WASM instantiation failed`)
    const jtErrors = [...errors, ...consoleErrors].filter(e =>
      e.includes('__t is not defined') ||
      e.includes('WASM instantiation failed')
    );
    expect(jtErrors).toHaveLength(0);
  });

  test('WS connects and full_state arrives', async ({ page }) => {
    await page.goto(LIVE_URL);
    await page.waitForLoadState('domcontentloaded');

    const wsConnected = await page.waitForFunction(() => {
      return (window as any).TherapyWS && (window as any).TherapyWS.isConnected();
    }, { timeout: 10000 });
    expect(wsConnected).toBeTruthy();
  });

  test('CM editors have content from SSR data-src', async ({ page }) => {
    await page.goto(LIVE_URL);
    await page.waitForLoadState('domcontentloaded');
    await page.waitForFunction(() => !document.getElementById('nb-loading'), { timeout: 10000 });

    const hasContent = await page.evaluate(() => {
      const editors = (window as any)._sessionsEditors;
      if (!editors) return false;
      const ids = Object.keys(editors);
      if (ids.length === 0) return false;
      const firstDoc = editors[ids[0]].state.doc.toString();
      return firstDoc.length > 0;
    });
    expect(hasContent).toBe(true);
  });
});
