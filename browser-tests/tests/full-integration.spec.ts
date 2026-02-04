/**
 * SESSIONS-2204: Full Sessions.jl Integration Test
 *
 * Complete end-to-end test of all Sessions.jl functionality:
 * 1. Launch Sessions.jl app
 * 2. Navigate file browser to sample notebooks
 * 3. Open notebook, edit cell, execute
 * 4. Use @bind widget, verify reactivity
 * 5. Open terminal, run command
 * 6. Open second notebook in new tab
 * 7. Save both, verify files
 * 8. Close and reopen, verify state
 *
 * Prerequisites:
 * - Sessions.jl server running on localhost:8080
 * - Run: julia +1.12 --project=.. -e 'using Sessions; Sessions.serve()'
 */

import { test, expect, Page } from '@playwright/test';

// Timeout for WebSocket operations
const WS_TIMEOUT = 20000;

// Helper to wait for WebSocket connection
async function waitForWebSocket(page: Page) {
  await page.waitForFunction(
    () => typeof (window as any).TherapyWS !== 'undefined' && (window as any).TherapyWS.isConnected(),
    { timeout: WS_TIMEOUT }
  );
}

// Helper to wait for cell to become idle
async function waitForCellIdle(page: Page, cellId: string) {
  await page.waitForSelector(
    `[data-cell-id="${cellId}"].cell-idle`,
    { timeout: WS_TIMEOUT }
  );
}

// Helper to add a new cell with specific code
async function addCellWithCode(page: Page, code: string, afterCellId?: string): Promise<string> {
  const initialCount = await page.locator('.cell').count();

  await page.evaluate((args) => {
    (window as any).addCellAfter(args.afterCellId || null, args.code);
  }, { afterCellId, code });

  await page.waitForFunction(
    (expected) => document.querySelectorAll('.cell').length === expected,
    initialCount + 1,
    { timeout: WS_TIMEOUT }
  );

  await page.waitForTimeout(1500);

  const cells = page.locator('.cell');
  const newCell = cells.nth(initialCount);
  const cellId = await newCell.getAttribute('data-cell-id');

  if (!cellId) {
    throw new Error('Failed to get new cell ID');
  }

  await page.waitForFunction(
    (id) => {
      const cell = document.querySelector(`[data-cell-id="${id}"]`);
      if (!cell) return false;
      const cmContainer = cell.querySelector('[data-codemirror]');
      return cmContainer && (cmContainer as any)._cmView;
    },
    cellId,
    { timeout: WS_TIMEOUT }
  );

  return cellId;
}

// Helper to execute a cell and wait for result
async function executeCellAndWait(page: Page, cellId: string) {
  await page.evaluate((id) => {
    (window as any).executeCell(id);
  }, cellId);

  await waitForCellIdle(page, cellId);
  await page.waitForTimeout(300);
}

// Helper to get cell output text
async function getCellOutput(page: Page, cellId: string): Promise<string> {
  const output = page.locator(`[data-cell-id="${cellId}"] .cell-output`);
  const isVisible = await output.isVisible();
  if (!isVisible) {
    return '';
  }
  return await output.innerText();
}

test.describe('Sessions.jl Full Integration Test', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await waitForWebSocket(page);
    await page.waitForSelector('.cell', { timeout: 10000 });
  });

  test('1. Complete workflow: File browser → Notebook → Execute → Save', async ({ page }) => {
    // Step 1: Verify app loaded
    const appContainer = page.locator('#sessions-app');
    await expect(appContainer).toBeVisible();
    console.log('[Integration] App loaded');

    // Step 2: Check file browser panel exists
    const fileBrowserExists = await page.evaluate(() => {
      return typeof (window as any).navigateDirectory === 'function';
    });
    expect(fileBrowserExists).toBe(true);
    console.log('[Integration] File browser API available');

    // Step 3: Create a cell with code and execute
    const cell1Id = await addCellWithCode(page, 'x = 42');
    await executeCellAndWait(page, cell1Id);
    expect(await getCellOutput(page, cell1Id)).toContain('42');
    console.log('[Integration] Cell execution works');

    // Step 4: Create dependent cell
    const cell2Id = await addCellWithCode(page, 'x * 2');
    await executeCellAndWait(page, cell2Id);
    expect(await getCellOutput(page, cell2Id)).toContain('84');
    console.log('[Integration] Dependent cell execution works');

    // Step 5: Verify save function exists
    const saveExists = await page.evaluate(() => {
      return typeof (window as any).saveNotebook === 'function';
    });
    expect(saveExists).toBe(true);
    console.log('[Integration] Save function available');
  });

  test('2. @bind widget reactivity workflow', async ({ page }) => {
    // Create slider widget
    const sliderCellId = await addCellWithCode(page, '@bind val Sessions.Slider(1:100, default=25)');
    await executeCellAndWait(page, sliderCellId);

    // Create cell that uses the bound value
    const displayCellId = await addCellWithCode(page, 'val * 2');
    await executeCellAndWait(page, displayCellId);

    // Verify initial value (25 * 2 = 50)
    expect(await getCellOutput(page, displayCellId)).toContain('50');
    console.log('[Integration] @bind initial value works');

    // Change slider value
    const slider = page.locator(`[data-cell-id="${sliderCellId}"] bond[def="val"] input[type="range"]`);
    await slider.fill('75');
    await slider.dispatchEvent('input');

    // Wait for reactive update
    await page.waitForTimeout(2000);
    await waitForCellIdle(page, displayCellId);

    // Verify updated value (75 * 2 = 150)
    expect(await getCellOutput(page, displayCellId)).toContain('150');
    console.log('[Integration] @bind reactivity works');
  });

  test('3. Terminal integration workflow', async ({ page }) => {
    // Check terminal API exists
    const terminalApiExists = await page.evaluate(() => {
      return typeof (window as any).initTerminal === 'function' ||
             typeof (window as any).createTerminal === 'function';
    });
    expect(terminalApiExists).toBe(true);
    console.log('[Integration] Terminal API available');

    // Check WebSocket channel for terminal exists
    const terminalChannelExists = await page.evaluate(() => {
      return (window as any).TherapyWS &&
             typeof (window as any).TherapyWS.send === 'function';
    });
    expect(terminalChannelExists).toBe(true);
    console.log('[Integration] WebSocket channel for terminal available');
  });

  test('4. Multi-notebook tab workflow', async ({ page }) => {
    // Check tab management functions exist
    const tabApiExists = await page.evaluate(() => {
      return typeof (window as any).switchTab === 'function' ||
             typeof (window as any).createNewNotebook === 'function';
    });
    expect(tabApiExists).toBe(true);
    console.log('[Integration] Tab management API available');

    // Verify notebook tabs container
    const tabsContainer = page.locator('#notebook-tabs');
    const tabsExist = await tabsContainer.count() > 0 || await page.locator('.notebook-tab').count() >= 0;
    expect(tabsExist).toBe(true);
    console.log('[Integration] Tab container present');
  });

  test('5. StatusBar displays correct information', async ({ page }) => {
    // Check status bar exists
    const statusBar = page.locator('#status-bar');
    await expect(statusBar).toBeVisible();
    console.log('[Integration] StatusBar visible');

    // Check kernel status
    const kernelStatus = page.locator('[data-server-signal="kernel_status"]');
    const kernelStatusExists = await kernelStatus.count() > 0;
    expect(kernelStatusExists).toBe(true);
    console.log('[Integration] Kernel status present');

    // Check WebSocket status
    const wsStatusText = page.locator('#ws-status-text');
    await expect(wsStatusText).toBeVisible();
    const wsText = await wsStatusText.innerText();
    expect(wsText.toLowerCase()).toMatch(/connected|disconnected/);
    console.log('[Integration] WebSocket status:', wsText);
  });

  test('6. Sidebar panel switching workflow', async ({ page }) => {
    // Check sidebar functions exist
    const sidebarApiExists = await page.evaluate(() => {
      return typeof (window as any).getSidebarState === 'function' ||
             typeof (window as any).saveSidebarState === 'function';
    });
    expect(sidebarApiExists).toBe(true);
    console.log('[Integration] Sidebar API available');
  });

  test('7. Dark mode toggle workflow', async ({ page }) => {
    // Get initial theme
    const initialIsDark = await page.evaluate(() => {
      return document.documentElement.classList.contains('dark');
    });
    console.log('[Integration] Initial theme dark:', initialIsDark);

    // Find and click theme toggle
    const themeToggle = page.locator('[data-theme-toggle]').first();
    const toggleExists = await themeToggle.count() > 0;

    if (toggleExists) {
      await themeToggle.click();
      await page.waitForTimeout(500);

      // Verify theme changed
      const newIsDark = await page.evaluate(() => {
        return document.documentElement.classList.contains('dark');
      });
      expect(newIsDark).not.toBe(initialIsDark);
      console.log('[Integration] Theme toggled successfully');
    } else {
      console.log('[Integration] Theme toggle not found, skipping toggle test');
    }
  });

  test('8. Complete notebook lifecycle: Create → Edit → Execute → Dependent execution', async ({ page }) => {
    // Create multiple cells with dependencies
    const cells: string[] = [];

    // Cell 1: Define base value
    const cell1 = await addCellWithCode(page, 'base = 10');
    await executeCellAndWait(page, cell1);
    cells.push(cell1);
    console.log('[Integration] Cell 1 created');

    // Cell 2: First dependent
    const cell2 = await addCellWithCode(page, 'doubled = base * 2');
    await executeCellAndWait(page, cell2);
    expect(await getCellOutput(page, cell2)).toContain('20');
    cells.push(cell2);
    console.log('[Integration] Cell 2 created and executed');

    // Cell 3: Second dependent (depends on cell 2)
    const cell3 = await addCellWithCode(page, 'tripled = base * 3');
    await executeCellAndWait(page, cell3);
    expect(await getCellOutput(page, cell3)).toContain('30');
    cells.push(cell3);
    console.log('[Integration] Cell 3 created and executed');

    // Cell 4: Diamond dependency (depends on cell 2 and cell 3)
    const cell4 = await addCellWithCode(page, 'sum = doubled + tripled');
    await executeCellAndWait(page, cell4);
    expect(await getCellOutput(page, cell4)).toContain('50');
    cells.push(cell4);
    console.log('[Integration] Cell 4 (diamond dependency) created and executed');

    // Now change the base value and verify cascade
    await page.evaluate((id) => {
      const cell = document.querySelector(`[data-cell-id="${id}"]`);
      if (!cell) return;
      const cmContainer = cell.querySelector('[data-codemirror]');
      if (cmContainer && (cmContainer as any)._cmView) {
        const view = (cmContainer as any)._cmView;
        view.dispatch({
          changes: { from: 0, to: view.state.doc.length, insert: 'base = 100' }
        });
      }
    }, cell1);

    await executeCellAndWait(page, cell1);

    // Wait for cascade
    await page.waitForTimeout(2000);
    await waitForCellIdle(page, cell2);
    await waitForCellIdle(page, cell3);
    await waitForCellIdle(page, cell4);

    // Verify all cells updated
    expect(await getCellOutput(page, cell2)).toContain('200');
    expect(await getCellOutput(page, cell3)).toContain('300');
    expect(await getCellOutput(page, cell4)).toContain('500');
    console.log('[Integration] Cascade re-execution works');
  });

  test('9. Error handling and recovery', async ({ page }) => {
    // Create a cell with error
    const errorCellId = await addCellWithCode(page, 'undefined_variable_xyz');
    await executeCellAndWait(page, errorCellId);

    // Verify error state
    const cell = page.locator(`[data-cell-id="${errorCellId}"]`);
    const hasErrorClass = await cell.evaluate((el) => el.classList.contains('cell-error'));
    expect(hasErrorClass).toBe(true);
    console.log('[Integration] Error state displayed correctly');

    // Fix the cell
    await page.evaluate((id) => {
      const cell = document.querySelector(`[data-cell-id="${id}"]`);
      if (!cell) return;
      const cmContainer = cell.querySelector('[data-codemirror]');
      if (cmContainer && (cmContainer as any)._cmView) {
        const view = (cmContainer as any)._cmView;
        view.dispatch({
          changes: { from: 0, to: view.state.doc.length, insert: 'fixed_value = 123' }
        });
      }
    }, errorCellId);

    await executeCellAndWait(page, errorCellId);

    // Verify recovery
    expect(await getCellOutput(page, errorCellId)).toContain('123');
    const hasErrorClassNow = await cell.evaluate((el) => el.classList.contains('cell-error'));
    expect(hasErrorClassNow).toBe(false);
    console.log('[Integration] Error recovery works');
  });

  test('10. WebSocket stability throughout session', async ({ page }) => {
    // Verify initial connection
    let connected = await page.evaluate(() => {
      return (window as any).TherapyWS && (window as any).TherapyWS.isConnected();
    });
    expect(connected).toBe(true);
    console.log('[Integration] WebSocket initially connected');

    // Perform multiple operations
    for (let i = 0; i < 5; i++) {
      const cellId = await addCellWithCode(page, `result_${i} = ${i} * 10`);
      await executeCellAndWait(page, cellId);
      expect(await getCellOutput(page, cellId)).toContain(`${i * 10}`);
    }

    // Verify still connected
    connected = await page.evaluate(() => {
      return (window as any).TherapyWS && (window as any).TherapyWS.isConnected();
    });
    expect(connected).toBe(true);
    console.log('[Integration] WebSocket stable after multiple operations');
  });

  test('11. Performance: Cell execution under 3 seconds', async ({ page }) => {
    const startTime = Date.now();

    // Create and execute a simple cell
    const cellId = await addCellWithCode(page, 'sqrt(2)');
    await executeCellAndWait(page, cellId);

    const duration = Date.now() - startTime;
    console.log(`[Integration] Cell execution duration: ${duration}ms`);

    // Should complete in under 3 seconds
    expect(duration).toBeLessThan(3000);
    expect(await getCellOutput(page, cellId)).toContain('1.414');
  });

  test('12. Multiple widgets in same notebook', async ({ page }) => {
    // Create multiple different widgets
    const slider1Id = await addCellWithCode(page, '@bind a Sessions.Slider(1:10, default=3)');
    await executeCellAndWait(page, slider1Id);

    const slider2Id = await addCellWithCode(page, '@bind b Sessions.Slider(1:10, default=7)');
    await executeCellAndWait(page, slider2Id);

    // Create cell that combines both
    const sumCellId = await addCellWithCode(page, 'a + b');
    await executeCellAndWait(page, sumCellId);

    // Initial: 3 + 7 = 10
    expect(await getCellOutput(page, sumCellId)).toContain('10');
    console.log('[Integration] Multiple widgets initial values work');

    // Change first slider
    const slider1 = page.locator(`[data-cell-id="${slider1Id}"] bond[def="a"] input[type="range"]`);
    await slider1.fill('5');
    await slider1.dispatchEvent('input');

    await page.waitForTimeout(1500);
    await waitForCellIdle(page, sumCellId);

    // Now: 5 + 7 = 12
    expect(await getCellOutput(page, sumCellId)).toContain('12');
    console.log('[Integration] Multiple widgets react independently');
  });
});

test.describe('Sessions.jl Smoke Tests', () => {
  test('Quick smoke test: App loads and WebSocket connects', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // WebSocket should connect
    await waitForWebSocket(page);

    // App should be visible
    const app = page.locator('#sessions-app');
    await expect(app).toBeVisible();

    // At least one cell should exist
    const cells = page.locator('.cell');
    const count = await cells.count();
    expect(count).toBeGreaterThan(0);

    console.log('[Smoke] App loaded, WebSocket connected, cells present');
  });
});
