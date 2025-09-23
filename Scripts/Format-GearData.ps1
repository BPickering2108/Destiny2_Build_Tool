# Format-GearData.ps1
# Functions to format Destiny 2 gear data for LLM consumption

[CmdletBinding()]
param()

# Dot source dependencies
. ".\Get-BungieAuth.ps1"
. ".\Get-DestinyInventory.ps1"

# Format equipped gear for a character
function Format-EquippedGear {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CharacterId,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$ProfileData,
        
        [hashtable]$Manifest = $null
    )
    
    $equippedGear = @()
    
    if ($ProfileData.characterEquipment -and $ProfileData.characterEquipment.data.$CharacterId) {
        $equipment = $ProfileData.characterEquipment.data.$CharacterId.items
        
        foreach ($item in $equipment) {
            $gearItem = Format-GearItem -Item $item -ProfileData $ProfileData -Manifest $Manifest -Location "Equipped on Character"
            if ($gearItem) {
                $equippedGear += $gearItem
            }
        }
    }
    
    return $equippedGear
}

# Format inventory items for a character
function Format-CharacterInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CharacterId,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$ProfileData,
        
        [hashtable]$Manifest = $null
    )
    
    $inventoryGear = @()
    
    if ($ProfileData.characterInventories -and $ProfileData.characterInventories.data.$CharacterId) {
        $inventory = $ProfileData.characterInventories.data.$CharacterId.items
        
        foreach ($item in $inventory) {
            $gearItem = Format-GearItem -Item $item -ProfileData $ProfileData -Manifest $Manifest -Location "Character Inventory"
            if ($gearItem -and $gearItem.Category -in @("Weapon", "Armor")) {
                $inventoryGear += $gearItem
            }
        }
    }
    
    return $inventoryGear
}

# Format vault items  
function Format-VaultInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$ProfileData,
        
        [hashtable]$Manifest = $null
    )
    
    $vaultGear = @()
    
    if ($ProfileData.profileInventory -and $ProfileData.profileInventory.data.items) {
        $vaultItems = $ProfileData.profileInventory.data.items
        
        foreach ($item in $vaultItems) {
            $gearItem = Format-GearItem -Item $item -ProfileData $ProfileData -Manifest $Manifest -Location "Vault"
            if ($gearItem -and $gearItem.Category -in @("Weapon", "Armor")) {
                $vaultGear += $gearItem
            }
        }
    }
    
    return $vaultGear
}

# Format individual gear item
function Format-GearItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Item,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$ProfileData,
        
        [hashtable]$Manifest = $null,
        
        [string]$Location = "Unknown"
    )
    
    try {
        # Get item definition
        $itemDef = $null
        if ($Manifest -and $Manifest.InventoryItems) {
            $itemDef = $Manifest.InventoryItems.([string]$Item.itemHash)
        }
        
        # If no manifest, try API call
        if (!$itemDef) {
            $itemDef = Get-ItemDefinition -ItemHash $Item.itemHash
        }
        
        if (!$itemDef) {
            Write-Verbose "Could not get definition for item hash: $($Item.itemHash)"
            return $null
        }
        
        # Determine item category
        $category = Get-ItemCategory -ItemDef $itemDef
        
        # Skip non-gear items
        if ($category -notin @("Weapon", "Armor")) {
            return $null
        }
        
        # Get item instance data
        $instanceData = $null
        if ($ProfileData.itemInstances -and $ProfileData.itemInstances.data.($Item.itemInstanceId)) {
            $instanceData = $ProfileData.itemInstances.data.($Item.itemInstanceId)
        }
        
        # Get socket data (perks/mods)
        $sockets = Get-ItemSockets -Item $Item -ProfileData $ProfileData -Manifest $Manifest
        
        # Get stats
        $stats = Get-ItemStats -Item $Item -ProfileData $ProfileData -ItemDef $itemDef
        
        # Build formatted item
        $gearItem = @{
            Name = $itemDef.displayProperties.name
            Hash = $Item.itemHash
            InstanceId = $Item.itemInstanceId
            Category = $category
            Type = $itemDef.itemTypeDisplayName
            Tier = Get-ItemTier -ItemDef $itemDef
            Element = Get-ItemElement -InstanceData $instanceData -ItemDef $itemDef
            Power = if ($instanceData) { $instanceData.primaryStat.value } else { $null }
            Location = $Location
            Sockets = $sockets
            Stats = $stats
            Masterwork = Get-ItemMasterwork -Item $Item -ProfileData $ProfileData -ItemDef $itemDef
        }
        
        return $gearItem
    }
    catch {
        Write-Warning "Error formatting item $($Item.itemHash): $($_.Exception.Message)"
        return $null
    }
}

# Determine item category
function Get-ItemCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$ItemDef
    )
    
    if ($ItemDef.itemCategoryHashes) {
        # Common category hashes
        $weaponCategories = @(1, 2, 3) # Kinetic, Energy, Heavy weapon categories
        $armorCategories = @(20, 21, 22, 23, 24) # Helmet, Arms, Chest, Legs, Class Item
        
        foreach ($categoryHash in $ItemDef.itemCategoryHashes) {
            if ($categoryHash -in $weaponCategories -or $ItemDef.itemTypeDisplayName -like "*weapon*") {
                return "Weapon"
            }
            if ($categoryHash -in $armorCategories -or $ItemDef.itemTypeDisplayName -like "*armor*") {
                return "Armor"  
            }
        }
    }
    
    # Fallback based on item type name
    if ($ItemDef.itemTypeDisplayName) {
        $typeName = $ItemDef.itemTypeDisplayName.ToLower()
        if ($typeName -match "rifle|cannon|sword|bow|launcher|shotgun|sidearm|pistol|machine|trace|fusion") {
            return "Weapon"
        }
        if ($typeName -match "helmet|gauntlets|chest|legs|cloak|bond|mark|armor") {
            return "Armor"
        }
    }
    
    return "Other"
}

# Get item tier (Common, Rare, Legendary, Exotic)
function Get-ItemTier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$ItemDef
    )
    
    switch ($ItemDef.inventory.tierType) {
        2 { return "Common" }
        3 { return "Rare" }
        4 { return "Legendary" }
        5 { return "Exotic" }
        default { return "Unknown" }
    }
}

# Get item element
function Get-ItemElement {
    [CmdletBinding()]
    param(
        [hashtable]$InstanceData,
        [hashtable]$ItemDef
    )
    
    if ($InstanceData -and $InstanceData.damageType) {
        switch ($InstanceData.damageType) {
            1 { return "Kinetic" }
            2 { return "Arc" }
            3 { return "Solar" }
            4 { return "Void" }
            6 { return "Stasis" }
            7 { return "Strand" }
            default { return "Unknown" }
        }
    }
    
    # Fallback - check item definition for default damage type
    if ($ItemDef.defaultDamageType) {
        switch ($ItemDef.defaultDamageType) {
            1 { return "Kinetic" }
            2 { return "Arc" }
            3 { return "Solar" }
            4 { return "Void" }
            6 { return "Stasis" }
            7 { return "Strand" }
            default { return "Kinetic" }
        }
    }
    
    return "Kinetic"
}

# Get item sockets (perks, mods, etc.)
function Get-ItemSockets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Item,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$ProfileData,
        
        [hashtable]$Manifest = $null
    )
    
    $sockets = @()
    
    if ($ProfileData.itemSockets -and $ProfileData.itemSockets.data.($Item.itemInstanceId)) {
        $socketData = $ProfileData.itemSockets.data.($Item.itemInstanceId).sockets
        
        foreach ($socket in $socketData) {
            if ($socket.plugHash -and $socket.plugHash -ne 0) {
                # Get plug definition
                $plugDef = $null
                if ($Manifest -and $Manifest.InventoryItems) {
                    $plugDef = $Manifest.InventoryItems.([string]$socket.plugHash)
                }
                
                if (!$plugDef) {
                    $plugDef = Get-ItemDefinition -ItemHash $socket.plugHash
                }
                
                if ($plugDef -and $plugDef.displayProperties.name) {
                    $sockets += @{
                        Name = $plugDef.displayProperties.name
                        Description = $plugDef.displayProperties.description
                        Hash = $socket.plugHash
                        IsEnabled = $socket.isEnabled
                    }
                }
            }
        }
    }
    
    return $sockets
}

# Get item stats
function Get-ItemStats {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Item,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$ProfileData,
        
        [hashtable]$ItemDef
    )
    
    $stats = @{}
    
    if ($ProfileData.itemStats -and $ProfileData.itemStats.data.($Item.itemInstanceId)) {
        $statData = $ProfileData.itemStats.data.($Item.itemInstanceId).stats
        
        foreach ($statHash in $statData.Keys) {
            $stat = $statData.$statHash
            
            # Common stat names mapping
            $statName = switch ($statHash) {
                "1735777505" { "Discipline" }
                "144602215"  { "Intellect" }
                "4244567218" { "Strength" }
                "2996146975" { "Mobility" }
                "392767087"  { "Resilience" }
                "1943323491" { "Recovery" }
                "1885944937" { "Range" }
                "3597844532" { "Stability" }
                "4043523819" { "Handling" }
                "2837207746" { "Swing Speed" }
                "943549884"  { "Damage" }
                default { "Stat_$statHash" }
            }
            
            $stats[$statName] = $stat.value
        }
    }
    
    return $stats
}

# Get masterwork information
function Get-ItemMasterwork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Item,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$ProfileData,
        
        [hashtable]$ItemDef
    )
    
    # Check if item has masterwork
    if ($ProfileData.itemInstances -and $ProfileData.itemInstances.data.($Item.itemInstanceId)) {
        $instanceData = $ProfileData.itemInstances.data.($Item.itemInstanceId)
        
        # Look for masterwork tier
        if ($instanceData.energy) {
            return @{
                Tier = $instanceData.energy.energyCapacity
                Type = "Energy"
            }
        }
    }
    
    return $null
}

# Format complete gear collection for LLM
function Format-GearForLLM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$InventoryData
    )
    
    try {
        Write-Host "Formatting gear data for LLM analysis..." -ForegroundColor Yellow
        
        $allGear = @{
            Characters = @()
            Vault = @()
            Summary = @{
                TotalItems = 0
                WeaponCount = 0
                ArmorCount = 0
                ExoticCount = 0
                LastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
        
        # Process each character
        foreach ($character in $InventoryData.Characters) {
            Write-Host "Processing $($character.Class)..." -ForegroundColor Gray
            
            # Get equipped gear
            $equippedGear = Format-EquippedGear -CharacterId $character.CharacterId -ProfileData $InventoryData.ProfileData -Manifest $InventoryData.Manifest
            
            # Get character inventory
            $characterInventory = Format-CharacterInventory -CharacterId $character.CharacterId -ProfileData $InventoryData.ProfileData -Manifest $InventoryData.Manifest
            
            $characterData = @{
                Class = $character.Class
                Light = $character.Light
                Race = $character.Race
                Gender = $character.Gender
                LastPlayed = $character.LastPlayed.ToString("yyyy-MM-dd")
                Equipped = $equippedGear
                Inventory = $characterInventory
            }
            
            $allGear.Characters += $characterData
        }
        
        # Process vault
        Write-Host "Processing vault..." -ForegroundColor Gray
        $allGear.Vault = Format-VaultInventory -ProfileData $InventoryData.ProfileData -Manifest $InventoryData.Manifest
        
        # Calculate summary statistics
        $totalItems = 0
        $weaponCount = 0
        $armorCount = 0
        $exoticCount = 0
        
        # Count character items
        foreach ($char in $allGear.Characters) {
            $totalItems += $char.Equipped.Count + $char.Inventory.Count
            $weaponCount += ($char.Equipped + $char.Inventory | Where-Object Category -eq "Weapon").Count
            $armorCount += ($char.Equipped + $char.Inventory | Where-Object Category -eq "Armor").Count
            $exoticCount += ($char.Equipped + $char.Inventory | Where-Object Tier -eq "Exotic").Count
        }
        
        # Count vault items
        $totalItems += $allGear.Vault.Count
        $weaponCount += ($allGear.Vault | Where-Object Category -eq "Weapon").Count
        $armorCount += ($allGear.Vault | Where-Object Category -eq "Armor").Count
        $exoticCount += ($allGear.Vault | Where-Object Tier -eq "Exotic").Count
        
        $allGear.Summary = @{
            TotalItems = $totalItems
            WeaponCount = $weaponCount
            ArmorCount = $armorCount
            ExoticCount = $exoticCount
            LastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        
        Write-Host "Gear formatting complete!" -ForegroundColor Green
        Write-Host "   Total items: $totalItems ($weaponCount weapons, $armorCount armor, $exoticCount exotics)" -ForegroundColor Gray
        
        return $allGear
    }
    catch {
        Write-Error "Failed to format gear data: $($_.Exception.Message)"
        throw
    }
}

# Convert gear data to LLM-friendly text format
function Convert-GearToText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$GearData,
        
        [switch]$IncludeDetails
    )
    
    $text = @()
    
    # Header
    $text += "=== DESTINY 2 GEAR COLLECTION ==="
    $text += "Last Updated: $($GearData.Summary.LastUpdated)"
    $text += "Total Items: $($GearData.Summary.TotalItems) ($($GearData.Summary.WeaponCount) weapons, $($GearData.Summary.ArmorCount) armor, $($GearData.Summary.ExoticCount) exotics)"
    $text += ""
    
    # Characters
    foreach ($character in $GearData.Characters) {
        $text += "=== CHARACTER: $($character.Class.ToUpper()) (Light $($character.Light)) ==="
        $text += "Last Played: $($character.LastPlayed)"
        $text += ""
        
        # Equipped gear
        if ($character.Equipped.Count -gt 0) {
            $text += "EQUIPPED GEAR:"
            foreach ($item in $character.Equipped) {
                $itemText = "  $($item.Name) ($($item.Type), $($item.Tier))"
                if ($item.Element -and $item.Element -ne "Kinetic") {
                    $itemText += " - $($item.Element)"
                }
                if ($item.Power) {
                    $itemText += " - $($item.Power) Power"
                }
                $text += $itemText
                
                if ($IncludeDetails -and $item.Sockets.Count -gt 0) {
                    $perks = ($item.Sockets | Where-Object { $_.Name -notlike "*Default*" } | ForEach-Object { $_.Name }) -join ", "
                    if ($perks) {
                        $text += "    Perks: $perks"
                    }
                }
            }
            $text += ""
        }
        
        # Character inventory (summary)
        if ($character.Inventory.Count -gt 0) {
            $text += "CHARACTER INVENTORY:"
            $inventoryWeapons = $character.Inventory | Where-Object Category -eq "Weapon"
            $inventoryArmor = $character.Inventory | Where-Object Category -eq "Armor"
            
            if ($inventoryWeapons.Count -gt 0) {
                $text += "  Weapons ($($inventoryWeapons.Count)):"
                foreach ($weapon in $inventoryWeapons) {
                    $text += "    $($weapon.Name) ($($weapon.Type), $($weapon.Tier)) - $($weapon.Element)"
                }
            }
            
            if ($inventoryArmor.Count -gt 0) {
                $text += "  Armor ($($inventoryArmor.Count)):"
                foreach ($armor in $inventoryArmor) {
                    $text += "    $($armor.Name) ($($armor.Type), $($armor.Tier))"
                }
            }
            $text += ""
        }
    }
    
    # Vault
    if ($GearData.Vault.Count -gt 0) {
        $text += "=== VAULT ==="
        
        $vaultWeapons = $GearData.Vault | Where-Object Category -eq "Weapon"
        $vaultArmor = $GearData.Vault | Where-Object Category -eq "Armor"
        
        if ($vaultWeapons.Count -gt 0) {
            $text += "WEAPONS ($($vaultWeapons.Count)):"
            foreach ($weapon in $vaultWeapons) {
                $weaponText = "  $($weapon.Name) ($($weapon.Type), $($weapon.Tier)) - $($weapon.Element)"
                if ($weapon.Power) {
                    $weaponText += " - $($weapon.Power) Power"
                }
                $text += $weaponText
            }
            $text += ""
        }
        
        if ($vaultArmor.Count -gt 0) {
            $text += "ARMOR ($($vaultArmor.Count)):"
            foreach ($armor in $vaultArmor) {
                $armorText = "  $($armor.Name) ($($armor.Type), $($armor.Tier))"
                if ($armor.Stats -and $armor.Stats.Count -gt 0) {
                    $statText = @()
                    foreach ($statName in @("Mobility", "Resilience", "Recovery", "Discipline", "Intellect", "Strength")) {
                        if ($armor.Stats.$statName) {
                            $statText += "$($statName): $($armor.Stats.$statName)"
                        }
                    }
                    if ($statText.Count -gt 0) {
                        $armorText += " [$($statText -join ', ')]"
                    }
                }
                $text += $armorText
            }
        }
    }
    
    return $text -join "`n"
}

# Save gear data to file
function Save-GearData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$GearData,
        
        [string]$OutputPath = "Data/gear_collection.json",
        
        [switch]$IncludeTextFormat
    )
    
    try {
        # Ensure Data directory exists
        $dataDir = Split-Path $OutputPath -Parent
        if (!(Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        
        # Save JSON format
        $GearData | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "Gear data saved to: $OutputPath" -ForegroundColor Green
        
        # Save text format if requested
        if ($IncludeTextFormat) {
            $textPath = $OutputPath -replace "\.json$", ".txt"
            $textData = Convert-GearToText -GearData $GearData -IncludeDetails
            $textData | Out-File -FilePath $textPath -Encoding UTF8
            Write-Host "Text format saved to: $textPath" -ForegroundColor Green
        }
        
        return $OutputPath
    }
    catch {
        Write-Error "Failed to save gear data: $($_.Exception.Message)"
        throw
    }
}

# Main function to get and format all gear data
function Get-FormattedGearCollection {
    [CmdletBinding()]
    param(
        [switch]$SaveToFile,
        [switch]$IncludeTextFormat
    )
    
    try {
        Write-Host "Starting gear collection process..." -ForegroundColor Cyan
        
        # Get inventory data
        $inventoryData = Get-AllCharacterInventories
        
        # Format for LLM
        $gearData = Format-GearForLLM -InventoryData $inventoryData
        
        # Save if requested
        if ($SaveToFile) {
            Save-GearData -GearData $gearData -IncludeTextFormat:$IncludeTextFormat
        }
        
        return $gearData
    }
    catch {
        Write-Error "Failed to get formatted gear collection: $($_.Exception.Message)"
        throw
    }
}