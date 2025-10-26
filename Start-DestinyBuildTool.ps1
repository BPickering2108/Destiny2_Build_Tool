# Start-DestinyBuildTool.ps1
# Launcher script for Destiny 2 Build Tool
# This script can be run from anywhere and will automatically set up the correct paths

[CmdletBinding()]
param()

# Get the script root directory
$ToolRoot = $PSScriptRoot

# Change to the tool root directory
Set-Location $ToolRoot

# Ensure required directories exist
$requiredDirs = @("Data", "Manifest", "Scripts")
foreach ($dir in $requiredDirs) {
    $dirPath = Join-Path $ToolRoot $dir
    if (-not (Test-Path $dirPath)) {
        New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
    }
}

# Load .env file if it exists
$envFile = Join-Path $ToolRoot ".env"
if (Test-Path $envFile) {
    Write-Verbose "Loading configuration from .env file..."

    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()

        # Skip comments and empty lines
        if ($line -match '^#' -or [string]::IsNullOrWhiteSpace($line)) {
            return
        }

        # Parse KEY=VALUE
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()

            # Remove quotes if present
            $value = $value -replace '^["'']|["'']$', ''

            # Set environment variable for this session
            [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
            Write-Verbose "  Loaded: $key"
        }
    }
}

# Check if this is the first run
$firstRun = $false
if (-not (Test-Path $envFile)) {
    $firstRun = $true
}

# Display welcome message
Clear-Host
Write-Host ""
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "  Destiny 2 Build Tool Launcher  " -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

if ($firstRun) {
    Write-Host "First-time setup detected!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This tool requires a Bungie.net API key to access your Destiny 2 data." -ForegroundColor White
    Write-Host ""
    Write-Host "Setup steps:" -ForegroundColor Cyan
    Write-Host "1. Go to: https://www.bungie.net/en/Application" -ForegroundColor White
    Write-Host "2. Create a new application" -ForegroundColor White
    Write-Host "3. Set OAuth Redirect URL to: http://localhost:8080/oauth_redirect.html" -ForegroundColor White
    Write-Host "4. Copy your API Key and OAuth Client ID" -ForegroundColor White
    Write-Host ""
    Write-Host "Press Enter when ready to continue..." -ForegroundColor Yellow
    Read-Host
}

# Check for updates (silent check, only shows if update available)
try {
    . "$ToolRoot\Scripts\Update-DestinyBuildTool.ps1"
    $null = Test-UpdateAvailable -ShowMessage
}
catch {
    # Silently continue if update check fails
    Write-Verbose "Update check failed: $($_.Exception.Message)"
}

# Launch the main tool
Write-Host "Starting Destiny 2 Build Tool..." -ForegroundColor Green
Write-Host ""

try {
    # Load the main script
    . "$ToolRoot\Scripts\DestinyBuildTool.ps1"
}
catch {
    Write-Host "Error starting tool: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Press Enter to exit..." -ForegroundColor Yellow
    Read-Host
    exit 1
}
