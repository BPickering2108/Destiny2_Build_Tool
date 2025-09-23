# Get-DestinyInventory.ps1
# Functions to retrieve and process Destiny 2 character and inventory data

[CmdletBinding()]
param()

# Dot source the authentication script
. ".\Get-BungieAuth.ps1"

# Global manifest cache
$script:ManifestCache = @{}

# Get user's Destiny memberships
function Get-DestinyMemberships {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "Getting Destiny 2 memberships..." -ForegroundColor Yellow
        
        Write-Host "DEBUG: About to call API for memberships..."
        Write-Verbose "DEBUG: Using API key: $((Get-BungieConfig).ApiKey)"        

        $user = Invoke-BungieApiRequest -Uri "https://www.bungie.net/Platform/User/GetMembershipsForCurrentUser/" -RequireAuth
        
        if ($user.destinyMemberships.Count -eq 0) {
            throw "No Destiny 2 characters found on this account"
        }
        
        Write-Host "Found $($user.destinyMemberships.Count) Destiny membership(s):" -ForegroundColor Green
        for ($i = 0; $i -lt $user.destinyMemberships.Count; $i++) {
            $membership = $user.destinyMemberships[$i]
            $platform = switch ($membership.membershipType) {
                1 { "Xbox" }
                2 { "PlayStation" }
                3 { "Steam" }
                4 { "Blizzard" }
                5 { "Stadia" }
                6 { "Epic Games" }
                default { "Unknown ($($membership.membershipType))" }
            }
            Write-Host "  $($i + 1). $($membership.displayName) - $platform" -ForegroundColor Gray
        }
        
        return $user.destinyMemberships
    }
    catch {
        Write-Error "Failed to get Destiny memberships: $($_.Exception.Message)"
        throw
    }
}

# Get character and inventory data for a membership
function Get-DestinyProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$MembershipType,
        
        [Parameter(Mandatory=$true)]
        [string]$MembershipId,
        
        [string[]]$Components = @("100", "102", "201", "205", "300", "302", "304", "305", "307", "308", "310")
    )
    
    try {
        Write-Host "Getting profile data..." -ForegroundColor Yellow
        
        # Component codes:
        # 100 = Profiles, 102 = Characters, 201 = CharacterInventories, 205 = CharacterEquipment
        # 300 = ItemInstances, 302 = ItemPerks, 304 = ItemStats, 305 = ItemSockets
        # 307 = ItemTalentGrids, 308 = ItemCommonData, 310 = ItemPlugStates
        
        $componentString = $Components -join ","
        $uri = "https://www.bungie.net/Platform/Destiny2/$MembershipType/Profile/$MembershipId/?components=$componentString"
        
        $d2profile = Invoke-BungieApiRequest -Uri $uri -RequireAuth
        
        Write-Host "Profile data retrieved successfully" -ForegroundColor Green
        
        return $d2profile
    }
    catch {
        Write-Error "Failed to get profile data: $($_.Exception.Message)"
        throw
    }
}

# Download and cache manifest data
function Get-DestinyManifest {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "Getting Destiny 2 manifest..." -ForegroundColor Yellow
        
        $manifest = Invoke-BungieApiRequest -Uri "https://www.bungie.net/Platform/Destiny2/Manifest/"
        
        $manifestUrl = "https://www.bungie.net$($manifest.jsonWorldContentPaths.en)"
        Write-Host "Manifest URL: $manifestUrl" -ForegroundColor Gray
        
        # Check if we have cached manifest - FIXED PATHS
        $manifestFile = "../Data/manifest.json"
        $versionFile = "../Data/manifest_version.txt"
        
        $downloadManifest = $true
        if ((Test-Path $manifestFile) -and (Test-Path $versionFile)) {
            $cachedVersion = Get-Content $versionFile -ErrorAction SilentlyContinue
            if ($cachedVersion -eq $manifest.version) {
                Write-Host "Using cached manifest (version: $($manifest.version))" -ForegroundColor Green
                $downloadManifest = $false
            }
        }
        
        if ($downloadManifest) {
            Write-Host "Downloading manifest data (this may take a moment)..." -ForegroundColor Yellow
            
            # Ensure Data directory exists - FIXED PATH
            if (!(Test-Path "../Data")) {
                New-Item -ItemType Directory -Path "../Data" -Force | Out-Null
            }
            
            # Download manifest
            try {
                Invoke-WebRequest -Uri $manifestUrl -OutFile $manifestFile -UseBasicParsing
                $manifest.version | Out-File -FilePath $versionFile -Encoding UTF8
                Write-Host "Manifest downloaded and cached" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to download full manifest: $($_.Exception.Message)"
                Write-Host "Continuing without manifest cache..." -ForegroundColor Yellow
                return $null
            }
        }
        
        # Load manifest into memory (just the definitions we need)
        if (Test-Path $manifestFile) {
            try {
                Write-Host "Loading manifest definitions..." -ForegroundColor Yellow
                $manifestData = Get-Content $manifestFile | ConvertFrom-Json
                
                # Cache key definition tables
                $script:ManifestCache = @{
                    InventoryItems = $manifestData.DestinyInventoryItemDefinition
                    Stats = $manifestData.DestinyStatDefinition
                    Sockets = $manifestData.DestinySocketTypeDefinition
                    Perks = $manifestData.DestinyInventoryItemDefinition # Perks are items too
                    Version = $manifest.version
                }
                
                Write-Host "Manifest loaded into cache" -ForegroundColor Green
                return $script:ManifestCache
            }
            catch {
                Write-Warning "Failed to load manifest: $($_.Exception.Message)"
                return $null
            }
        }
        
        return $null
    }
    catch {
        Write-Warning "Failed to get manifest: $($_.Exception.Message)"
        return $null
    }
}

# Get item definition from manifest
function Get-ItemDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ItemHash
    )
    
    if ($script:ManifestCache.InventoryItems -and $script:ManifestCache.InventoryItems.$ItemHash) {
        return $script:ManifestCache.InventoryItems.$ItemHash
    }
    
    # If not in cache, try direct API call (slower but works)
    try {
        $uri = "https://www.bungie.net/Platform/Destiny2/Manifest/DestinyInventoryItemDefinition/$ItemHash/"
        $response = Invoke-BungieApiRequest -Uri $uri
        return $response
    }
    catch {
        Write-Warning "Could not get definition for item hash: $ItemHash"
        return $null
    }
}

# Parse character data - WORK WITH ACTUAL DATA RETURNED
function Get-CharacterSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$ProfileData
    )
    
    Write-Verbose "=== CHARACTER SUMMARY DEBUG ==="
    Write-Verbose "Profile data type: $($ProfileData.GetType().FullName)"
    
    # Get all properties
    $properties = $ProfileData | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
    Write-Verbose "Profile data properties: $($properties -join ', ')"
    
    $characters = @()
    
    # The characters metadata isn't being returned, but we can extract character IDs from the equipment data
    if ($ProfileData.characterEquipment -and $ProfileData.characterEquipment.data) {
        Write-Verbose "Using characterEquipment data to find characters"
        
        $characterIds = $ProfileData.characterEquipment.data | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        Write-Verbose "Character IDs found in equipment data: $($characterIds -join ', ')"
        
        foreach ($characterId in $characterIds) {
            Write-Verbose "Processing character from equipment data: $characterId"
            
            # We don't have the character metadata, so create basic character info
            $characters += @{
                CharacterId = $characterId
                Class = "Unknown" # Can't determine without character component
                Race = "Unknown"
                Gender = "Unknown"
                Light = "Unknown"
                Level = "Unknown"
                EmblemPath = ""
                LastPlayed = [DateTime]::Now # Placeholder
            }
        }
    }
    
    # Also check character inventories for more character IDs
    if ($ProfileData.characterInventories -and $ProfileData.characterInventories.data) {
        Write-Verbose "Also checking characterInventories for character IDs"
        
        $inventoryCharacterIds = $ProfileData.characterInventories.data | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        
        foreach ($characterId in $inventoryCharacterIds) {
            # Only add if not already found
            if (-not ($characters | Where-Object { $_.CharacterId -eq $characterId })) {
                Write-Verbose "Adding character from inventory data: $characterId"
                
                $characters += @{
                    CharacterId = $characterId
                    Class = "Unknown"
                    Race = "Unknown" 
                    Gender = "Unknown"
                    Light = "Unknown"
                    Level = "Unknown"
                    EmblemPath = ""
                    LastPlayed = [DateTime]::Now
                }
            }
        }
    }
    
    Write-Verbose "Total characters found: $($characters.Count)"
    Write-Verbose "=== END CHARACTER SUMMARY DEBUG ==="
    
    return $characters
}

# Get all inventory for all characters
function Get-AllCharacterInventories {
    [CmdletBinding()]
    param()
    
    try {
        # Get memberships
        $memberships = Get-DestinyMemberships
        
        # For simplicity, use the first membership found
        # In a full implementation, you might want to let user choose
        $membership = $memberships[0]
        
        Write-Host "`nUsing membership: $($membership.displayName)" -ForegroundColor Cyan
        
        # Get profile data
        $d2profile = Get-DestinyProfile -MembershipType $membership.membershipType -MembershipId $membership.membershipId
        
        # Get manifest (optional but helpful for item names)
        $manifest = Get-DestinyManifest
        
        # Parse characters
        $characters = Get-CharacterSummary -ProfileData $d2profile
        
        Write-Host "`nCharacters found:" -ForegroundColor Green
        foreach ($char in $characters) {
            Write-Host "  $($char.Class) - Light Level $($char.Light) - Last played: $($char.LastPlayed.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
        }
        
        # Return structured data
        return @{
            Membership = $membership
            Characters = $characters
            ProfileData = $d2profile
            Manifest = $manifest
        }
    }
    catch {
        Write-Error "Failed to get character inventories: $($_.Exception.Message)"
        throw
    }
}

# Quick test function
function Test-DestinyInventoryAccess {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "Testing Destiny inventory access..." -ForegroundColor Cyan
        
        $data = Get-AllCharacterInventories
        
        Write-Host "`nSuccessfully retrieved character data!" -ForegroundColor Green
        Write-Host "Found $($data.Characters.Count) character(s)" -ForegroundColor Gray
        
        return $data
    }
    catch {
        Write-Host "Failed to retrieve inventory data: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}