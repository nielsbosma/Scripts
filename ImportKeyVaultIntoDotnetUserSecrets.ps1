<#
.SYNOPSIS
  Import secrets from Azure Key Vault into .NET user secrets.

.PARAMETER VaultName
  Name of the Azure Key Vault.

.PARAMETER ProjectPath
  Path to the .csproj (or a directory containing it).

.PARAMETER PrefixToTrim
  Optional: trim this prefix from each Key Vault secret name before saving.

.PARAMETER WhatIf
  Show what would be imported without writing to user secrets.
#>
param(
  [Parameter(Mandatory = $true)][string]$VaultName,
  [Parameter(Mandatory = $true)][string]$ProjectPath,
  [string]$PrefixToTrim = "",
  [switch]$WhatIf
)

function Ensure-AzCli {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI ('az') not found. Install from https://learn.microsoft.com/cli/azure/install-azure-cli"
  }
}

function Ensure-DotNet {
  if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw ".NET SDK ('dotnet') not found. Install from https://dotnet.microsoft.com/en-us/download"
  }
}

# function Ensure-LoggedIn {
#   $account = az account show 2>$null | ConvertFrom-Json
#   if (-not $account) {
#     Write-Host "Logging in to Azure…" -ForegroundColor Yellow
#     az login | Out-Null
#   }
# }

function Ensure-UserSecretsInit {
  # Safe to call repeatedly; if already initialized, the CLI will say so and exit 0.
  dotnet user-secrets init --project $ProjectPath | Out-Null
}

function Get-KvSecretsMeta {
  $raw = az keyvault secret list --vault-name $VaultName --output json
  if (-not $raw) { return @() }
  $items = $raw | ConvertFrom-Json
  # Normalize fields across CLI versions
  $nowUnix = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
  $items | ForEach-Object {
    # Old CLI: attributes.enabled, attributes.expires
    # Newer:    properties.enabled, properties.expiresOn (RFC3339)
    $enabled = $_.attributes.enabled
    if ($null -eq $enabled) { $enabled = $_.properties.enabled }
    $expires = $_.attributes.expires
    if ($null -eq $expires) {
      $expiresOn = $_.properties.expiresOn
      if ($expiresOn) {
        try { $expires = [int]([DateTimeOffset]::Parse($expiresOn).ToUnixTimeSeconds()) } catch { $expires = $null }
      }
    }
    [pscustomobject]@{
      Name    = $_.name
      Enabled = $true -eq $enabled
      Expired = ($expires -ne $null -and $expires -le $nowUnix)
    }
  }
}

function Get-KvSecretValue {
  param([string]$Name)
  az keyvault secret show --vault-name $VaultName --name $Name --query "value" -o tsv
}

function Map-Name {
  param([string]$Name)
  if ($PrefixToTrim -and $Name.StartsWith($PrefixToTrim)) {
    $Name = $Name.Substring($PrefixToTrim.Length)
  }
  # Replace -- with : for .NET configuration format
  return $Name.Replace("--", ":")
}

# ---- main ----
Ensure-AzCli
Ensure-DotNet
# Ensure-LoggedIn
Ensure-UserSecretsInit

$meta = Get-KvSecretsMeta
if (-not $meta -or $meta.Count -eq 0) {
  Write-Warning "No secrets found (or you lack permission to list)."
  exit 1
}

$toProcess = $meta | Where-Object { $_.Enabled -and -not $_.Expired }
if ($toProcess.Count -eq 0) {
  Write-Warning "No enabled, non-expired secrets to import."
  exit 0
}

Write-Host "Found $($toProcess.Count) secrets to import from vault '$VaultName'." -ForegroundColor Cyan

$errors = 0
foreach ($s in $toProcess) {
  $key = Map-Name -Name $s.Name
  try {
    $val = Get-KvSecretValue -Name $s.Name
    if (-not $val) {
      Write-Warning "Cannot read value for '$($s.Name)' (missing 'get' permission?). Skipping."
      continue
    }
    if ($WhatIf) {
      Write-Host "[WhatIf] dotnet user-secrets set --project `"$ProjectPath`" `"$key`" <value>" -ForegroundColor Yellow
    } else {
      # Use --project to target the specified project
      # Pass value as parameter, properly escaped for multiline values
      & dotnet user-secrets set --project $ProjectPath "$key" "$val" | Out-Null
      Write-Host "Set: $key" -ForegroundColor Green
    }
  } catch {
    $errors++
    Write-Warning "Failed to import '$($s.Name)': $($_.Exception.Message)"
  }
}

if ($WhatIf) {
  Write-Host "Dry run complete." -ForegroundColor Cyan
} elseif ($errors -gt 0) {
  Write-Warning "Completed with $errors errors."
} else {
  Write-Host "All secrets imported successfully." -ForegroundColor Cyan
}
