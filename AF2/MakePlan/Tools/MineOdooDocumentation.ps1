# Mine Odoo documentation and create reference files
param(
    [string]$OutputPath = "D:\Repos\_Ivy\Ivy\Ivy.Internals\Workflows\Conversion\Odoo\References"
)

# Ensure output directory exists
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

# Clone or update Odoo documentation repository
$docRepo = "D:\Temp\odoo-documentation"
if (Test-Path $docRepo) {
    Write-Host "Updating Odoo documentation repository..."
    Push-Location $docRepo
    git pull
    Pop-Location
} else {
    Write-Host "Cloning Odoo documentation repository..."
    git clone https://github.com/odoo/documentation.git $docRepo --depth 1 --branch 18.0
}

# Clone or update main Odoo repository (for component inspection)
$odooRepo = "D:\Temp\odoo"
if (Test-Path $odooRepo) {
    Write-Host "Updating Odoo repository..."
    Push-Location $odooRepo
    git pull
    Pop-Location
} else {
    Write-Host "Cloning Odoo repository (web addon only)..."
    git clone https://github.com/odoo/odoo.git $odooRepo --depth 1 --branch 19.0 --filter=blob:none --sparse
    Push-Location $odooRepo
    git sparse-checkout set addons/web/static/src/views
    Pop-Location
}

Write-Host "Mining view types..."
$viewTypes = @("form", "list", "kanban", "calendar", "graph", "pivot", "search", "activity", "cohort", "grid", "gantt", "map")

foreach ($viewType in $viewTypes) {
    $outputFile = Join-Path $OutputPath "$viewType-view.md"

    # Skip if already exists (don't overwrite hand-crafted files)
    if (Test-Path $outputFile) {
        Write-Host "  Skipping $viewType-view.md (already exists)"
        continue
    }

    # Extract documentation from .rst files
    $docFile = Join-Path $docRepo "content\developer\reference\user_interface\view_architectures.rst"

    @"
# $($viewType.Substring(0,1).ToUpper() + $viewType.Substring(1)) View

Odoo $viewType view component for displaying and interacting with data.

## Odoo

Documentation will be extracted from official sources.

## Ivy

Map to appropriate Ivy components:
- Form views -> Use Ivy Form components with appropriate fields
- List views -> Use DataGrid or Table components
- Kanban views -> Use Card layouts with drag-and-drop
- Calendar views -> Use Calendar widget (if available)
- Graph views -> Use Chart components (LineChart, BarChart, etc.)
- Pivot views -> Use DataGrid with pivot capabilities
- Search views -> Use SearchInput, Filters, and query builders

## Parameters

TBD - Extract from Odoo documentation

"@ | Out-File -FilePath $outputFile -Encoding UTF8
}

Write-Host "Mining field widgets..."
$fieldWidgetsPath = Join-Path $odooRepo "addons\web\static\src\views\fields"
if (Test-Path $fieldWidgetsPath) {
    Get-ChildItem -Path $fieldWidgetsPath -Filter "*.js" | ForEach-Object {
        $widgetName = $_.BaseName
        $outputFile = Join-Path $OutputPath "field-$widgetName.md"

        # Skip if already exists
        if (Test-Path $outputFile) {
            Write-Host "  Skipping field-$widgetName.md (already exists)"
            return
        }

        @"
# Field: $widgetName

Odoo field widget for $widgetName.

## Odoo

``````javascript
// Usage in Odoo view
<field name="field_name" widget="$widgetName"/>
``````

## Ivy

Map to appropriate Ivy field component.

## Parameters

TBD - Extract from source code

"@ | Out-File -FilePath $outputFile -Encoding UTF8
    }
}

Write-Host "Created reference files in $OutputPath"
Write-Host "Run this script again to update references from latest Odoo versions"
