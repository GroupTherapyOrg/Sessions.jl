/**
 * SESSIONS-2003: @bind Integration Test
 *
 * Tests the complete @bind workflow with PlutoUI widgets:
 * 1. Slider affects downstream calculation
 * 2. Multiple bound widgets work independently
 * 3. Widget validation (out of range)
 * 4. Widget initial value propagation
 *
 * Prerequisites:
 * - Sessions.jl server running on localhost:8080
 * - Run: julia --project=.. -e 'using Sessions; Sessions.serve()'
 */

import { test, expect, Page } from '@playwright/test';

// Timeout for WebSocket operations
const WS_TIMEOUT = 15000;

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
  // Get current cell count
  const initialCount = await page.locator('.cell').count();

  // Add cell via JavaScript API with code parameter
  await page.evaluate((args) => {
    (window as any).addCellAfter(args.afterCellId || null, args.code);
  }, { afterCellId, code });

  // Wait for new cell to appear
  await page.waitForFunction(
    (expected) => document.querySelectorAll('.cell').length === expected,
    initialCount + 1,
    { timeout: WS_TIMEOUT }
  );

  // Wait for cell_added channel response and CodeMirror initialization
  await page.waitForTimeout(1500);

  // Find the new cell (last one added)
  const cells = page.locator('.cell');
  const newCell = cells.nth(initialCount);
  const cellId = await newCell.getAttribute('data-cell-id');

  if (!cellId) {
    throw new Error('Failed to get new cell ID');
  }

  // Wait for CodeMirror to initialize on this cell
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
  // Debug: Log what we're about to send
  const executeDebug = await page.evaluate((id) => {
    const cell = document.querySelector(`[data-cell-id="${id}"]`);
    if (!cell) return { error: 'CELL NOT FOUND' };
    const cmContainer = cell.querySelector('[data-codemirror]');
    const code = cmContainer && (cmContainer as any)._cmView
      ? (cmContainer as any)._cmView.state.doc.toString()
      : 'NO CODEMIRROR';
    const notebookId = (window as any).getNotebookId ? (window as any).getNotebookId() : 'NO NOTEBOOK ID';
    return { cellId: id, code, notebookId };
  }, cellId);
  console.log('[Test] Execute debug:', executeDebug);

  // Execute the cell
  await page.evaluate((id) => {
    console.log('[Sessions JS] Calling executeCell with id:', id);
    (window as any).executeCell(id);
  }, cellId);

  // Wait for execution to complete
  await waitForCellIdle(page, cellId);

  // Small delay for output to render
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

// Helper to check if a bond element exists in a cell
async function hasBondElement(page: Page, cellId: string, bondName: string): Promise<boolean> {
  const bondElement = page.locator(`[data-cell-id="${cellId}"] bond[def="${bondName}"]`);
  return await bondElement.count() > 0;
}

test.describe('Sessions.jl @bind Integration', () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to notebook and wait for page load
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Wait for WebSocket connection
    await waitForWebSocket(page);

    // Wait for initial cells to load
    await page.waitForSelector('.cell', { timeout: 10000 });
  });

  test('1. Slider affects downstream calculation', async ({ page }) => {
    // This test verifies that:
    // 1. A slider widget can be created with @bind
    // 2. Moving the slider updates the bound variable
    // 3. Downstream cells that reference the variable re-execute

    // First, add a cell that defines a slider bound to variable 'n'
    const sliderCellId = await addCellWithCode(page, '@bind n Sessions.Slider(1:10, default=5)');

    // Debug: Log cell ID and code
    console.log('[Test] Created slider cell:', sliderCellId);
    const cellCode = await page.evaluate((id) => {
      const cell = document.querySelector(`[data-cell-id="${id}"]`);
      if (!cell) return 'CELL NOT FOUND';
      const cmContainer = cell.querySelector('[data-codemirror]');
      if (cmContainer && (cmContainer as any)._cmView) {
        return (cmContainer as any)._cmView.state.doc.toString();
      }
      return 'NO CODEMIRROR';
    }, sliderCellId);
    console.log('[Test] Cell code from CodeMirror:', cellCode);

    // Execute the slider cell
    await executeCellAndWait(page, sliderCellId);

    // Debug: Wait a bit more and check output area
    await page.waitForTimeout(2000);
    const outputDebug = await page.evaluate((id) => {
      const cell = document.querySelector(`[data-cell-id="${id}"]`);
      if (!cell) return 'CELL NOT FOUND';
      const output = cell.querySelector('.cell-output');
      if (!output) return 'NO OUTPUT ELEMENT';
      return {
        html: output.innerHTML,
        hidden: output.classList.contains('hidden'),
        signalName: output.getAttribute('data-signal-html')
      };
    }, sliderCellId);
    console.log('[Test] Output debug:', outputDebug);

    // Verify the bond element was created
    const hasBond = await hasBondElement(page, sliderCellId, 'n');
    console.log('[Test] Has bond element:', hasBond);
    expect(hasBond).toBe(true);

    // Add a cell that references 'n'
    const computeCellId = await addCellWithCode(page, 'n * 2');

    // Execute the compute cell
    await executeCellAndWait(page, computeCellId);

    // Check initial output (n=5, so n*2=10)
    const initialOutput = await getCellOutput(page, computeCellId);
    expect(initialOutput).toContain('10');

    // Now interact with the slider - change value to 8
    const slider = page.locator(`[data-cell-id="${sliderCellId}"] bond[def="n"] input[type="range"]`);
    await slider.evaluate((el: HTMLInputElement) => {
      el.value = '8';
      el.dispatchEvent(new Event('input', { bubbles: true }));
    });

    // Wait for reactive update
    await page.waitForTimeout(1000);

    // Verify the downstream cell updated (n=8, so n*2=16)
    await waitForCellIdle(page, computeCellId);
    const updatedOutput = await getCellOutput(page, computeCellId);
    expect(updatedOutput).toContain('16');
  });

  test('2. Multiple bound widgets work independently', async ({ page }) => {
    // This test verifies that multiple @bind widgets can coexist

    // Add first slider
    const slider1CellId = await addCellWithCode(page, '@bind a Sessions.Slider(1:10, default=3)');
    await executeCellAndWait(page, slider1CellId);

    // Add second slider
    const slider2CellId = await addCellWithCode(page, '@bind b Sessions.Slider(1:10, default=7)');
    await executeCellAndWait(page, slider2CellId);

    // Add cell that uses both
    const sumCellId = await addCellWithCode(page, 'a + b');
    await executeCellAndWait(page, sumCellId);

    // Check initial sum (3 + 7 = 10)
    const initialOutput = await getCellOutput(page, sumCellId);
    expect(initialOutput).toContain('10');

    // Change only the first slider to 5
    const slider1 = page.locator(`[data-cell-id="${slider1CellId}"] bond[def="a"] input[type="range"]`);
    await slider1.evaluate((el: HTMLInputElement) => {
      el.value = '5';
      el.dispatchEvent(new Event('input', { bubbles: true }));
    });

    // Wait for reactive update
    await page.waitForTimeout(1000);
    await waitForCellIdle(page, sumCellId);

    // Verify sum updated (5 + 7 = 12)
    const afterSlider1 = await getCellOutput(page, sumCellId);
    expect(afterSlider1).toContain('12');

    // Change the second slider to 2
    const slider2 = page.locator(`[data-cell-id="${slider2CellId}"] bond[def="b"] input[type="range"]`);
    await slider2.evaluate((el: HTMLInputElement) => {
      el.value = '2';
      el.dispatchEvent(new Event('input', { bubbles: true }));
    });

    // Wait for reactive update
    await page.waitForTimeout(1000);
    await waitForCellIdle(page, sumCellId);

    // Verify sum updated (5 + 2 = 7)
    const afterSlider2 = await getCellOutput(page, sumCellId);
    expect(afterSlider2).toContain('7');
  });

  test('3. Widget initial value propagation', async ({ page }) => {
    // This test verifies that initial values are correctly set

    // Add a slider with default=7
    const sliderCellId = await addCellWithCode(page, '@bind x Sessions.Slider(1:10, default=7)');
    await executeCellAndWait(page, sliderCellId);

    // Add a cell that displays the value
    const displayCellId = await addCellWithCode(page, 'x');
    await executeCellAndWait(page, displayCellId);

    // The initial value should be 7 (the default)
    const output = await getCellOutput(page, displayCellId);
    expect(output).toContain('7');

    // Also verify the slider input element has the correct value
    const slider = page.locator(`[data-cell-id="${sliderCellId}"] bond[def="x"] input[type="range"]`);
    const sliderValue = await slider.inputValue();
    expect(sliderValue).toBe('7');
  });

  test('4. CheckBox widget works', async ({ page }) => {
    // Test checkbox widget with boolean binding

    // Add checkbox cell
    const checkboxCellId = await addCellWithCode(page, '@bind enabled Sessions.CheckBox(default=false)');
    await executeCellAndWait(page, checkboxCellId);

    // Add conditional cell
    const conditionalCellId = await addCellWithCode(page, 'enabled ? "ON" : "OFF"');
    await executeCellAndWait(page, conditionalCellId);

    // Initial state should be OFF (false)
    const initialOutput = await getCellOutput(page, conditionalCellId);
    expect(initialOutput).toContain('OFF');

    // Click the checkbox to toggle
    const checkbox = page.locator(`[data-cell-id="${checkboxCellId}"] bond[def="enabled"] input[type="checkbox"]`);
    await checkbox.click();

    // Wait for reactive update
    await page.waitForTimeout(1000);
    await waitForCellIdle(page, conditionalCellId);

    // Should now be ON
    const afterCheck = await getCellOutput(page, conditionalCellId);
    expect(afterCheck).toContain('ON');
  });

  test('5. TextField widget works', async ({ page }) => {
    // Test text field widget with string binding

    // Add text field cell
    const textCellId = await addCellWithCode(page, '@bind name Sessions.TextField(default="World")');
    await executeCellAndWait(page, textCellId);

    // Add greeting cell
    const greetingCellId = await addCellWithCode(page, '"Hello, " * name * "!"');
    await executeCellAndWait(page, greetingCellId);

    // Initial greeting should be "Hello, World!"
    const initialOutput = await getCellOutput(page, greetingCellId);
    expect(initialOutput).toContain('Hello, World!');

    // Change the text to "Julia"
    const textField = page.locator(`[data-cell-id="${textCellId}"] bond[def="name"] input[type="text"]`);
    await textField.fill('Julia');
    await textField.dispatchEvent('input');

    // Wait for reactive update
    await page.waitForTimeout(1000);
    await waitForCellIdle(page, greetingCellId);

    // Should now greet Julia
    const afterChange = await getCellOutput(page, greetingCellId);
    expect(afterChange).toContain('Hello, Julia!');
  });

  test('6. Select widget works', async ({ page }) => {
    // Test dropdown/select widget

    // Add select cell with options
    const selectCellId = await addCellWithCode(
      page,
      '@bind color Sessions.Select(["red" => "Red", "green" => "Green", "blue" => "Blue"], default="green")'
    );
    await executeCellAndWait(page, selectCellId);

    // Add display cell
    const displayCellId = await addCellWithCode(page, '"Selected: " * color');
    await executeCellAndWait(page, displayCellId);

    // Initial selection should be "green"
    const initialOutput = await getCellOutput(page, displayCellId);
    expect(initialOutput).toContain('green');

    // Change selection to "blue"
    const select = page.locator(`[data-cell-id="${selectCellId}"] bond[def="color"] select`);
    await select.selectOption('blue');

    // Wait for reactive update
    await page.waitForTimeout(1000);
    await waitForCellIdle(page, displayCellId);

    // Should now show blue
    const afterChange = await getCellOutput(page, displayCellId);
    expect(afterChange).toContain('blue');
  });
});

test.describe('Sessions.jl @bind Edge Cases', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await waitForWebSocket(page);
    await page.waitForSelector('.cell', { timeout: 10000 });
  });

  test('7. Bond survives cell re-execution', async ({ page }) => {
    // When a cell with @bind is re-executed, the bond should still work

    // Add slider cell
    const sliderCellId = await addCellWithCode(page, '@bind val Sessions.Slider(1:100, default=50)');
    await executeCellAndWait(page, sliderCellId);

    // Add display cell
    const displayCellId = await addCellWithCode(page, 'val');
    await executeCellAndWait(page, displayCellId);

    // Verify initial value
    let output = await getCellOutput(page, displayCellId);
    expect(output).toContain('50');

    // Re-execute the slider cell
    await executeCellAndWait(page, sliderCellId);

    // Change slider value
    const slider = page.locator(`[data-cell-id="${sliderCellId}"] bond[def="val"] input[type="range"]`);
    await slider.evaluate((el: HTMLInputElement) => {
      el.value = '75';
      el.dispatchEvent(new Event('input', { bubbles: true }));
    });

    // Wait for reactive update
    await page.waitForTimeout(1000);
    await waitForCellIdle(page, displayCellId);

    // Should still update
    output = await getCellOutput(page, displayCellId);
    expect(output).toContain('75');
  });

  test('8. Rapid slider changes handle gracefully', async ({ page }) => {
    // Test that rapid changes don't break the system (lossy updates)

    // Add slider cell
    const sliderCellId = await addCellWithCode(page, '@bind fast Sessions.Slider(1:100, default=1)');
    await executeCellAndWait(page, sliderCellId);

    // Add display cell
    const displayCellId = await addCellWithCode(page, 'fast');
    await executeCellAndWait(page, displayCellId);

    // Rapidly change slider values
    const slider = page.locator(`[data-cell-id="${sliderCellId}"] bond[def="fast"] input[type="range"]`);

    for (let i = 10; i <= 100; i += 10) {
      await slider.evaluate((el: HTMLInputElement, val) => {
        el.value = String(val);
        el.dispatchEvent(new Event('input', { bubbles: true }));
      }, i);
      await page.waitForTimeout(50); // Small delay between changes
    }

    // Wait for final update
    await page.waitForTimeout(2000);
    await waitForCellIdle(page, displayCellId);

    // Final value should be close to 100 (may skip some intermediate values)
    const output = await getCellOutput(page, displayCellId);
    const value = parseInt(output.trim());
    expect(value).toBeGreaterThanOrEqual(50); // At least got some updates
    expect(value).toBeLessThanOrEqual(100);
  });
});
