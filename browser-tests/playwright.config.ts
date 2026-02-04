import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for Sessions.jl integration tests.
 *
 * These tests verify the full notebook workflow in a browser:
 * - Load notebook
 * - Edit cells
 * - Execute cells
 * - Verify reactive updates
 * - Save notebook
 */
export default defineConfig({
  testDir: './tests',
  fullyParallel: false,  // Run tests sequentially (shared server state)
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,  // Single worker to avoid port conflicts
  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report' }]
  ],

  use: {
    baseURL: 'http://localhost:8080',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'on-first-retry',
  },

  // Timeout settings
  timeout: 30000,
  expect: {
    timeout: 10000
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  // Don't automatically start webServer - we manage Sessions.jl server separately
  // webServer: {
  //   command: 'julia --project=.. -e "using Sessions; Sessions.serve()"',
  //   url: 'http://localhost:8080',
  //   reuseExistingServer: !process.env.CI,
  //   timeout: 120000,  // Julia startup can be slow
  // },
});
