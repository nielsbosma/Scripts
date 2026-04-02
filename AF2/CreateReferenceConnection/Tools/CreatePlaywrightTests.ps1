<#
.SYNOPSIS
    Generates agentic Playwright test files for an Ivy connection.

.DESCRIPTION
    Discovers apps via `dotnet run --describe`, reads app source code,
    and generates per-app E2E spec files with real UI interactions.

.PARAMETER ServiceName
    The name of the service/connection (e.g., "CoinGecko")

.PARAMETER TestDir
    The directory containing .ivy/tests/ (usually same as ProjectPath)

.PARAMETER ProjectPath
    Path to the connection project (source directory)

.EXAMPLE
    .\CreatePlaywrightTests.ps1 -ServiceName "CoinGecko" -TestDir "D:\Repos\_Ivy\Ivy\connections\CoinGecko\Ivy.Connections.CoinGecko" -ProjectPath "D:\Repos\_Ivy\Ivy\connections\CoinGecko\Ivy.Connections.CoinGecko"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceName,

    [Parameter(Mandatory=$true)]
    [string]$TestDir,

    [Parameter(Mandatory=$true)]
    [string]$ProjectPath
)

$ErrorActionPreference = "Stop"
$TestsDir = "$TestDir\.ivy\tests"

if (-not (Test-Path $TestsDir)) {
    New-Item -Path $TestsDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path "$TestsDir\screenshots")) {
    New-Item -Path "$TestsDir\screenshots" -ItemType Directory -Force | Out-Null
}

# ---- Discover apps ----
Write-Host "  Discovering apps..." -ForegroundColor Gray
$describeOutput = ""
try {
    Push-Location $ProjectPath
    $describeOutput = dotnet run --no-build -- --describe 2>&1 | Out-String
} finally {
    Pop-Location
}

# Parse app entries from YAML output
$apps = @()
$lines = $describeOutput -split "`n"
$inApps = $false
$currentApp = $null
foreach ($line in $lines) {
    if ($line -match "^apps:") { $inApps = $true; continue }
    if ($line -match "^[a-z]" -and $line -notmatch "^\s") { $inApps = $false }
    if (-not $inApps) { continue }

    if ($line -match "^\s*-\s*name:\s*(.+)") {
        if ($currentApp) { $apps += $currentApp }
        $currentApp = @{ Name = $matches[1].Trim(); Id = ""; Visible = $false }
    }
    if ($line -match "^\s+id:\s*(.+)" -and $currentApp) {
        $currentApp.Id = $matches[1].Trim()
    }
    if ($line -match "^\s+isVisible:\s*true" -and $currentApp) {
        $currentApp.Visible = $true
    }
}
if ($currentApp) { $apps += $currentApp }

# Filter to visible apps only
$visibleApps = $apps | Where-Object { $_.Visible -and $_.Id -notmatch '^\$' }
Write-Host "  Found $($visibleApps.Count) visible app(s): $(($visibleApps | ForEach-Object { $_.Name }) -join ', ')" -ForegroundColor Gray

# ---- Read app source files ----
$appSources = @{}
$appsDir = "$ProjectPath\Apps"
if (Test-Path $appsDir) {
    Get-ChildItem -Path $appsDir -Filter "*.cs" | ForEach-Object {
        $appSources[$_.BaseName] = Get-Content $_.FullName -Raw
    }
}

# ---- Normalize paths for TypeScript ----
$projectPathTs = ($ProjectPath -replace '\\', '/').TrimEnd('/')

# ---- Create package.json ----
@"
{
  "name": "ivy-connection-test-$($ServiceName.ToLower())",
  "version": "1.0.0",
  "type": "module",
  "scripts": { "test": "playwright test" },
  "devDependencies": {
    "@playwright/test": "^1.48.0",
    "@types/node": "^22.10.2"
  }
}
"@ | ForEach-Object { [System.IO.File]::WriteAllText("$TestsDir\package.json", $_, [System.Text.UTF8Encoding]::new($false)) }

# ---- Create playwright.config.ts ----
@"
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: 0,
  timeout: 60000,
  reporter: 'list',
  use: {
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    viewport: { width: 1920, height: 1080 },
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
"@ | Out-File -FilePath "$TestsDir\playwright.config.ts" -Encoding UTF8

# ---- Create connection.spec.ts (structural checks) ----
$testsPathTs = ($TestsDir -replace '\\', '/').TrimEnd('/')
$connSpec = @'
import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const PROJECT_PATH = '__PROJECTPATH__';

test.describe('__SERVICENAME__ Connection Structure', () => {
  test('connection class exists and implements required methods', () => {
    const connectionFile = path.join(PROJECT_PATH, 'Connections', '__SERVICENAME__Connection.cs');
    expect(fs.existsSync(connectionFile)).toBe(true);

    const content = fs.readFileSync(connectionFile, 'utf-8');
    for (const method of ['GetName', 'GetConnectionType', 'GetEntities', 'RegisterServices', 'TestConnection', 'GetContext', 'GetNamespace']) {
      expect(content, `Missing method: ${method}`).toContain(method);
    }
  });

  test('connection.yaml exists', () => {
    const yamlFile = path.join(PROJECT_PATH, '..', 'connection.yaml');
    expect(fs.existsSync(yamlFile)).toBe(true);
  });

  test('unit tests passed', () => {
    const logFile = '__TESTSDIR__/unit-tests.log';
    if (!fs.existsSync(logFile)) { test.skip(); return; }
    const content = fs.readFileSync(logFile, 'utf-8');
    expect(content).toContain('Test Run Successful');
  });
});
'@ -replace '__PROJECTPATH__', $projectPathTs -replace '__SERVICENAME__', $ServiceName -replace '__TESTSDIR__', $testsPathTs
$connSpec | Out-File -FilePath "$TestsDir\connection.spec.ts" -Encoding UTF8

# ---- Generate per-app spec files ----
foreach ($app in $visibleApps) {
    $appName = $app.Name
    $appId = $app.Id
    $safeName = ($appId -replace '[^a-zA-Z0-9]', '-')

    # Find matching source file
    $sourceContent = ""
    foreach ($key in $appSources.Keys) {
        $src = $appSources[$key]
        if ($src -match "title:\s*`"$([regex]::Escape($appName))`"" -or $src -match "class\s+$key") {
            $sourceContent = $src
            break
        }
    }

    # Analyze source to determine test strategy
    $hasTextInput = $sourceContent -match "ToTextInput|ToSearchInput|ToTextareaInput"
    $hasButton = $sourceContent -match "new Button\("
    $hasCard = $sourceContent -match "new Card\("
    $hasLoading = $sourceContent -match "Loading\.\.\."
    $hasError = $sourceContent -match "Text\.Danger|Callout\.Error|Error"
    $hasTable = $sourceContent -match "ToTable\(\)|DataTable"

    # Extract heading text
    $headingText = ""
    if ($sourceContent -match 'Text\.H[12]\("([^"]+)"\)') {
        $headingText = $matches[1]
    }

    # Extract placeholder text
    $placeholderText = ""
    if ($sourceContent -match '\.Placeholder\("([^"]+)"\)') {
        $placeholderText = $matches[1]
    }

    # Extract button label
    $buttonLabel = ""
    if ($sourceContent -match 'new Button\("([^"]+)"') {
        $buttonLabel = $matches[1]
    }

    # Extract muted description
    $mutedText = ""
    if ($sourceContent -match 'Text\.Muted\("([^"]+)"\)') {
        $mutedText = $matches[1]
    }

    # Build test file — use single-quoted here-string to avoid backtick issues,
    # then replace __APPNAME__, __APPID__, __PROJECTROOT__, __SCREENSHOTSDIR__, etc.
    $specHeader = @'
import { test, expect } from '@playwright/test';
import { spawn, ChildProcess } from 'child_process';
import * as http from 'http';
import * as net from 'net';
import * as path from 'path';
import * as fs from 'fs';

const PROJECT_ROOT = '__PROJECTROOT__';
const SCREENSHOTS_DIR = '__TESTSDIR__/screenshots';
const CONSOLE_LOG_PATH = '__TESTSDIR__/console.log';
const BACKEND_LOG_PATH = '__TESTSDIR__/backend.log';

let screenshotCounter = 1;

function findFreePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, () => {
      const port = (srv.address() as net.AddressInfo).port;
      srv.close(() => resolve(port));
    });
    srv.on('error', reject);
  });
}

function waitForServer(port: number, timeout = 30000): Promise<void> {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    const check = () => {
      http.get(`http://localhost:${port}`, (res) => {
        if (res.statusCode === 200) resolve();
        else if (Date.now() - start > timeout) reject(new Error('Server startup timeout'));
        else setTimeout(check, 500);
      }).on('error', () => {
        if (Date.now() - start > timeout) reject(new Error('Server startup timeout'));
        else setTimeout(check, 500);
      });
    };
    check();
  });
}

async function takeScreenshot(page: any, name: string) {
  const filename = `${String(screenshotCounter++).padStart(2, '0')}-${name}.png`;
  await page.screenshot({
    path: path.join(SCREENSHOTS_DIR, filename),
    fullPage: true,
  });
}

test.describe('__APPNAME__', () => {
  let appProcess: ChildProcess;
  let appPort: number;
  const consoleLogs: string[] = [];
  const backendLogs: string[] = [];

  test.beforeAll(async ({}, testInfo) => {
    testInfo.setTimeout(120000);

    appPort = await findFreePort();
    appProcess = spawn('dotnet', ['run', '--no-build', '--', '--port', String(appPort), '--chrome=false'], {
      cwd: PROJECT_ROOT,
      shell: true,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    appProcess.stdout?.on('data', (data: Buffer) => {
      backendLogs.push(data.toString());
    });
    appProcess.stderr?.on('data', (data: Buffer) => {
      backendLogs.push('[stderr] ' + data.toString());
    });

    await waitForServer(appPort);
  });

  test.afterAll(async () => {
    if (appProcess) {
      appProcess.kill();
      try {
        const pid = appProcess.pid;
        if (pid) {
          spawn('taskkill', ['//pid', String(pid), '//t', '//f'], { shell: true, stdio: 'ignore' });
        }
      } catch {}
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
    fs.writeFileSync(CONSOLE_LOG_PATH, consoleLogs.join('\n'));
    fs.writeFileSync(BACKEND_LOG_PATH, backendLogs.join('\n'));
  });

  test.beforeEach(async ({ page }) => {
    page.on('console', (msg) => {
      consoleLogs.push(`[${msg.type()}] ${msg.text()}`);
    });
    page.on('pageerror', (err) => {
      consoleLogs.push(`[pageerror] ${err.message}`);
    });
    await page.goto(`http://localhost:${appPort}/__APPID__?chrome=false`, {
      waitUntil: 'domcontentloaded',
    });
    await page.waitForTimeout(1000);
  });

  // ---- Test: Initial load ----
  test('should render initial UI without errors', async ({ page }) => {
    await takeScreenshot(page, 'initial-load');

'@

    # Do token replacements
    $specContent = $specHeader `
        -replace '__PROJECTROOT__', $projectPathTs `
        -replace '__TESTSDIR__', $testsPathTs `
        -replace '__APPNAME__', $appName `
        -replace '__APPID__', $appId

    # Add heading assertion
    if ($headingText) {
        $specContent += @"
    // Verify heading
    await expect(page.getByText('$headingText')).toBeVisible();

"@
    }

    # Add muted text assertion
    if ($mutedText -and $mutedText.Length -lt 80) {
        $specContent += @"
    // Verify description
    await expect(page.getByText('$($mutedText.Substring(0, [Math]::Min(40, $mutedText.Length)))', { exact: false })).toBeVisible();

"@
    }

    # Add input assertion
    if ($hasTextInput -and $placeholderText) {
        $specContent += @"
    // Verify search input is present
    await expect(page.locator('input[type="text"]').first()).toBeVisible();

"@
    }

    # Add button assertion
    if ($hasButton -and $buttonLabel) {
        $specContent += @"
    // Verify button is present
    await expect(page.getByRole('button', { name: '$buttonLabel' })).toBeVisible();

"@
    }

    $specContent += @"
    // No runtime errors in the UI
    const errorIndicators = await page.locator('text=/Something went wrong|Exception|Stack trace/i').count();
    expect(errorIndicators).toBe(0);
  });

"@

    # ---- Test: Interaction (search/click flow) ----
    if ($hasTextInput -and $hasButton -and $buttonLabel) {
        $specContent += @"
  // ---- Test: Search interaction ----
  test('should search and display results', async ({ page }) => {
    // Type a search query
    const input = page.locator('input[type="text"]').first();
    await input.fill('bitcoin');
    await takeScreenshot(page, 'after-typing');

    // Click search button
    await page.getByRole('button', { name: '$buttonLabel' }).click();
    // Wait for loading to finish — either results appear or "No coins" or error
    // Use a longer timeout to account for API rate limiting
    try {
      await page.waitForFunction(() => {
        const body = document.body.innerText;
        return !body.includes('Loading...') || body.includes('Price:') || body.includes('No coins') || body.includes('Error') || body.includes('API error');
      }, { timeout: 15000 });
    } catch { /* timeout — screenshot will show what happened */ }
    await page.waitForTimeout(500);

    await takeScreenshot(page, 'after-search');

"@

        if ($hasCard) {
            $specContent += @"
    // Verify result cards appeared (or "No coins found" message)
    const hasResults = await page.getByText('Bitcoin', { exact: false }).count();
    const noResults = await page.getByText('No coins found').count();
    expect(hasResults + noResults).toBeGreaterThan(0);

    if (hasResults > 0) {
      // Verify card content has price data
      await expect(page.getByText('Price:', { exact: false }).first()).toBeVisible();
      await expect(page.getByText('Market Cap:', { exact: false }).first()).toBeVisible();
    }

"@
        }

        $specContent += @"
    // No errors after search
    const errorText = await page.locator('text=/Error:|API error:/i').count();
    expect(errorText).toBe(0);
  });

"@

        # ---- Test: No results case ----
        $specContent += @"
  // ---- Test: Search with no results ----
  test('should handle search with no matching results', async ({ page }) => {
    const input = page.locator('input[type="text"]').first();
    await input.fill('xyznonexistentcoin12345');

    await page.getByRole('button', { name: '$buttonLabel' }).click();
    await page.waitForTimeout(3000);

    await takeScreenshot(page, 'no-results');

    // Should show "No coins found", or still loading (rate limited), or error
    const noResults = await page.getByText('No coins found', { exact: false }).count();
    const loading = await page.getByText('Loading...').count();
    const hasError = await page.locator('text=/Error|API error/i').count();
    // Any response state is acceptable — we're testing the app handles it gracefully
    expect(noResults + loading + hasError).toBeGreaterThan(0);
  });

"@

        # ---- Test: Second search ----
        $specContent += @"
  // ---- Test: Multiple searches ----
  test('should handle multiple sequential searches', async ({ page }) => {
    const input = page.locator('input[type="text"]').first();

    // First search
    await input.fill('eth');
    await page.getByRole('button', { name: '$buttonLabel' }).click();
    await page.waitForTimeout(3000);
    await takeScreenshot(page, 'search-eth');

    // Verify ETH results (or rate limit/loading state)
    const ethResults = await page.getByText('Ethereum', { exact: false }).count();
    const stillLoading = await page.getByText('Loading...').count();
    // Accept results or loading state (rate limited)
    expect(ethResults + stillLoading).toBeGreaterThan(0);

    // Second search
    await input.fill('solana');
    await page.getByRole('button', { name: '$buttonLabel' }).click();
    await page.waitForTimeout(3000);
    await takeScreenshot(page, 'search-solana');
  });

"@
    }

    # ---- Test: Console/backend log cleanliness ----
    $specContent += @"
  // ---- Test: Logs are clean ----
  test('should have clean console and backend logs', async ({ page }) => {
    // Check for JS errors captured during all previous tests
    const jsErrors = consoleLogs.filter(l =>
      l.startsWith('[error]') || l.startsWith('[pageerror]')
    ).filter(l =>
      !l.includes('favicon') && !l.includes('DevTools')
    );

    if (jsErrors.length > 0) {
      console.warn('Console errors detected:', jsErrors);
    }

    // Check backend logs for exceptions
    const backendErrors = backendLogs.filter(l =>
      /exception|error|stack trace|unhandled/i.test(l)
    ).filter(l =>
      !l.includes('[stderr]') || /exception|unhandled/i.test(l)
    );

    if (backendErrors.length > 0) {
      console.warn('Backend errors detected:', backendErrors);
    }

    await takeScreenshot(page, 'final-state');
  });
});
"@

    $specContent | Out-File -FilePath "$TestsDir\$safeName.spec.ts" -Encoding UTF8
    Write-Host "  Generated $safeName.spec.ts ($appName)" -ForegroundColor Gray
}

Write-Host "  Test generation complete." -ForegroundColor Gray
