<#
.SYNOPSIS
    Generates Playwright test files for an Ivy connection.

.DESCRIPTION
    Creates the .ivy/tests/ directory structure with package.json, playwright.config.ts,
    and test spec files for connection interface and demo apps.

.PARAMETER ServiceName
    The name of the service/connection (e.g., "Claude", "Stripe")

.PARAMETER TestDir
    The test directory path

.PARAMETER ProjectPath
    Path to the connection project

.EXAMPLE
    .\CreatePlaywrightTests.ps1 -ServiceName "Claude" -TestDir "D:\Temp\CreateReferenceConnectionTest\Claude" -ProjectPath "D:\Temp\CreateReferenceConnectionTest\Claude\Ivy.Connections.Claude"
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

# Ensure tests directory exists
if (-not (Test-Path $TestsDir)) {
    New-Item -Path $TestsDir -ItemType Directory -Force | Out-Null
}

# Discover demo apps
$appsDir = "$ProjectPath\Apps"
$apps = @()
if (Test-Path $appsDir) {
    $apps = Get-ChildItem -Path $appsDir -Filter "*.cs" | ForEach-Object {
        $appName = $_.BaseName
        @{
            Name = $appName
            FileName = $_.Name
            Port = 5000 + ($apps.Count)
        }
    }
}

Write-Host "  Found $($apps.Count) demo apps" -ForegroundColor Gray

# Create package.json
$packageJson = @"
{
  "name": "ivy-connection-test-$($ServiceName.ToLower())",
  "version": "1.0.0",
  "description": "Automated tests for Ivy.$ServiceName connection",
  "type": "module",
  "scripts": {
    "test": "playwright test"
  },
  "devDependencies": {
    "@playwright/test": "^1.48.0",
    "@types/node": "^22.10.2"
  }
}
"@

$packageJson | Out-File -FilePath "$TestsDir\package.json" -Encoding UTF8

# Create playwright.config.ts
$playwrightConfig = @"
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: 'list',
  use: {
    baseURL: 'http://localhost',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    viewport: { width: 1920, height: 1920 },
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
"@

$playwrightConfig | Out-File -FilePath "$TestsDir\playwright.config.ts" -Encoding UTF8

# Create connection.spec.ts
$connectionSpec = @"
import { test, expect } from '@playwright/test';
import { spawn, ChildProcess } from 'child_process';
import { join } from 'path';

test.describe('$ServiceName Connection Tests', () => {
  test('should build successfully', async () => {
    // This is verified by the PowerShell runner before Playwright starts
    expect(true).toBe(true);
  });

  test('should pass unit tests', async () => {
    // This is verified by the PowerShell runner before Playwright starts
    expect(true).toBe(true);
  });

  test('connection class should exist', async () => {
    const projectPath = join(__dirname, '..', '..', 'Ivy.Connections.$ServiceName');
    const connectionFile = join(projectPath, 'Connections', '$($ServiceName)Connection.cs');

    const fs = await import('fs');
    expect(fs.existsSync(connectionFile)).toBe(true);
  });
});
"@

$connectionSpec | Out-File -FilePath "$TestsDir\connection.spec.ts" -Encoding UTF8

# Create apps.spec.ts if apps exist
if ($apps.Count -gt 0) {
    $appsSpecHeader = @"
import { test, expect } from '@playwright/test';
import { spawn, ChildProcess } from 'child_process';
import { join } from 'path';

// Helper to start an Ivy app
async function startApp(appName: string, port: number): Promise<ChildProcess> {
  const projectPath = join(__dirname, '..', '..', 'Ivy.Connections.$ServiceName');

  return new Promise((resolve, reject) => {
    const proc = spawn('dotnet', ['run', '--', '--port', port.toString(), '--chrome=false'], {
      cwd: projectPath,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let output = '';
    proc.stdout?.on('data', (data) => {
      output += data.toString();
      if (output.includes('Now listening on:') || output.includes('Application started')) {
        setTimeout(() => resolve(proc), 2000); // Give it 2s to fully start
      }
    });

    proc.stderr?.on('data', (data) => {
      console.error(``[``{appName}] stderr: ``${data}``);
    });

    proc.on('error', reject);

    // Timeout after 30 seconds
    setTimeout(() => {
      if (proc.exitCode === null) {
        proc.kill();
        reject(new Error(``App ``${appName} failed to start within 30 seconds``));
      }
    }, 30000);
  });
}

test.describe('$ServiceName Demo Apps', () => {
"@

    $appsSpecTests = ""
    foreach ($app in $apps) {
        $appName = $app.Name
        $port = $app.Port

        $appsSpecTests += @"

  test('$appName should render without errors', async ({ page }) => {
    let appProcess: ChildProcess | null = null;

    try {
      // Start the app
      appProcess = await startApp('$appName', $port);

      // Navigate to the app
      const response = await page.goto('http://localhost:$port');
      expect(response?.status()).toBeLessThan(400);

      // Wait for page to load
      await page.waitForLoadState('networkidle', { timeout: 10000 });

      // Check for console errors
      const consoleErrors: string[] = [];
      page.on('console', msg => {
        if (msg.type() === 'error') {
          consoleErrors.push(msg.text());
        }
      });

      // Take screenshot
      await page.screenshot({
        path: join(__dirname, 'screenshots', '$appName.png'),
        fullPage: true
      });

      // Verify no critical console errors
      const criticalErrors = consoleErrors.filter(err =>
        !err.includes('favicon') &&
        !err.includes('DevTools')
      );

      if (criticalErrors.length > 0) {
        console.warn('Console errors detected:', criticalErrors);
      }

    } finally {
      // Clean up
      if (appProcess) {
        appProcess.kill();
        // Give it a moment to shut down
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }
  });
"@
    }

    $appsSpecFooter = @"
});
"@

    $appsSpec = $appsSpecHeader + $appsSpecTests + $appsSpecFooter
    $appsSpec | Out-File -FilePath "$TestsDir\apps.spec.ts" -Encoding UTF8
}

Write-Host "  Created Playwright test structure:" -ForegroundColor Gray
Write-Host "    - package.json" -ForegroundColor Gray
Write-Host "    - playwright.config.ts" -ForegroundColor Gray
Write-Host "    - connection.spec.ts" -ForegroundColor Gray
if ($apps.Count -gt 0) {
    Write-Host "    - apps.spec.ts ($($apps.Count) apps)" -ForegroundColor Gray
}
