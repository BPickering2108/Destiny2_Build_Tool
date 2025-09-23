# Scripts/DestinyBuildTool.ps1
# Main entry point for Destiny 2 Build Tool

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Test API connection only")]
    [switch]$TestConnection,
    
    [Parameter(HelpMessage="Force re-authentication")]
    [switch]$ForceAuth
)

# Dot-source Bungie authentication script
try {
    . "$PSScriptRoot\get-bungieauth.ps1"
    Write-Host "Loaded Bungie Authentication Script" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load Bungie authentication script: $($_.Exception.Message)"
    exit 1
}
# Dot-source API test connection script
try {
    . "$PSScriptRoot\test-destinyapi.ps1"
    Write-Host "Loaded Bungie Authentication Script" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load Bungie authentication script: $($_.Exception.Message)"
    exit 1
}

# Main function
function Start-DestinyBuildTool {
    [CmdletBinding()]
    param()
    
    try {
        # Display banner
        Write-Host ""
        Write-Host "==================================" -ForegroundColor Cyan
        Write-Host "    Destiny 2 Build Tool v1.0     " -ForegroundColor Cyan  
        Write-Host "==================================" -ForegroundColor Cyan
        Write-Host ""
        
        # Validate environment
        Write-Host "Validating environment..." -ForegroundColor Yellow
        try {
            $config = Get-BungieConfig
            Write-Host "Environment variables configured" -ForegroundColor Green
        }
        catch {
            Write-Host "Environment configuration error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "Please ensure the following environment variables are set:" -ForegroundColor Yellow
            Write-Host "  - BUNGIE_CLIENT_ID" -ForegroundColor Gray
            Write-Host "  - BUNGIE_CLIENT_SECRET" -ForegroundColor Gray  
            Write-Host "  - BUNGIE_REDIRECT_URI" -ForegroundColor Gray
            return
        }
        
        # Test connection
        if ($TestConnection) {
            Start-DestinyAPITest
            return
        }
        
        # Force re-authentication if requested
        if ($ForceAuth) {
            Write-Host "Forcing re-authentication..." -ForegroundColor Yellow
            $cacheFile = "Data/Cache/bungie_token.json"
            if (Test-Path $cacheFile) {
                Remove-Item $cacheFile -Force
                Write-Host "Cleared cached token" -ForegroundColor Gray
            }
        }
        
        # Test API connection
        Write-Host "Testing API connection..." -ForegroundColor Yellow
        Test-BungieApiConnection
        
        # Main menu loop
        do {
            Show-MainMenu
            $choice = Read-Host "`nEnter your choice"
            
            switch ($choice) {
                '1' { 
                    Write-Host "`nGetting your Destiny 2 inventory..." -ForegroundColor Yellow
                    Get-PlayerInventory
                }
                '2' { 
                    Write-Host "`nBuild creation coming soon!" -ForegroundColor Yellow
                    Write-Host "This feature will analyze your gear and create optimal builds." -ForegroundColor Gray
                }
                '3' { 
                    Write-Host "`nTesting API connection..." -ForegroundColor Yellow
                    Test-BungieApiConnection
                }
                '4' { 
                    Write-Host "`nForcing re-authentication..." -ForegroundColor Yellow
                    $cacheFile = "Data/Cache/bungie_token.json"
                    if (Test-Path $cacheFile) { Remove-Item $cacheFile -Force }
                    Test-BungieApiConnection
                }
                'q' { 
                    Write-Host "`nGoodbye! Eyes up, Guardian!" -ForegroundColor Cyan
                    return
                }
                default { 
                    Write-Host "Invalid choice. Please try again." -ForegroundColor Red
                }
            }
            
            if ($choice -ne 'q') {
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            
        } while ($choice -ne 'q')
    }
    catch {
        Write-Error "Application error: $($_.Exception.Message)"
        Write-Host "Stack trace:" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    }
}

# Display main menu
function Show-MainMenu {
    Clear-Host
    Write-Host ""
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host "    Destiny 2 Build Tool v1.0     " -ForegroundColor Cyan  
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. View Inventory & Vault" -ForegroundColor White
    Write-Host "2. Create Build (Coming Soon)" -ForegroundColor White
    Write-Host "3. Test API Connection" -ForegroundColor White
    Write-Host "4. Re-authenticate" -ForegroundColor White
    Write-Host "q. Quit" -ForegroundColor White
    Write-Host ""
}

# Placeholder for inventory function (we'll build this next)
function Get-PlayerInventory {
    Write-Host "Getting your Destiny 2 characters and inventory..." -ForegroundColor Green
    
    try {
        # Get user memberships first
        $user = Invoke-BungieApiRequest -Uri "https://www.bungie.net/Platform/User/GetMembershipsForCurrentUser/" -RequireAuth
        
        if ($user.destinyMemberships.Count -eq 0) {
            Write-Host "No Destiny 2 characters found on this account" -ForegroundColor Red
            return
        }
        
        # Show available memberships
        Write-Host "`nFound Destiny 2 account(s):" -ForegroundColor Yellow
        for ($i = 0; $i -lt $user.destinyMemberships.Count; $i++) {
            $membership = $user.destinyMemberships[$i]
            Write-Host "  $($i + 1). $($membership.displayName) ($($membership.membershipType))" -ForegroundColor Gray
        }
        
        Write-Host "`nSuccessfully connected to Destiny 2 API!" -ForegroundColor Green
        Write-Host "Next: We'll implement character and inventory data retrieval" -ForegroundColor Cyan
    }
    catch {
        Write-Host "❌ Failed to get inventory: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Start the application
if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Name) {
    Start-DestinyBuildTool
}