# Scripts/DestinyBuildTool.ps1
# Main entry point for Destiny 2 Build Tool

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Test API connection only")]
    [switch]$TestConnection,
    
    [Parameter(HelpMessage="Force re-authentication")]
    [switch]$ForceAuth,

    [Parameter(HelpMessage="Save gear data to files")]
    [switch]$SaveData,

    [Parameter(HelpMessage="Skip interactive menu and run full collection")]
    [switch]$FullCollection,

    [Parameter(HelpMessage="Save individual character files instead of consolidated")]
    [switch]$SeparateFiles
)

# Import required scripts
try {
    . "$PSScriptRoot\get-bungieauth.ps1"
    Write-Host "Loaded Bungie Authentication Script" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load Bungie authentication script: $($_.Exception.Message)"
    exit 1
}

try {
    . "$PSScriptRoot\Get-DestinyInventory.ps1"
    Write-Host "Loaded Destiny Inventory Script" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load Destiny inventory script: $($_.Exception.Message)"
    exit 1
}

try {
    . "$PSScriptRoot\Format-GearData.ps1"
    Write-Host "Loaded Gear Formatting Script" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load gear formatting script: $($_.Exception.Message)"
    exit 1
}

try {
    . "$PSScriptRoot\Invoke-LLMAnalysis.ps1"
    Write-Host "Loaded LLM Analysis Script" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load LLM analysis script: $($_.Exception.Message)"
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
            if ($config) {$config = $null}
        }
        catch {
            Write-Host "Environment configuration error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "Please ensure the following environment variables are set:" -ForegroundColor Yellow
            Write-Host "  - BUNGIE_CLIENT_ID" -ForegroundColor Gray
            Write-Host "  - BUNGIE_CLIENT_SECRET" -ForegroundColor Gray  
            Write-Host "  - BUNGIE_REDIRECT_URI" -ForegroundColor Gray
            Write-Host "  - BUNGIE_API_ID" -ForegroundColor Gray
            return
        }

        # Initialize session properly - let the auth system handle caching
        Write-Host "Initializing authentication session..." -ForegroundColor Yellow
        try {
            Initialize-BungieSession | Out-Null
            Write-Host "Session initialized successfully" -ForegroundColor Green
        } catch {
            Write-Host "Session initialization failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Authentication may be required on first API call" -ForegroundColor Yellow
        }
        
        # Handle command line options
        if ($TestConnection) {
            Test-APIConnection
            return
        }
        
        if ($FullCollection) {
            Get-FullGearCollection
            return
        }
        
        # Force re-authentication if requested
        if ($ForceAuth) {
            Write-Host "Forcing re-authentication..." -ForegroundColor Yellow
            $cacheFile = "../Data/bungie_token.json"
            if (Test-Path $cacheFile) {
                Remove-Item $cacheFile -Force
                Write-Host "Cleared cached token" -ForegroundColor Gray
            }
        }
        
        # Default: Show interactive menu
        Show-InteractiveMenu
        
    }
    catch {
        Write-Error "Application error: $($_.Exception.Message)"
        Write-Host "Stack trace:" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    }
}

# Test API connection function
function Test-APIConnection {
    Write-Host "Testing Destiny 2 API connection..." -ForegroundColor Yellow
    
    try {
        # Test unauthenticated endpoint
        $manifest = Invoke-BungieApiRequest -Uri "https://www.bungie.net/Platform/Destiny2/Manifest/"
        Write-Host "Unauthenticated API access working" -ForegroundColor Green
        Write-Host "   Current game version: $($manifest.version)" -ForegroundColor Gray
        
        # Test authenticated endpoint (session already initialized)
        $user = Invoke-BungieApiRequest -Uri "https://www.bungie.net/Platform/User/GetMembershipsForCurrentUser/" -RequireAuth -UseSessionToken
        Write-Host "Authenticated API access working" -ForegroundColor Green
        Write-Host "   Found $($user.destinyMemberships.Count) Destiny membership(s)" -ForegroundColor Gray
        
        Write-Host "API connection test completed successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "API connection test failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Get full gear collection function
function Get-FullGearCollection {
    Write-Host "Starting full Destiny 2 gear collection..." -ForegroundColor Cyan
    
    try {
        # Test connection first
        Write-Host "1. Testing API connection..." -ForegroundColor Yellow
        Test-APIConnection
        
        # Get character inventories
        Write-Host "`n2. Retrieving character inventories..." -ForegroundColor Yellow
        $inventoryData = Get-AllCharacterInventories
        
        Write-Host "   Found $($inventoryData.Characters.Count) character(s)" -ForegroundColor Green
        foreach ($char in $inventoryData.Characters) {
            Write-Host "   - $($char.Class) (Light Level: $($char.Light))" -ForegroundColor Gray
        }

        
        # Format gear data
        Write-Host "`n3. Formatting gear data for analysis..." -ForegroundColor Yellow
        $gearData = Format-GearForLLM -InventoryData $inventoryData
        
        Write-Host "   Total items processed: $($gearData.Summary.TotalItems)" -ForegroundColor Green
        Write-Host "   - Weapons: $($gearData.Summary.WeaponCount)" -ForegroundColor Gray
        Write-Host "   - Armor: $($gearData.Summary.ArmorCount)" -ForegroundColor Gray
        Write-Host "   - Exotics: $($gearData.Summary.ExoticCount)" -ForegroundColor Gray
        
        # Save data if requested
        if ($SaveData) {
            Write-Host "`n4. Saving gear data..." -ForegroundColor Yellow

            if ($SaveBothFormats) {
                # Save both consolidated and individual files
                $savedPath = Save-GearData -GearData $gearData -IncludeTextFormat
                Write-Host "   Consolidated data saved!" -ForegroundColor Green
                Write-Host "   - JSON format: $savedPath" -ForegroundColor Gray
                Write-Host "   - Text format: $($savedPath -replace '\.json$', '.txt')" -ForegroundColor Gray

                Save-CharacterFiles -FormattedGearData $gearData
                Write-Host "   Individual character files saved!" -ForegroundColor Green
                Write-Host "   - Separate JSON file for each character and vault" -ForegroundColor Gray
            } elseif ($SeparateFiles) {
                # Only separate files
                Save-CharacterFiles -FormattedGearData $gearData
                Write-Host "   Individual character files saved!" -ForegroundColor Green
                Write-Host "   - Separate JSON file for each character and vault" -ForegroundColor Gray
            } else {
                # Only consolidated file
                $savedPath = Save-GearData -GearData $gearData -IncludeTextFormat
                Write-Host "   Consolidated data saved!" -ForegroundColor Green
                Write-Host "   - JSON format: $savedPath" -ForegroundColor Gray
                Write-Host "   - Text format: $($savedPath -replace '\.json$', '.txt')" -ForegroundColor Gray
            }
        }
        
        # Generate sample output
        Write-Host "`n5. Generating analysis-ready text..." -ForegroundColor Yellow
        $textOutput = Convert-GearToText -GearData $gearData
        $lines = ($textOutput -split "`n").Count
        Write-Host "   Generated $lines lines of structured text" -ForegroundColor Green
        
        # Show sample
        Write-Host "`nSample gear data:" -ForegroundColor Cyan
        ($textOutput -split "`n")[0..15] | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
        if ($lines -gt 15) {
            Write-Host "   ... (truncated, $($lines - 15) more lines available)" -ForegroundColor DarkGray
        }
        
        Write-Host "`nGear collection completed successfully!" -ForegroundColor Green
        Write-Host "Your Destiny 2 gear data is ready for LLM analysis and build creation." -ForegroundColor Cyan
        
        if (!$SaveData) {
            Write-Host "`nTip: Run with -SaveData to save your gear data to files for future use." -ForegroundColor Yellow
        }
        
        return $gearData
    }
    catch {
        Write-Host "Failed to complete gear collection: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Interactive menu system
function Show-InteractiveMenu {
    do {
        Show-MainMenu
        $choice = Read-Host "`nEnter your choice"
        
        switch ($choice) {
            '1' { 
                Write-Host "`nTesting API connection..." -ForegroundColor Yellow
                try {
                    Test-APIConnection
                }
                catch {
                    Write-Host "Connection test failed." -ForegroundColor Red
                }
            }
            '2' { 
                Write-Host "`nGetting your Destiny 2 gear collection..." -ForegroundColor Yellow
                try {
                    Get-FullGearCollection
                }
                catch {
                    Write-Host "Gear collection failed." -ForegroundColor Red
                }
            }
            '3' { 
                Write-Host "`nGetting and saving your Destiny 2 gear collection..." -ForegroundColor Yellow
                try {
                    $script:SaveData = $true
                    Get-FullGearCollection
                }
                catch {
                    Write-Host "Gear collection failed." -ForegroundColor Red
                }
                finally {
                    $script:SaveData = $false
                }
            }
            '4' {
                Write-Host "`nGetting and saving individual character files..." -ForegroundColor Yellow
                try {
                    $script:SaveData = $true
                    $script:SeparateFiles = $true
                    Get-FullGearCollection
                }
                catch {
                    Write-Host "Gear collection failed." -ForegroundColor Red
                }
                finally {
                    $script:SaveData = $false
                    $script:SeparateFiles = $false
                }
            }
            '5' {
                Write-Host "`nGetting and saving both consolidated and individual files..." -ForegroundColor Yellow
                try {
                    $script:SaveData = $true
                    $script:SeparateFiles = $true
                    $script:SaveBothFormats = $true
                    Get-FullGearCollection
                }
                catch {
                    Write-Host "Gear collection failed: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "Error details: $($_.ScriptStackTrace)" -ForegroundColor Gray
                }
                finally {
                    $script:SaveData = $false
                    $script:SeparateFiles = $false
                    $script:SaveBothFormats = $false
                }
            }
            '6' {
                Write-Host "`nStarting AI Build Analysis..." -ForegroundColor Yellow
                try {
                    # Select LLM provider
                    $provider = Select-LLMProvider

                    if ($provider) {
                        # Show analysis options menu
                        Show-AnalysisMenu
                    }
                }
                catch {
                    Write-Host "Build analysis failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            '7' {
                Write-Host "`nConfiguring LLM Provider..." -ForegroundColor Yellow
                try {
                    Select-LLMProvider
                }
                catch {
                    Write-Host "Configuration failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            '8' {
                Write-Host "`nForcing re-authentication..." -ForegroundColor Yellow
                $cacheFile = "../Data/bungie_token.json"
                if (Test-Path $cacheFile) {
                    Remove-Item $cacheFile -Force
                    Write-Host "Cleared cached token" -ForegroundColor Green
                } else {
                    Write-Host "No cached token found" -ForegroundColor Gray
                }
            }
            '9' {
                try {
                    . "$PSScriptRoot\Update-DestinyBuildTool.ps1"
                    Write-Host ""
                    Write-Host "==================================" -ForegroundColor Cyan
                    Write-Host "  Update Tool                     " -ForegroundColor Cyan
                    Write-Host "==================================" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "1. Check for Updates"
                    Write-Host "2. Update Now"
                    Write-Host "3. Show Version Info"
                    Write-Host "4. Back to Main Menu"
                    Write-Host ""
                    $updateChoice = Read-Host "Select option"

                    switch ($updateChoice) {
                        '1' {
                            Test-UpdateAvailable -ShowMessage
                        }
                        '2' {
                            Update-Tool
                        }
                        '3' {
                            Show-VersionInfo
                        }
                        '4' {
                            # Return to main menu
                        }
                        default {
                            Write-Host "Invalid choice" -ForegroundColor Red
                        }
                    }
                }
                catch {
                    Write-Host "Update check failed: $($_.Exception.Message)" -ForegroundColor Red
                }
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

# Display analysis type menu
function Show-AnalysisMenu {
    Clear-Host
    Write-Host ""
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host "    Build Analysis Options        " -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. General Build Analysis (All Characters)" -ForegroundColor White
    Write-Host "2. Raid Build Analysis (Specific Character)" -ForegroundColor White
    Write-Host "3. PvE Build Analysis (Specific Character)" -ForegroundColor White
    Write-Host "4. PvP/Crucible Build Analysis (Specific Character)" -ForegroundColor White
    Write-Host "5. Vault Cleanup Recommendations" -ForegroundColor Yellow
    Write-Host "q. Back to Main Menu" -ForegroundColor White
    Write-Host ""

    $choice = Read-Host "Select analysis type"

    switch ($choice) {
        '1' {
            Invoke-BuildAnalysis -AnalysisType "general" -SaveToFile
        }
        '2' {
            $character = Select-Character
            if ($character) {
                Invoke-BuildAnalysis -AnalysisType "raid" -CharacterClass $character -SaveToFile
            }
        }
        '3' {
            $character = Select-Character
            if ($character) {
                Invoke-BuildAnalysis -AnalysisType "pve" -CharacterClass $character -SaveToFile
            }
        }
        '4' {
            $character = Select-Character
            if ($character) {
                Invoke-BuildAnalysis -AnalysisType "pvp" -CharacterClass $character -SaveToFile
            }
        }
        '5' {
            Invoke-BuildAnalysis -AnalysisType "vault-cleanup" -SaveToFile
        }
        'q' {
            return
        }
        default {
            Write-Host "Invalid choice" -ForegroundColor Red
        }
    }
}

# Select character for targeted analysis
function Select-Character {
    Write-Host "`nSelect Character Class:" -ForegroundColor Yellow
    Write-Host "1. Hunter" -ForegroundColor White
    Write-Host "2. Titan" -ForegroundColor White
    Write-Host "3. Warlock" -ForegroundColor White
    Write-Host ""

    $choice = Read-Host "Select class (1-3)"

    switch ($choice) {
        '1' { return "Hunter" }
        '2' { return "Titan" }
        '3' { return "Warlock" }
        default {
            Write-Host "Invalid choice, cancelling..." -ForegroundColor Red
            return $null
        }
    }
}

# Display main menu
function Show-MainMenu {
    Clear-Host

    # Load version info
    try {
        . "$PSScriptRoot\Update-DestinyBuildTool.ps1"
        $version = Get-CurrentVersion
    }
    catch {
        $version = "1.0.0"
    }

    Write-Host ""
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host "    Destiny 2 Build Tool v$version     " -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Test API Connection"
    Write-Host "2. Get Gear Collection (No Save)"
    Write-Host "3. Get Gear Collection + Save Consolidated"
    Write-Host "4. Get Gear Collection + Save Individual Files"
    Write-Host "5. Get Gear Collection + Save Both Formats"
    Write-Host "6. AI Build Analysis"
    Write-Host "7. Configure LLM Provider"
    Write-Host "8. Clear Authentication Cache"
    Write-Host "9. Check for Updates"
    Write-Host "q. Quit"
    Write-Host ""
}

# Handle parameters and start application
if ($SaveData -and !$TestConnection -and !$FullCollection) {
    # If only -SaveData is specified, assume -FullCollection
    $FullCollection = $true
}

# Pass the SeparateFiles flag through to functions that need it
if ($SeparateFiles) {
    $script:UseSeparateFiles = $true
}

# Delete old files
$dataFiles = Get-ChildItem -Path "..\Data"
foreach($file in $dataFiles) {
    Remove-Item $file -Force
}

# Start the application
Start-DestinyBuildTool