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
        
        Write-Verbose "DEBUG: Using API key: $((Get-BungieConfig).ApiKey)"        

        $user = Invoke-BungieApiRequest -Uri "https://www.bungie.net/Platform/User/GetMembershipsForCurrentUser/" -RequireAuth -UseSessionToken
        
        if ($user.destinyMemberships.Count -eq 0) {
            throw "No Destiny 2 characters found on this account"
        }
        
<#         Write-Host "Found $($user.destinyMemberships.Count) Destiny membership(s):" -ForegroundColor Green
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
        } #>
        
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
        
        $d2profile = Invoke-BungieApiRequest -Uri $uri -RequireAuth -UseSessionToken
        
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
        
        # Check if we have cached manifest - MANIFEST FOLDER
        $manifestDir = "../Manifest"
        $manifestFile = "$manifestDir/manifest.json"
        $versionFile = "$manifestDir/manifest_version.txt"
        
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

            # Ensure Manifest directory exists
            if (!(Test-Path $manifestDir)) {
                New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
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
        
        # Load manifest into memory with progress tracking
        if (Test-Path $manifestFile) {
            try {
                Write-Host "Loading manifest definitions (this will take 15-30 seconds)..." -ForegroundColor Yellow

                # Use streaming read for better performance
                $manifestData = Get-Content $manifestFile -Raw | ConvertFrom-Json

                # Cache key definition tables
                $script:ManifestCache = @{
                    InventoryItems = $manifestData.DestinyInventoryItemDefinition
                    Stats = $manifestData.DestinyStatDefinition
                    Sockets = $manifestData.DestinySocketTypeDefinition
                    Perks = $manifestData.DestinyInventoryItemDefinition # Perks are items too
                    Version = $manifest.version
                }

                Write-Host "Manifest loaded successfully" -ForegroundColor Green
                return $script:ManifestCache
            }
            catch {
                Write-Warning "Failed to load manifest: $($_.Exception.Message)"
                Write-Host "Falling back to API lookups (slower)..." -ForegroundColor Yellow

                $script:ManifestCache = @{
                    InventoryItems = @{}
                    Stats = @{}
                    Sockets = @{}
                    Perks = @{}
                    Version = $manifest.version
                    UseLiveAPI = $true
                }
                return $script:ManifestCache
            }
        }

        return $null
    }
    catch {
        Write-Warning "Failed to get manifest: $($_.Exception.Message)"
        return $null
    }
}

# Helper functions to convert character metadata
function Get-CharacterClassName {
    [CmdletBinding()]
    param([int]$ClassType)

    switch ($ClassType) {
        0 { return "Titan" }
        1 { return "Hunter" }
        2 { return "Warlock" }
        default { return "Unknown" }
    }
}

function Get-CharacterRaceName {
    [CmdletBinding()]
    param([int]$RaceType)

    switch ($RaceType) {
        0 { return "Human" }
        1 { return "Awoken" }
        2 { return "Exo" }
        default { return "Unknown" }
    }
}

function Get-CharacterGenderName {
    [CmdletBinding()]
    param([int]$GenderType)

    switch ($GenderType) {
        0 { return "Male" }
        1 { return "Female" }
        2 { return "Other" }
        default { return "Unknown" }
    }
}

# Get item definition from manifest
function Get-ItemDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ItemHash
    )

    # Check cache first
    if ($script:ManifestCache.InventoryItems -and $script:ManifestCache.InventoryItems.$ItemHash) {
        return $script:ManifestCache.InventoryItems.$ItemHash
    }

    # If not in cache, try direct API call and cache the result
    try {
        $uri = "https://www.bungie.net/Platform/Destiny2/Manifest/DestinyInventoryItemDefinition/$ItemHash/"
        $response = Invoke-BungieApiRequest -Uri $uri

        # Cache the result for future use
        if ($response -and $script:ManifestCache.InventoryItems) {
            $script:ManifestCache.InventoryItems[$ItemHash] = $response
        }

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
# Get all inventory for all characters
function Get-AllCharacterInventories {
    [CmdletBinding()]
    param()
    
    try {
        # Get memberships
        $memberships = Get-DestinyMemberships
        # Let user choose membership if multiple exist
        $membership = $null
        if ($memberships.Count -eq 1) {
            $membership = $memberships[0]
            Write-Host "Using only available membership: $($membership.displayName)" -ForegroundColor Cyan
        } else {
            Write-Host "`nMultiple Destiny memberships found:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $memberships.Count; $i++) {
                $m = $memberships[$i]
                $platform = switch ($m.membershipType) {
                    1 { "Xbox" } 2 { "PlayStation" } 3 { "Steam" } 
                    4 { "Blizzard" } 5 { "Stadia" } 6 { "Epic Games" }
                    default { "Platform $($m.membershipType)" }
                }
                Write-Host "  $($i + 1). $($m.displayName) - $platform" -ForegroundColor Gray
            }
            
            do {
                $choice = Read-Host "`nSelect membership (1-$($memberships.Count))"
                $choiceNum = [int]$choice - 1
            } while ($choiceNum -lt 0 -or $choiceNum -ge $memberships.Count)
            
            $membership = $memberships[$choiceNum]
            Write-Host "Selected: $($membership.displayName)" -ForegroundColor Cyan
        }
        
        Write-Host "`nUsing membership: $($membership.displayName)" -ForegroundColor Cyan
        
        # 1. Get character metadata first
        Write-Host "Getting character details..." -ForegroundColor Yellow
        $charactersResponse = Get-CharacterDetails -MembershipType $membership.membershipType -MembershipId $membership.membershipId

                
        # 2. Get each character's equipment and inventory separately
        $characterData = @()
        
        if ($charactersResponse.characters -and $charactersResponse.characters.data) {
            $characterIds = $charactersResponse.characters.data | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
            foreach ($characterId in $characterIds) {
                try {
                    
                    $charEquipAndInv = Get-CharacterEquipmentAndInventory -MembershipType $membership.membershipType -MembershipId $membership.membershipId -CharacterId $characterId
                    
                    # Store character data with proper metadata
                    $charMetadata = $charactersResponse.characters.data.$characterId
                    $characterData += @{
                        CharacterId = $characterId
                        Class = Get-CharacterClassName -ClassType $charMetadata.classType
                        Race = Get-CharacterRaceName -RaceType $charMetadata.raceType
                        Gender = Get-CharacterGenderName -GenderType $charMetadata.genderType
                        Light = $charMetadata.light
                        Level = $charMetadata.levelProgression.level
                        EmblemPath = $charMetadata.emblemPath
                        LastPlayed = if ($charMetadata.dateLastPlayed) {
                            try {
                                [DateTime]::ParseExact($charMetadata.dateLastPlayed, "MM/dd/yyyy HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                            } catch {
                                try {
                                    [DateTime]::Parse($charMetadata.dateLastPlayed, [System.Globalization.CultureInfo]::InvariantCulture)
                                } catch {
                                    Write-Warning "Could not parse dateLastPlayed '$($charMetadata.dateLastPlayed)' for character, using current time"
                                    [DateTime]::Now
                                }
                            }
                        } else { [DateTime]::Now }
                        Character = $charMetadata
                        Equipment = $charEquipAndInv.equipment
                        Inventory = $charEquipAndInv.inventory
                        ItemInstances = $charEquipAndInv.itemComponents.instances.data
                        ItemStats = $charEquipAndInv.itemComponents.stats.data
                        ItemSockets = $charEquipAndInv.itemComponents.sockets.data
                        ItemPerks = $charEquipAndInv.itemComponents.perks.data
                    }
                }
                catch {
                    Write-Warning "Failed to get data for character $characterId : $_"
                }
            }
        }
        
        # 3. Get vault data separately
        Write-Host "Getting vault data..." -ForegroundColor Yellow
        # Add 302=ItemPerks, 305=ItemSockets, 310=ItemPlugStates for perks data
        $vaultUri = "https://www.bungie.net/Platform/Destiny2/$($membership.membershipType)/Profile/$($membership.membershipId)/?components=102,300,302,304,305,310"
        $vaultData = Invoke-BungieApiRequest -Uri $vaultUri -RequireAuth -UseSessionToken



        
        # INITIALIZE CONSOLIDATED DATA STRUCTURE FIRST
        $consolidatedProfileData = @{
            characterEquipment = @{ data = @{} }
            characterInventories = @{ data = @{} }
            itemInstances = @{ data = @{} }
            itemStats = @{ data = @{} }
            itemSockets = @{ data = @{} }
            itemPerks = @{ data = @{} }
            profileInventory = $vaultData.profileInventory
        }


        foreach ($char in $characterData) {
            $charId = $char.CharacterId
            
            try {
                # Equipment
                if (($null -ne $char.Equipment) -and ($null -ne $char.Equipment.data)) {
                    $consolidatedProfileData.characterEquipment.data[$charId] = $char.Equipment.data
                }

                # Inventory
                if (($null -ne $char.Inventory) -and ($null -ne $char.Inventory.data)) {
                    $consolidatedProfileData.characterInventories.data[$charId] = $char.Inventory.data
                }

                # ItemInstances using Get-Member approach
                if ($null -ne $char.ItemInstances) {
                    $instanceKeys = @()
                    try {
                        $instanceKeys = $char.ItemInstances | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                        foreach ($key in $instanceKeys) {
                            $consolidatedProfileData.itemInstances.data[$key] = $char.ItemInstances.$key
                        }
                    } catch {
                        # Silently skip on error
                    }
                }

                # ItemStats using Get-Member approach
                if ($null -ne $char.ItemStats) {
                    try {
                        $statKeys = $char.ItemStats | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                        foreach ($key in $statKeys) {
                            $consolidatedProfileData.itemStats.data[$key] = $char.ItemStats.$key
                        }
                    } catch {
                        # Silently skip on error
                    }
                }

                # ItemSockets using Get-Member approach
                if ($null -ne $char.ItemSockets) {
                    try {
                        $socketKeys = $char.ItemSockets | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                        foreach ($key in $socketKeys) {
                            $consolidatedProfileData.itemSockets.data[$key] = $char.ItemSockets.$key
                        }
                    } catch {
                        # Silently skip on error
                    }
                }

                # ItemPerks using Get-Member approach
                if ($null -ne $char.ItemPerks) {
                    try {
                        $perkKeys = $char.ItemPerks | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                        foreach ($key in $perkKeys) {
                            $consolidatedProfileData.itemPerks.data[$key] = $char.ItemPerks.$key
                        }
                    } catch {
                        # Silently skip on error
                    }
                }
            } catch {
                Write-Warning "Failed to process character ${charId}: $($_.Exception.Message)"
            }
        }

        # Add vault item instances, stats, sockets, and perks using Get-Member approach
        if ($null -ne $vaultData.itemComponents) {
            if ($null -ne $vaultData.itemComponents.instances.data) {
                try {
                    $vaultInstanceKeys = $vaultData.itemComponents.instances.data | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                    foreach ($key in $vaultInstanceKeys) {
                        $consolidatedProfileData.itemInstances.data[$key] = $vaultData.itemComponents.instances.data.$key
                    }
                } catch {
                    Write-Warning "Error processing vault instances: $($_.Exception.Message)"
                }
            }
            if ($null -ne $vaultData.itemComponents.stats.data) {
                try {
                    $vaultStatKeys = $vaultData.itemComponents.stats.data | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                    foreach ($key in $vaultStatKeys) {
                        $consolidatedProfileData.itemStats.data[$key] = $vaultData.itemComponents.stats.data.$key
                    }
                } catch {
                    Write-Warning "Error processing vault stats: $($_.Exception.Message)"
                }
            }
            if ($null -ne $vaultData.itemComponents.sockets.data) {
                try {
                    $vaultSocketKeys = $vaultData.itemComponents.sockets.data | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                    foreach ($key in $vaultSocketKeys) {
                        $consolidatedProfileData.itemSockets.data[$key] = $vaultData.itemComponents.sockets.data.$key
                    }
                } catch {
                    Write-Warning "Error processing vault sockets: $($_.Exception.Message)"
                }
            }
            if ($null -ne $vaultData.itemComponents.perks.data) {
                try {
                    $vaultPerkKeys = $vaultData.itemComponents.perks.data | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                    foreach ($key in $vaultPerkKeys) {
                        $consolidatedProfileData.itemPerks.data[$key] = $vaultData.itemComponents.perks.data.$key
                    }
                } catch {
                    Write-Warning "Error processing vault perks: $($_.Exception.Message)"
                }
            }
        }

        # Get manifest
        $manifest = Get-DestinyManifest

        # Return in the expected format
        return @{
            Membership = $membership
            Characters = $characterData
            ProfileData = $consolidatedProfileData
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

function Get-CharacterDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$MembershipType,
        
        [Parameter(Mandatory=$true)]
        [string]$MembershipId
    )
    
    $uri = "https://www.bungie.net/Platform/Destiny2/$MembershipType/Profile/$MembershipId/?components=200"
    $response = Invoke-BungieApiRequest -Uri $uri -RequireAuth -UseSessionToken
    return $response
}

function Get-CharacterEquipmentAndInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$MembershipType,
        
        [Parameter(Mandatory=$true)]
        [string]$MembershipId,
        
        [Parameter(Mandatory=$true)]
        [string]$CharacterId
    )
    
    # Components: 201=CharacterInventories, 205=CharacterEquipment,
    #             300=ItemInstances, 302=ItemPerks, 304=ItemStats, 305=ItemSockets, 310=ItemPlugStates
    $uri = "https://www.bungie.net/Platform/Destiny2/$MembershipType/Profile/$MembershipId/Character/$CharacterId/?components=201,205,300,302,304,305,310"
    $response = Invoke-BungieApiRequest -Uri $uri -RequireAuth -UseSessionToken


    return $response
}