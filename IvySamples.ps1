param(
    [switch]$BuildFrontend
)

if ($BuildFrontend) {
    Push-Location "D:\Repos\_Ivy\Ivy-Framework\src\frontend"
    npm run build
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "npm run build failed" }
    Pop-Location
}

dotnet run --project "D:\Repos\_Ivy\Ivy-Framework\src\Ivy.Samples\Ivy.Samples.csproj" -- --browse @args
