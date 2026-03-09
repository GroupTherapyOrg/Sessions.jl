import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './test/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'list',
  timeout: 30000,
  use: {
    baseURL: (process.env.BASE_URL || 'http://localhost:3457').replace(/\/?$/, '/'),
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  ...(!process.env.BASE_URL ? {
    webServer: {
      // Create Sessions.jl symlink so /Sessions.jl/* resolves (matches GitHub Pages path)
      command: 'cd docs/dist && ln -sf . Sessions.jl 2>/dev/null; cd ../.. && npx serve docs/dist -l 3457',
      port: 3457,
      reuseExistingServer: !process.env.CI,
    },
  } : {}),
});
