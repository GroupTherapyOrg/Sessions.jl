# Sessions.jl Browser Tests

Playwright-based integration tests for Sessions.jl notebook functionality.

## Prerequisites

1. Node.js 18+
2. Playwright browsers installed

## Setup

```bash
cd browser-tests
npm install
npx playwright install chromium
```

## Running Tests

### 1. Start Sessions.jl Server

In one terminal:
```bash
cd Sessions.jl
julia --project=. -e 'using Sessions; Sessions.serve()'
```

### 2. Run Tests

In another terminal:
```bash
cd browser-tests
npm test
```

### Debug Mode

Run with browser visible:
```bash
npm run test:headed
```

Step through tests:
```bash
npm run test:debug
```

## Test Coverage

The MVP integration test (`notebook-mvp.spec.ts`) verifies:

1. **Page loads with cells** - Notebook container and cells render
2. **CodeMirror editor initializes** - Code editors are functional
3. **Execute cell and see output** - Cell execution via WebSocket works
4. **Cell with computation shows output** - Results display correctly
5. **Dependent cells re-execute** - Reactive dependency system works
6. **Add new cell** - Cell creation works
7. **Save notebook function exists** - Save functionality is present
8. **Cell state indicators work** - Visual state feedback (idle/running/error)
9. **WebSocket signal bindings present** - Reactive bindings are configured
10. **Dark mode toggle works** - Theme switching works
11. **Cell shows error state on bad code** - Error handling works

## Test Architecture

- Tests use Playwright Test framework
- Single worker to avoid port conflicts
- WebSocket connection verified before each test
- Cell execution uses JavaScript API (`window.executeCell()`) for reliability
- Screenshots captured on failure for debugging

## CI Integration

For CI environments, ensure:
1. Sessions.jl server starts before tests
2. Chromium browser is installed
3. Tests have adequate timeout for Julia startup
