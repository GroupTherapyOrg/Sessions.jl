/**
 * SESSIONS-2202: Pluto Notebook Compatibility Suite
 *
 * Tests that Sessions.jl can properly load, execute, and save Pluto notebooks.
 *
 * Prerequisites:
 * - Sessions.jl server running on localhost:8080
 * - Run: julia --project=.. -e 'using Sessions; Sessions.serve()'
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

test.describe('Sessions.jl Pluto Compatibility', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await waitForWebSocket(page);
    await page.waitForSelector('.cell', { timeout: 10000 });
  });

  test('1. Basic computation cells execute correctly', async ({ page }) => {
    // Test basic Pluto-style computation
    const cell1Id = await addCellWithCode(page, 'x = 42');
    await executeCellAndWait(page, cell1Id);

    const output1 = await getCellOutput(page, cell1Id);
    expect(output1).toContain('42');

    // Test dependent cell
    const cell2Id = await addCellWithCode(page, 'y = x * 2');
    await executeCellAndWait(page, cell2Id);

    const output2 = await getCellOutput(page, cell2Id);
    expect(output2).toContain('84');
  });

  test('2. Reactive dependencies update downstream cells', async ({ page }) => {
    // Create dependency chain
    const cell1Id = await addCellWithCode(page, 'n = 5');
    await executeCellAndWait(page, cell1Id);

    const cell2Id = await addCellWithCode(page, 'squared = n^2');
    await executeCellAndWait(page, cell2Id);

    const cell3Id = await addCellWithCode(page, 'cubed = n^3');
    await executeCellAndWait(page, cell3Id);

    // Verify initial outputs
    expect(await getCellOutput(page, cell2Id)).toContain('25');
    expect(await getCellOutput(page, cell3Id)).toContain('125');

    // Update the code in cell1 to change n
    await page.evaluate((id) => {
      const cell = document.querySelector(`[data-cell-id="${id}"]`);
      if (!cell) return;
      const cmContainer = cell.querySelector('[data-codemirror]');
      if (cmContainer && (cmContainer as any)._cmView) {
        const view = (cmContainer as any)._cmView;
        view.dispatch({
          changes: { from: 0, to: view.state.doc.length, insert: 'n = 10' }
        });
      }
    }, cell1Id);

    // Re-execute cell1
    await executeCellAndWait(page, cell1Id);

    // Wait for downstream cells to update
    await page.waitForTimeout(2000);
    await waitForCellIdle(page, cell2Id);
    await waitForCellIdle(page, cell3Id);

    // Verify downstream cells updated
    expect(await getCellOutput(page, cell2Id)).toContain('100');
    expect(await getCellOutput(page, cell3Id)).toContain('1000');
  });

  test('3. Markdown cells render correctly', async ({ page }) => {
    // Add a markdown cell (Pluto style)
    const mdCellId = await addCellWithCode(page, 'md"# Hello World\\n\\nThis is **bold** and *italic*"');
    await executeCellAndWait(page, mdCellId);

    const output = await page.locator(`[data-cell-id="${mdCellId}"] .cell-output`);
    const html = await output.innerHTML();

    // Should contain rendered markdown
    expect(html).toContain('Hello World');
    expect(html.toLowerCase()).toMatch(/<h1|<strong|<em/); // Some HTML formatting
  });

  test('4. Functions can be defined and called', async ({ page }) => {
    // Define a function
    const funcCellId = await addCellWithCode(page, 'double(x) = x * 2');
    await executeCellAndWait(page, funcCellId);

    // Call the function
    const callCellId = await addCellWithCode(page, 'double(21)');
    await executeCellAndWait(page, callCellId);

    expect(await getCellOutput(page, callCellId)).toContain('42');
  });

  test('5. Arrays and collections work', async ({ page }) => {
    // Create an array
    const arrCellId = await addCellWithCode(page, 'arr = [1, 2, 3, 4, 5]');
    await executeCellAndWait(page, arrCellId);

    // Operations on array
    const sumCellId = await addCellWithCode(page, 'sum(arr)');
    await executeCellAndWait(page, sumCellId);

    expect(await getCellOutput(page, sumCellId)).toContain('15');
  });

  test('6. Error states are displayed correctly', async ({ page }) => {
    // Create a cell with an error
    const errorCellId = await addCellWithCode(page, 'undefined_variable + 1');
    await executeCellAndWait(page, errorCellId);

    // Cell should show error state
    const cell = page.locator(`[data-cell-id="${errorCellId}"]`);
    const hasErrorClass = await cell.evaluate((el) => el.classList.contains('cell-error'));
    expect(hasErrorClass).toBe(true);

    // Error message should be displayed
    const output = await getCellOutput(page, errorCellId);
    expect(output.toLowerCase()).toContain('error');
  });

  test('7. Multiple independent cells work correctly', async ({ page }) => {
    // Create several independent cells
    const cell1Id = await addCellWithCode(page, 'a = 100');
    const cell2Id = await addCellWithCode(page, 'b = 200');
    const cell3Id = await addCellWithCode(page, 'c = 300');

    // Execute in any order (should not depend on each other)
    await executeCellAndWait(page, cell3Id);
    await executeCellAndWait(page, cell1Id);
    await executeCellAndWait(page, cell2Id);

    expect(await getCellOutput(page, cell1Id)).toContain('100');
    expect(await getCellOutput(page, cell2Id)).toContain('200');
    expect(await getCellOutput(page, cell3Id)).toContain('300');
  });

  test('8. String operations work', async ({ page }) => {
    // String concatenation (Pluto style)
    const strCellId = await addCellWithCode(page, 'greeting = "Hello, " * "World!"');
    await executeCellAndWait(page, strCellId);

    expect(await getCellOutput(page, strCellId)).toContain('Hello, World!');
  });

  test('9. Boolean expressions evaluate correctly', async ({ page }) => {
    const boolCellId = await addCellWithCode(page, 'result = 5 > 3 && 10 < 20');
    await executeCellAndWait(page, boolCellId);

    expect(await getCellOutput(page, boolCellId)).toContain('true');
  });

  test('10. Diamond dependencies resolve correctly', async ({ page }) => {
    // Create a diamond dependency pattern
    //       a
    //      / \
    //     b   c
    //      \ /
    //       d
    const aId = await addCellWithCode(page, 'a = 10');
    await executeCellAndWait(page, aId);

    const bId = await addCellWithCode(page, 'b = a + 1');
    await executeCellAndWait(page, bId);

    const cId = await addCellWithCode(page, 'c = a + 2');
    await executeCellAndWait(page, cId);

    const dId = await addCellWithCode(page, 'd = b + c');
    await executeCellAndWait(page, dId);

    // Initial: a=10, b=11, c=12, d=23
    expect(await getCellOutput(page, dId)).toContain('23');

    // Change a and verify all downstream update
    await page.evaluate((id) => {
      const cell = document.querySelector(`[data-cell-id="${id}"]`);
      if (!cell) return;
      const cmContainer = cell.querySelector('[data-codemirror]');
      if (cmContainer && (cmContainer as any)._cmView) {
        const view = (cmContainer as any)._cmView;
        view.dispatch({
          changes: { from: 0, to: view.state.doc.length, insert: 'a = 20' }
        });
      }
    }, aId);

    await executeCellAndWait(page, aId);

    // Wait for propagation
    await page.waitForTimeout(2000);
    await waitForCellIdle(page, bId);
    await waitForCellIdle(page, cId);
    await waitForCellIdle(page, dId);

    // New: a=20, b=21, c=22, d=43
    expect(await getCellOutput(page, dId)).toContain('43');
  });
});

test.describe('Sessions.jl Pluto @bind Compatibility', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await waitForWebSocket(page);
    await page.waitForSelector('.cell', { timeout: 10000 });
  });

  test('11. @bind with Slider creates interactive element', async ({ page }) => {
    const sliderCellId = await addCellWithCode(page, '@bind val Sessions.Slider(1:100, default=50)');
    await executeCellAndWait(page, sliderCellId);

    // Verify bond element exists
    const bond = page.locator(`[data-cell-id="${sliderCellId}"] bond[def="val"]`);
    expect(await bond.count()).toBe(1);

    // Verify slider input exists
    const slider = page.locator(`[data-cell-id="${sliderCellId}"] bond[def="val"] input[type="range"]`);
    expect(await slider.count()).toBe(1);
  });

  test('12. @bind value available to dependent cells', async ({ page }) => {
    // Create slider
    const sliderCellId = await addCellWithCode(page, '@bind num Sessions.Slider(1:10, default=5)');
    await executeCellAndWait(page, sliderCellId);

    // Create cell that uses the bound value
    const useCellId = await addCellWithCode(page, 'num');
    await executeCellAndWait(page, useCellId);

    // Should show the default value
    expect(await getCellOutput(page, useCellId)).toContain('5');
  });

  test('13. @bind with CheckBox toggles boolean', async ({ page }) => {
    const checkCellId = await addCellWithCode(page, '@bind flag Sessions.CheckBox(default=false)');
    await executeCellAndWait(page, checkCellId);

    const displayCellId = await addCellWithCode(page, 'flag ? "YES" : "NO"');
    await executeCellAndWait(page, displayCellId);

    // Initial state
    expect(await getCellOutput(page, displayCellId)).toContain('NO');

    // Toggle checkbox
    const checkbox = page.locator(`[data-cell-id="${checkCellId}"] bond[def="flag"] input[type="checkbox"]`);
    await checkbox.click();

    // Wait for reactive update
    await page.waitForTimeout(1500);
    await waitForCellIdle(page, displayCellId);

    expect(await getCellOutput(page, displayCellId)).toContain('YES');
  });

  test('14. @bind with TextField captures text input', async ({ page }) => {
    const textCellId = await addCellWithCode(page, '@bind name Sessions.TextField(default="Julia")');
    await executeCellAndWait(page, textCellId);

    const greetCellId = await addCellWithCode(page, '"Hi, " * name');
    await executeCellAndWait(page, greetCellId);

    expect(await getCellOutput(page, greetCellId)).toContain('Hi, Julia');

    // Change text
    const textField = page.locator(`[data-cell-id="${textCellId}"] bond[def="name"] input[type="text"]`);
    await textField.fill('Pluto');
    await textField.dispatchEvent('input');

    await page.waitForTimeout(1500);
    await waitForCellIdle(page, greetCellId);

    expect(await getCellOutput(page, greetCellId)).toContain('Hi, Pluto');
  });
});
