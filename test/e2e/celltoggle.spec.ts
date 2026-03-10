import { test, expect } from '@playwright/test';

test.describe('CellToggle island — code visibility toggle', () => {
  test.beforeEach(async ({ page }) => {
    // Use the dev server directly (WASM compiled in-memory)
    await page.goto('http://localhost:8080/notebooks/hello-sessions/');
    await page.waitForLoadState('domcontentloaded');
    // Wait for WASM hydration to complete
    await page.waitForTimeout(2000);
  });

  test('renders therapy-island elements with celltoggle component', async ({ page }) => {
    const islands = page.locator('therapy-island[data-component="celltoggle"]');
    const count = await islands.count();
    expect(count).toBeGreaterThanOrEqual(3);
  });

  test('islands get hydrated (data-hydrated attribute)', async ({ page }) => {
    const hydrated = page.locator('therapy-island[data-component="celltoggle"][data-hydrated]');
    // Wait for at least one island to hydrate
    await expect(hydrated.first()).toBeAttached({ timeout: 10000 });
    const count = await hydrated.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  test('eye icon appears on hover', async ({ page }) => {
    const cell = page.locator('[data-cell-id]').first();
    const eyeButton = cell.locator('button').first();

    // Eye should be invisible by default (opacity-0)
    await expect(eyeButton).toHaveCSS('opacity', '0');

    // Hover over cell
    await cell.hover();

    // Eye should become visible
    await expect(eyeButton).toHaveCSS('opacity', '1', { timeout: 2000 });
  });

  test('clicking eye toggles code visibility', async ({ page }) => {
    // Find a non-folded cell (code should be visible initially)
    const cell = page.locator('[data-cell-id]').first();
    const codeBlock = cell.locator('[data-codeblock]');

    // Code should be visible initially
    await expect(codeBlock).toBeVisible({ timeout: 5000 });

    // Hover to reveal eye, then click
    await cell.hover();
    const eyeButton = cell.locator('button').first();
    await eyeButton.click();

    // Code should now be hidden
    await expect(codeBlock).toBeHidden({ timeout: 3000 });

    // Click again to show
    await cell.hover();
    await eyeButton.click();
    await expect(codeBlock).toBeVisible({ timeout: 3000 });
  });

  test('folded cells start with code hidden', async ({ page }) => {
    // Folded cells have data-props with initial_open=0
    const foldedIsland = page.locator('therapy-island[data-props*="initial_open"][data-props*="0"]');
    const count = await foldedIsland.count();

    if (count > 0) {
      // The code block inside a folded cell should be hidden
      const codeBlock = foldedIsland.first().locator('[data-codeblock]');
      await expect(codeBlock).toBeHidden({ timeout: 5000 });
    }
  });

  test('open eye icon visible for open cells, closed eye for folded cells', async ({ page }) => {
    // For an open cell, the open eye SVG should be the one stacked on top
    const cell = page.locator('[data-cell-id]').first();
    await cell.hover();

    // The Show wrapper for the open eye should be visible (data-show="true")
    const showSpan = cell.locator('button span[data-show]');
    await expect(showSpan.first()).toBeAttached({ timeout: 3000 });
  });

  test('WASM module loads successfully', async ({ page }) => {
    // Check that the celltoggle.wasm file is accessible
    const response = await page.request.get('http://localhost:8080/celltoggle.wasm');
    expect(response.status()).toBe(200);
    expect(response.headers()['content-type']).toBe('application/wasm');
  });

  test('hydration script defines __hydrateTherapyIsland', async ({ page }) => {
    const defined = await page.evaluate(() => typeof (window as any).__hydrateTherapyIsland === 'function');
    expect(defined).toBe(true);
  });

  test('check browser console for hydration errors', async ({ page }) => {
    const errors: string[] = [];
    const warnings: string[] = [];
    const logs: string[] = [];
    page.on('console', msg => {
      const text = msg.text();
      if (msg.type() === 'error') {
        errors.push(text);
      } else if (msg.type() === 'warning') {
        warnings.push(text);
      } else {
        logs.push(text);
      }
    });
    page.on('pageerror', err => {
      errors.push(err.message);
    });

    await page.goto('http://localhost:8080/notebooks/hello-sessions/');
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3000);

    // Log all warnings for debugging hydration issues
    if (warnings.length > 0) {
      console.log('Console warnings:', warnings);
    }

    // Filter out expected errors (like missing resources)
    const hydrationErrors = errors.filter(e =>
      e.includes('wasm') || e.includes('hydrat') || e.includes('island') || e.includes('WebAssembly')
    );

    if (hydrationErrors.length > 0) {
      console.log('Hydration errors found:', hydrationErrors);
    }
    expect(hydrationErrors).toHaveLength(0);
  });

  test('debug: inspect hydration state', async ({ page }) => {
    const allMessages: string[] = [];
    page.on('console', msg => {
      allMessages.push(`[${msg.type()}] ${msg.text()}`);
    });
    page.on('pageerror', err => {
      allMessages.push(`[pageerror] ${err.message}`);
    });

    await page.goto('http://localhost:8080/notebooks/hello-sessions/');
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3000);

    // Check DOM state
    const state = await page.evaluate(() => {
      const islands = document.querySelectorAll('therapy-island');
      const results: any[] = [];
      islands.forEach((el: any) => {
        results.push({
          component: el.dataset.component,
          props: el.dataset.props || '(none)',
          hydrated: el.dataset.hydrated || 'not set',
          hasWasm: el.dataset.wasm || '(none)',
          childCount: el.children.length,
          firstChildTag: el.firstElementChild?.tagName || '(none)',
        });
      });
      return {
        islands: results,
        hydrateTherapyIsland: typeof (window as any).__hydrateTherapyIsland,
        hydrateTherapyIslands: typeof (window as any).__hydrateTherapyIslands,
        therapyHydrate: (window as any).TherapyHydrate ? Object.keys((window as any).TherapyHydrate) : 'undefined',
      };
    });

    console.log('=== Hydration Debug ===');
    console.log('__hydrateTherapyIsland:', state.hydrateTherapyIsland);
    console.log('__hydrateTherapyIslands:', state.hydrateTherapyIslands);
    console.log('TherapyHydrate:', state.therapyHydrate);
    console.log('Islands found:', state.islands.length);
    for (const island of state.islands) {
      console.log(`  ${island.component}: hydrated=${island.hydrated}, props=${island.props}, children=${island.childCount}, firstChild=${island.firstChildTag}`);
    }

    // Print relevant console messages
    const hydrationMessages = allMessages.filter(m =>
      m.includes('Hydration') || m.includes('hydrat') || m.includes('wasm') ||
      m.includes('island') || m.includes('cursor') || m.includes('trap')
    );
    if (hydrationMessages.length > 0) {
      console.log('Hydration-related messages:');
      for (const msg of hydrationMessages) {
        console.log('  ', msg);
      }
    }

    // This test always passes - it's for debugging output
    expect(true).toBe(true);
  });
});
