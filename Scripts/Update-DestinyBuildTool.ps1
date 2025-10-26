# Update-DestinyBuildTool.ps1
# Functions for checking and updating the Destiny 2 Build Tool

[CmdletBinding()]
param()

# GitHub repository information
$script:GitHubRepo = "BPickering2108/Destiny2_Build_Tool"
$script:GitHubRawUrl = "https://raw.githubusercontent.com/$script:GitHubRepo/main"
$script:GitHubApiUrl = "https://api.github.com/repos/$script:GitHubRepo"

# Get current version
function Get-CurrentVersion {
    $versionFile = Join-Path $PSScriptRoot "..\version.json"
    if (Test-Path $versionFile) {
        try {
            $versionData = Get-Content $versionFile -Raw | ConvertFrom-Json
            return $versionData.version
        }
        catch {
            Write-Warning "Could not read version file: $($_.Exception.Message)"
            return "0.0.0"
        }
    }
    return "0.0.0"
}

# Get latest version from GitHub
function Get-LatestVersion {
    [CmdletBinding()]
    param(
        [switch]$IncludeChangelog
    )

    try {
        $versionUrl = "$script:GitHubRawUrl/version.json"
        Write-Verbose "Checking for updates at: $versionUrl"

        $response = Invoke-RestMethod -Uri $versionUrl -TimeoutSec 10 -ErrorAction Stop

        if ($IncludeChangelog) {
            return $response
        }
        else {
            return $response.version
        }
    }
    catch {
        Write-Warning "Could not check for updates: $($_.Exception.Message)"
        return $null
    }
}

# Compare versions
function Compare-Version {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CurrentVersion,

        [Parameter(Mandatory=$true)]
        [string]$LatestVersion
    )

    try {
        $current = [version]$CurrentVersion
        $latest = [version]$LatestVersion

        if ($latest -gt $current) {
            return 1  # Update available
        }
        elseif ($latest -eq $current) {
            return 0  # Up to date
        }
        else {
            return -1  # Current is newer (dev version)
        }
    }
    catch {
        Write-Warning "Could not compare versions: $($_.Exception.Message)"
        return $null
    }
}

# Check if git is available
function Test-GitAvailable {
    try {
        $null = git --version 2>&1
        return $true
    }
    catch {
        return $false
    }
}

# Check for updates
function Test-UpdateAvailable {
    [CmdletBinding()]
    param(
        [switch]$ShowMessage
    )

    $currentVersion = Get-CurrentVersion
    $latestVersion = Get-LatestVersion

    if (-not $latestVersion) {
        if ($ShowMessage) {
            Write-Host "Could not check for updates (no internet or GitHub unavailable)" -ForegroundColor Yellow
        }
        return $false
    }

    $comparison = Compare-Version -CurrentVersion $currentVersion -LatestVersion $latestVersion

    if ($comparison -eq 1) {
        if ($ShowMessage) {
            Write-Host ""
            Write-Host "=====================================" -ForegroundColor Cyan
            Write-Host "  UPDATE AVAILABLE" -ForegroundColor Yellow
            Write-Host "=====================================" -ForegroundColor Cyan
            Write-Host "  Current version: $currentVersion" -ForegroundColor White
            Write-Host "  Latest version:  $latestVersion" -ForegroundColor Green
            Write-Host ""
            Write-Host "  Run the 'Update Tool' menu option to update" -ForegroundColor Yellow
            Write-Host "=====================================" -ForegroundColor Cyan
            Write-Host ""
        }
        return $true
    }
    elseif ($comparison -eq 0) {
        if ($ShowMessage) {
            Write-Host "You are running the latest version ($currentVersion)" -ForegroundColor Green
        }
        return $false
    }
    else {
        if ($ShowMessage) {
            Write-Host "You are running a development version ($currentVersion)" -ForegroundColor Cyan
        }
        return $false
    }
}

# Update tool from GitHub
function Update-Tool {
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $toolRoot = Split-Path -Parent $PSScriptRoot

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  Destiny 2 Build Tool Update       " -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host ""

    # Get version info
    $currentVersion = Get-CurrentVersion
    $latestVersionData = Get-LatestVersion -IncludeChangelog

    if (-not $latestVersionData) {
        Write-Host "ERROR: Could not fetch latest version information" -ForegroundColor Red
        Write-Host "Please check your internet connection and try again." -ForegroundColor Yellow
        return $false
    }

    $latestVersion = $latestVersionData.version
    $comparison = Compare-Version -CurrentVersion $currentVersion -LatestVersion $latestVersion

    # Check if update is needed
    if ($comparison -le 0 -and -not $Force) {
        Write-Host "You are already running the latest version ($currentVersion)" -ForegroundColor Green
        Write-Host ""
        return $true
    }

    # Display update info
    Write-Host "Current version: $currentVersion" -ForegroundColor White
    Write-Host "Latest version:  $latestVersion" -ForegroundColor Green
    Write-Host ""

    if ($latestVersionData.changelog) {
        Write-Host "What's new in version $($latestVersion):" -ForegroundColor Cyan
        foreach ($change in $latestVersionData.changelog) {
            Write-Host "  - $change" -ForegroundColor Gray
        }
        Write-Host ""
    }

    # Check if git is available
    $hasGit = Test-GitAvailable

    if ($hasGit) {
        # Check if this is a git repository
        Push-Location $toolRoot
        $isGitRepo = Test-Path (Join-Path $toolRoot ".git")
        Pop-Location

        if ($isGitRepo) {
            # Use git pull
            Write-Host "Detected git repository. Using git to update..." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "IMPORTANT: This will overwrite any local changes!" -ForegroundColor Red
            Write-Host "Your .env file and Data folder will be preserved." -ForegroundColor Green
            Write-Host ""
            Write-Host "Continue with update? (y/n): " -ForegroundColor Yellow -NoNewline
            $confirm = Read-Host

            if ($confirm -ne 'y' -and $confirm -ne 'yes') {
                Write-Host "Update cancelled." -ForegroundColor Yellow
                return $false
            }

            Write-Host ""
            Write-Host "Updating from GitHub..." -ForegroundColor Yellow

            Push-Location $toolRoot
            try {
                # Stash any local changes
                Write-Host "Saving local changes..." -ForegroundColor Gray
                git stash push -m "Auto-stash before update $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>&1 | Out-Null

                # Pull latest changes
                Write-Host "Pulling latest version..." -ForegroundColor Gray
                $gitOutput = git pull origin main 2>&1

                if ($LASTEXITCODE -ne 0) {
                    Write-Host "ERROR: Git pull failed" -ForegroundColor Red
                    Write-Host $gitOutput -ForegroundColor Red
                    Pop-Location
                    return $false
                }

                Write-Host ""
                Write-Host "Update successful!" -ForegroundColor Green
                Write-Host ""
                Write-Host "Changes applied:" -ForegroundColor Cyan
                Write-Host $gitOutput -ForegroundColor Gray
                Write-Host ""
                Write-Host "Please restart the tool to use the new version." -ForegroundColor Yellow

                Pop-Location
                return $true
            }
            catch {
                Write-Host "ERROR: Update failed: $($_.Exception.Message)" -ForegroundColor Red
                Pop-Location
                return $false
            }
        }
    }

    # Fallback: Manual download instructions
    Write-Host "Git is not available or this is not a git repository." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To update manually:" -ForegroundColor Cyan
    Write-Host "1. Go to: https://github.com/$script:GitHubRepo/releases" -ForegroundColor White
    Write-Host "2. Download the latest release (v$latestVersion)" -ForegroundColor White
    Write-Host "3. Extract and replace files (keep your .env and Data folder)" -ForegroundColor White
    Write-Host ""
    Write-Host "OR clone with git for automatic updates:" -ForegroundColor Cyan
    Write-Host "  git clone https://github.com/$script:GitHubRepo.git" -ForegroundColor White
    Write-Host ""

    return $false
}

# Show version information
function Show-VersionInfo {
    $currentVersion = Get-CurrentVersion
    $toolRoot = Split-Path -Parent $PSScriptRoot

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  Version Information                " -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Current version: $currentVersion" -ForegroundColor White
    Write-Host "Installation path: $toolRoot" -ForegroundColor Gray
    Write-Host ""

    # Check if this is a git repository
    Push-Location $toolRoot
    $isGitRepo = Test-Path (Join-Path $toolRoot ".git")
    Pop-Location

    if ($isGitRepo) {
        Write-Host "Installation type: Git repository" -ForegroundColor Green
        Write-Host "Auto-update: Available" -ForegroundColor Green
    }
    else {
        Write-Host "Installation type: Manual download" -ForegroundColor Yellow
        Write-Host "Auto-update: Not available (use git clone for auto-updates)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Checking for updates..." -ForegroundColor Gray
    Test-UpdateAvailable -ShowMessage
}

# Export functions
Export-ModuleMember -Function @(
    'Get-CurrentVersion',
    'Get-LatestVersion',
    'Test-UpdateAvailable',
    'Update-Tool',
    'Show-VersionInfo'
)
