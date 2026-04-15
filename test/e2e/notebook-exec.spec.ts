import { test, expect } from '@playwright/test';

const LIVE_URL = process.env.LIVE_URL || 'http://localhost:8081';

test.describe('Live app — cell execution', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(LIVE_URL);
    await page.waitForLoadState('domcontentloaded');
    await page.waitForFunction(() => !document.getElementById('nb-loading'), { timeout: 15000 });
    await page.waitForFunction(() => {
      return (window as any).TherapyWS && (window as any).TherapyWS.isConnected();
    }, { timeout: 10000 });
  });

  test('RT-003: execute button runs a cell and output renders', async ({ page }) => {
    // Use JS to run a simple cell (x = 20) via the global API
    const cellId = await page.evaluate(() => {
      const editors = (window as any)._sessionsEditors;
      if (!editors) return null;
      const ids = Object.keys(editors);
      return ids.length > 0 ? ids[0] : null;
    });
    expect(cellId).toBeTruthy();

    // Trigger execution via the global API
    await page.evaluate((cid: string) => {
      (window as any)._sessionsRunCell(cid);
    }, cellId!);

    // Wait for output to appear
    const output = page.locator(`.cell-out[data-cell-id="${cellId}"]`);
    await page.waitForFunction(
      (cid: string) => {
        const el = document.querySelector(`.cell-out[data-cell-id="${cid}"]`);
        return el && el.style.display !== 'none' && el.textContent!.trim().length > 0;
      },
      cellId!,
      { timeout: 15000 }
    );

    const text = await output.textContent();
    expect(text!.trim().length).toBeGreaterThan(0);
  });

  test('E2-002: edit cell code, run, output updates', async ({ page }) => {
    // Get the last editor cell (bc9c0418 — strict_undef, no downstream deps)
    const targetCell = await page.evaluate(() => {
      const editors = (window as any)._sessionsEditors;
      if (!editors) return null;
      const ids = Object.keys(editors);
      return ids.length > 0 ? ids[ids.length - 1] : null;
    });
    expect(targetCell).toBeTruthy();

    // Edit the code to a simple expression
    await page.evaluate((cid: string) => {
      const editors = (window as any)._sessionsEditors;
      if (!editors || !editors[cid]) return;
      const view = editors[cid];
      const cur = view.state.doc.toString();
      view.dispatch({ changes: { from: 0, to: cur.length, insert: '42 + 58' } });
    }, targetCell!);

    // Run via the global API (sends code from editor state)
    await page.evaluate((cid: string) => {
      (window as any)._sessionsRunCell(cid);
    }, targetCell!);

    // Wait for output to contain "100"
    await page.waitForFunction(
      (cid: string) => {
        const el = document.querySelector(`.cell-out[data-cell-id="${cid}"]`);
        return el && el.textContent!.includes('100');
      },
      targetCell!,
      { timeout: 30000 }
    );

    const output = page.locator(`.cell-out[data-cell-id="${targetCell}"]`);
    await expect(output).toContainText('100');
  });

  test('Run All button executes multiple cells', async ({ page }) => {
    const runAllBtn = page.locator('#run-all-btn');
    await expect(runAllBtn).toBeVisible();

    await runAllBtn.click();

    // Wait for at least some cells to produce output (may take a while due to sleep() cells)
    await page.waitForFunction(
      () => {
        const outputs = document.querySelectorAll('.cell-out');
        let visible = 0;
        outputs.forEach((el: any) => {
          if (el.style.display !== 'none' && el.textContent.trim().length > 0) visible++;
        });
        return visible >= 3;
      },
      { timeout: 120000 }
    );

    const outputsWithContent = await page.evaluate(() => {
      const outputs = document.querySelectorAll('.cell-out');
      let count = 0;
      outputs.forEach((el: any) => {
        if (el.style.display !== 'none' && el.textContent.trim().length > 0) count++;
      });
      return count;
    });
    expect(outputsWithContent).toBeGreaterThanOrEqual(3);
  });
});
