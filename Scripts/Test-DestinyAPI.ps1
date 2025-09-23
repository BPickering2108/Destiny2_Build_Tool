# Test-DestinyAPI.ps1
# Test script to validate the Destiny 2 API integration

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Test connection only")]
    [switch]$ConnectionOnly,
    
    [Parameter(HelpMessage="Get basic inventory")]
    [switch]$BasicInventory,
    
    [Parameter(HelpMessage="Get full formatted collection")]
    [switch]$FullCollection,
    
    [Parameter(HelpMessage="Save data to files")]
    [switch]$SaveData
)

# Import required scripts
Write-Host "Loading Destiny API modules..." -ForegroundColor Yellow

# Determine script location and adjust paths accordingly
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$authScript = Join-Path $scriptPath "Get-BungieAuth.ps1"
$inventoryScript = Join-Path $scriptPath "Get-DestinyInventory.ps1"
$formatScript = Join-Path $scriptPath "Format-GearData.ps1"

try {
    . $authScript
    Write-Host "Loaded authentication functions" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load Get-BungieAuth.ps1: $($_.Exception.Message)"
    exit 1
}

try {
    . $inventoryScript
    Write-Host "Loaded inventory functions" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load Get-DestinyInventory.ps1: $($_.Exception.Message)"
    exit 1
}

try {
    . $formatScript
    Write-Host "Loaded formatting functions" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load Format-GearData.ps1: $($_.Exception.Message)"
    exit 1
}

Write-Host ""

# Main test function
function Start-DestinyAPITest {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "=== DESTINY 2 API TEST SUITE ===" -ForegroundColor Cyan
        Write-Host ""
        
        # Validate environment
        Write-Host "1. Validating environment configuration..." -ForegroundColor Yellow
        
        # Clean up any old cache files in wrong location
        if (Test-Path "Data/bungie_token.json") {
            Remove-Item "Data/bungie_token.json" -Force
            Write-Verbose "Removed old token cache from Scripts/Data/"
        }
        
        try {
            $config = Get-BungieConfig
            Write-Host "   Environment variables configured" -ForegroundColor Green
            $clientIdDisplay = if ($config.ClientId.Length -gt 4) { 
                "$($config.ClientId.Substring(0, 4))..." 
            } else { 
                $config.ClientId
            }
            Write-Host "   Client ID: $clientIdDisplay" -ForegroundColor Gray
            Write-Host "   Redirect URI: $($config.RedirectUri)" -ForegroundColor Gray
        }
        catch {
            Write-Host "   Environment configuration error: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
        
        # Test API connection
        Write-Host "`n2. Testing API connection..." -ForegroundColor Yellow
        Write-Host "   (Fixed URL encoding issue with Bearer tokens)" -ForegroundColor Gray
        try {
            $user = Test-BungieApiConnection
            Write-Host "   API connection successful" -ForegroundColor Green
        }
        catch {
            Write-Host "   API connection failed: $($_.Exception.Message)" -ForegroundColor Red
            if ($_.Exception.Message -like "*500*") {
                Write-Host "   Note: If you're still getting 500 errors, the token may still be getting URL encoded" -ForegroundColor Yellow
                Write-Host "   Check the verbose output for the Authorization header format" -ForegroundColor Yellow
            }
            return
        }
        
        if ($ConnectionOnly) {
            Write-Host "`nConnection test completed successfully!" -ForegroundColor Green
            Write-Host "The URL encoding issue with Bearer tokens has been resolved." -ForegroundColor Cyan
            return
        }
        
        # Test basic inventory access
        Write-Host "`n3. Testing basic inventory access..." -ForegroundColor Yellow
        try {
            $inventoryData = Test-DestinyInventoryAccess
            Write-Host "   Basic inventory access successful" -ForegroundColor Green
            Write-Host "   Found $($inventoryData.Characters.Count) character(s)" -ForegroundColor Gray
        }
        catch {
            Write-Host "   Basic inventory access failed: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
        
        if ($BasicInventory) {
            Write-Host "`nBasic inventory test completed successfully!" -ForegroundColor Green
            return
        }
        
        # Test full gear formatting
        Write-Host "`n4. Testing gear data formatting..." -ForegroundColor Yellow
        try {
            $gearData = Get-FormattedGearCollection -SaveToFile:$SaveData -IncludeTextFormat:$SaveData
            Write-Host "   Gear formatting successful" -ForegroundColor Green
            Write-Host "   Total items processed: $($gearData.Summary.TotalItems)" -ForegroundColor Gray
            Write-Host "   Weapons: $($gearData.Summary.WeaponCount)" -ForegroundColor Gray
            Write-Host "   Armor: $($gearData.Summary.ArmorCount)" -ForegroundColor Gray
            Write-Host "   Exotics: $($gearData.Summary.ExoticCount)" -ForegroundColor Gray
            
            if ($SaveData) {
                Write-Host "   Data saved to files" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "   Gear formatting failed: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
        
        # Generate sample LLM text
        Write-Host "`n5. Generating LLM-ready text sample..." -ForegroundColor Yellow
        try {
            $textSample = Convert-GearToText -GearData $gearData
            $lines = ($textSample -split "`n").Count
            Write-Host "   Text generation successful" -ForegroundColor Green
            Write-Host "   Generated $lines lines of text for LLM consumption" -ForegroundColor Gray
            
            # Show first few lines as sample
            Write-Host "`n   Sample output:" -ForegroundColor Gray
            ($textSample -split "`n")[0..10] | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
            if ($lines -gt 10) {
                Write-Host "   ... (truncated, $($lines - 10) more lines)" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Host "   Text generation failed: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
        
        Write-Host "`nALL TESTS COMPLETED SUCCESSFULLY!" -ForegroundColor Green
        Write-Host "Your Destiny 2 API integration is working correctly." -ForegroundColor Cyan
        
        if (!$SaveData) {
            Write-Host "`nTip: Run with -SaveData to save your gear data to files" -ForegroundColor Yellow
        }
        
        Write-Host "Next steps:" -ForegroundColor Yellow
        Write-Host "- Your gear data is now ready for LLM analysis" -ForegroundColor Gray
        Write-Host "- You can feed the text output to Claude or other LLMs" -ForegroundColor Gray
        Write-Host "- The JSON data can be used for programmatic build analysis" -ForegroundColor Gray
        
    }
    catch {
        Write-Host "`nTest suite failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace:" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    }
}

# Show usage if no parameters
if (!$ConnectionOnly -and !$BasicInventory -and !$FullCollection -and !$PSBoundParameters.Count) {
    Write-Host ""
    Write-Host "=== Destiny 2 API Test Script ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage examples:" -ForegroundColor White
    Write-Host "  .\Test-DestinyAPI.ps1 -ConnectionOnly      # Test API connection only" -ForegroundColor Gray
    Write-Host "  .\Test-DestinyAPI.ps1 -BasicInventory      # Test basic inventory access" -ForegroundColor Gray
    Write-Host "  .\Test-DestinyAPI.ps1 -FullCollection      # Full gear collection test" -ForegroundColor Gray
    Write-Host "  .\Test-DestinyAPI.ps1 -FullCollection -SaveData  # Full test + save data" -ForegroundColor Gray
    Write-Host "  .\Test-DestinyAPI.ps1 -Verbose             # Use built-in verbose output" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Running full collection test by default..." -ForegroundColor Yellow
    Write-Host ""
    $FullCollection = $true
}

# Run the test
Start-DestinyAPITest