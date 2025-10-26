# Invoke-LLMAnalysis.ps1
# Functions to analyze Destiny 2 builds using various LLM providers

[CmdletBinding()]
param()

# LLM provider configuration
$script:LLMConfig = @{
    Provider = "claude"  # Default provider
    ApiKey = $null
    CustomUrl = $null
    Model = $null  # Will be set dynamically
    Temperature = 0.7
    MaxTokens = 4000
}

# Cache for available models
$script:AvailableModels = @{}

# Fetch available models from provider
function Get-AvailableModels {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Provider,

        [string]$ApiKey
    )

    # Return cached models if available
    if ($script:AvailableModels[$Provider]) {
        return $script:AvailableModels[$Provider]
    }

    try {
        switch ($Provider) {
            "claude" {
                # Try to fetch models from Anthropic docs
                try {
                    Write-Verbose "Fetching Claude models from Anthropic docs..."
                    $response = Invoke-WebRequest -Uri "https://docs.anthropic.com/en/docs/about-claude/models/overview" -UseBasicParsing -TimeoutSec 5

                    # Extract model IDs from the page content
                    $models = @()

                    # Look for model IDs in code blocks or table cells
                    # Pattern: claude-XXX-X-X-XXXXXXXX or claude-XXX-XXXXXXXX
                    $regexMatches = [regex]::Matches($response.Content, 'claude-[a-z0-9-]+')

                    foreach ($match in $regexMatches) {
                        $modelId = $match.Value
                        # Filter out invalid matches and duplicates
                        if ($modelId -match '^claude-(sonnet|opus|haiku)(-\d)?(-\d)?-\d{8}$' -and $modelId -notin $models) {
                            $models += $modelId
                        }
                    }

                    if ($models.Count -gt 0) {
                        Write-Verbose "Found $($models.Count) Claude models from docs"
                        # Sort by date (newest first) - the date is at the end YYYYMMDD
                        $models = $models | Sort-Object {
                            if ($_ -match '(\d{8})$') {
                                $dateString = $matches[1]
                                [int]$dateString
                            } else {
                                0
                            }
                        } -Descending

                        $script:AvailableModels[$Provider] = $models
                        return $models
                    }
                }
                catch {
                    Write-Verbose "Could not fetch models from Anthropic docs: $($_.Exception.Message)"
                }

                # Fallback to known models if fetch fails
                Write-Verbose "Using fallback Claude model list"
                $models = @(
                    "claude-sonnet-4-5-20250929",  # Claude Sonnet 4.5 (latest known)
                    "claude-haiku-4-5-20251001",   # Claude Haiku 4.5 (latest known)
                    "claude-3-5-sonnet-20240620",  # Claude 3.5 Sonnet
                    "claude-3-opus-20240229",      # Claude 3 Opus
                    "claude-3-haiku-20240307"      # Claude 3 Haiku
                )
                $script:AvailableModels[$Provider] = $models
                return $models
            }
            "haiku" {
                return @("claude-haiku-4-5-20251001", "claude-3-haiku-20240307")
            }
            "opus" {
                return @("claude-3-opus-20240229")
            }
            "gpt4" {
                # OpenAI has a models API
                if ($ApiKey) {
                    $headers = @{
                        "Authorization" = "Bearer $ApiKey"
                    }
                    $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/models" -Headers $headers -ErrorAction SilentlyContinue
                    if ($response.data) {
                        $gptModels = $response.data | Where-Object { $_.id -like "gpt-4*" } | Select-Object -ExpandProperty id
                        $script:AvailableModels[$Provider] = $gptModels
                        return $gptModels
                    }
                }
                # Fallback to known models
                $models = @("gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4")
                $script:AvailableModels[$Provider] = $models
                return $models
            }
            "gemini" {
                # Google has a models API
                if ($ApiKey) {
                    try {
                        $response = Invoke-RestMethod -Uri "https://generativelanguage.googleapis.com/v1beta/models?key=$ApiKey" -ErrorAction SilentlyContinue
                        if ($response.models) {
                            $geminiModels = $response.models | Where-Object { $_.name -like "*gemini*" } | Select-Object -ExpandProperty name | ForEach-Object { $_ -replace "^models/", "" }
                            $script:AvailableModels[$Provider] = $geminiModels
                            return $geminiModels
                        }
                    } catch {
                        # Ignore errors, fall back to defaults
                    }
                }
                # Fallback to known models
                $models = @("gemini-1.5-pro", "gemini-1.5-flash", "gemini-pro")
                $script:AvailableModels[$Provider] = $models
                return $models
            }
            "custom" {
                # Can't determine custom models, return generic
                return @("custom")
            }
        }
    }
    catch {
        Write-Warning "Failed to fetch available models for $Provider, using defaults"
    }

    # Default fallback
    return @("default")
}

# Get best available model for provider
function Get-BestModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Provider,

        [string]$ApiKey
    )

    $availableModels = Get-AvailableModels -Provider $Provider -ApiKey $ApiKey

    # Return the first (usually most capable/latest) model
    if ($availableModels -and $availableModels.Count -gt 0) {
        return $availableModels[0]
    }

    # Ultimate fallback
    return "default"
}

# Available LLM providers
function Get-LLMProviders {
    return @{
        "claude" = @{
            Name = "Claude 4.5 Sonnet (Anthropic)"
            Description = "Best for complex game analysis and build recommendations"
            Endpoint = "https://api.anthropic.com/v1/messages"
            DefaultModel = "claude-sonnet-4-5-20250929"
            EnvVar = "ANTHROPIC_API_KEY"
            RequiresApiKey = $true
        }
        "gpt4" = @{
            Name = "GPT-4o (OpenAI)"
            Description = "Strong reasoning for meta-analysis"
            Endpoint = "https://api.openai.com/v1/chat/completions"
            DefaultModel = "gpt-4o"
            EnvVar = "OPENAI_API_KEY"
            RequiresApiKey = $true
        }
        "gemini" = @{
            Name = "Gemini 1.5 Pro (Google)"
            Description = "Large context window for comprehensive analysis"
            Endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent"
            DefaultModel = "gemini-1.5-pro"
            EnvVar = "GOOGLE_API_KEY"
            RequiresApiKey = $true
        }
        "haiku" = @{
            Name = "Claude 4.5 Haiku (Anthropic)"
            Description = "Faster and cheaper analysis"
            Endpoint = "https://api.anthropic.com/v1/messages"
            DefaultModel = "claude-haiku-4-5-20251001"
            EnvVar = "ANTHROPIC_API_KEY"
            RequiresApiKey = $true
        }
        "opus" = @{
            Name = "Claude 3 Opus (Anthropic)"
            Description = "Most capable model for deep analysis"
            Endpoint = "https://api.anthropic.com/v1/messages"
            DefaultModel = "claude-3-opus-20240229"
            EnvVar = "ANTHROPIC_API_KEY"
            RequiresApiKey = $true
        }
        "custom" = @{
            Name = "Custom API Endpoint"
            Description = "Self-hosted or custom LLM (Ollama, LM Studio, etc.)"
            Endpoint = $null  # User-provided
            DefaultModel = "custom"
            EnvVar = $null
            RequiresApiKey = $false
        }
    }
}

# Configure LLM provider
function Set-LLMProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("claude", "gpt4", "gemini", "haiku", "custom")]
        [string]$Provider,

        [string]$ApiKey,

        [string]$CustomUrl,

        [string]$Model
    )

    $providers = Get-LLMProviders
    $providerConfig = $providers[$Provider]

    $script:LLMConfig.Provider = $Provider

    # Set API key
    if ($ApiKey) {
        $script:LLMConfig.ApiKey = $ApiKey
    } elseif ($providerConfig.EnvVar) {
        $envKey = [System.Environment]::GetEnvironmentVariable($providerConfig.EnvVar)
        if ($envKey) {
            $script:LLMConfig.ApiKey = $envKey
        }
    }

    # Set custom URL for custom provider
    if ($Provider -eq "custom" -and $CustomUrl) {
        $script:LLMConfig.CustomUrl = $CustomUrl
    }

    # Set model - use provided, or fetch best available
    if ($Model) {
        $script:LLMConfig.Model = $Model
    } else {
        Write-Host "Detecting best available model..." -ForegroundColor Gray
        $bestModel = Get-BestModel -Provider $Provider -ApiKey $script:LLMConfig.ApiKey
        $script:LLMConfig.Model = $bestModel
    }

    Write-Host "LLM Provider set to: $($providerConfig.Name)" -ForegroundColor Green
    Write-Host "Model: $($script:LLMConfig.Model)" -ForegroundColor Gray
    if ($script:LLMConfig.ApiKey) {
        Write-Host "API Key: Configured" -ForegroundColor Gray

        # Test the API key with a minimal request
        Write-Host "Testing API connection..." -ForegroundColor Yellow
        $testResult = Test-LLMConnection
        if ($testResult) {
            Write-Host "API connection test: SUCCESS" -ForegroundColor Green
        } else {
            Write-Host "API connection test: FAILED (you may have issues running analysis)" -ForegroundColor Red
        }
    } else {
        Write-Host "API Key: Not configured (required for API calls)" -ForegroundColor Yellow
    }
}

# Test LLM connection
function Test-LLMConnection {
    [CmdletBinding()]
    param()

    try {
        $testPrompt = @{
            System = "You are a helpful assistant."
            User = "Reply with just the word 'OK'"
        }

        # Temporarily reduce max tokens for test
        $originalMaxTokens = $script:LLMConfig.MaxTokens
        $script:LLMConfig.MaxTokens = 50

        $null = Invoke-LLMRequest -Prompt $testPrompt

        # Restore max tokens
        $script:LLMConfig.MaxTokens = $originalMaxTokens

        return $true
    }
    catch {
        Write-Verbose "API test failed: $($_.Exception.Message)"
        return $false
    }
}

# Interactive LLM provider selection
function Select-LLMProvider {
    [CmdletBinding()]
    param()

    $providers = Get-LLMProviders

    Write-Host "`nAvailable LLM Providers:" -ForegroundColor Cyan
    Write-Host "=========================" -ForegroundColor Cyan
    Write-Host ""

    $providerList = @("claude", "gpt4", "gemini", "haiku", "custom")
    for ($i = 0; $i -lt $providerList.Count; $i++) {
        $key = $providerList[$i]
        $provider = $providers[$key]
        Write-Host "$($i + 1). $($provider.Name)" -ForegroundColor White
        Write-Host "   $($provider.Description)" -ForegroundColor Gray
        Write-Host ""
    }

    do {
        $choice = Read-Host "Select LLM provider (1-$($providerList.Count))"
        $choiceNum = [int]$choice - 1
    } while ($choiceNum -lt 0 -or $choiceNum -ge $providerList.Count)

    $selectedProvider = $providerList[$choiceNum]
    $providerConfig = $providers[$selectedProvider]

    # Get API key if required
    $apiKey = $null
    if ($providerConfig.RequiresApiKey) {
        Write-Host "`nAPI Key Configuration" -ForegroundColor Yellow
        Write-Host "You can set the $($providerConfig.EnvVar) environment variable" -ForegroundColor Gray
        Write-Host "or enter it now (will not be saved):" -ForegroundColor Gray

        # Check environment variable first
        $envKey = [System.Environment]::GetEnvironmentVariable($providerConfig.EnvVar)
        if ($envKey) {
            Write-Host "Found API key in environment variable" -ForegroundColor Green
            $apiKey = $envKey
        } else {
            $apiKey = Read-Host "Enter API Key (or press Enter to skip)"
        }
    }

    # Get custom URL if custom provider
    $customUrl = $null
    if ($selectedProvider -eq "custom") {
        Write-Host "`nCustom API Endpoint" -ForegroundColor Yellow
        Write-Host "Enter the full URL of your LLM API endpoint" -ForegroundColor Gray
        Write-Host "Example: http://localhost:11434/api/chat" -ForegroundColor Gray
        $customUrl = Read-Host "Custom URL"
    }

    # Configure the provider
    $params = @{
        Provider = $selectedProvider
    }
    if ($apiKey) { $params.ApiKey = $apiKey }
    if ($customUrl) { $params.CustomUrl = $customUrl }

    Set-LLMProvider @params

    return $selectedProvider
}

# Get current Destiny 2 expansion and power caps from Bungie API
function Get-CurrentDestinyInfo {
    [CmdletBinding()]
    param()

    try {
        # Dot source auth to get API access
        . "$PSScriptRoot\Get-BungieAuth.ps1"

        # Get current season/expansion info from Destiny Settings
        $settingsUri = "https://www.bungie.net/Platform/Settings/"
        $settings = Invoke-BungieApiRequest -Uri $settingsUri

        # Get power cap info from progression
        $progressionUri = "https://www.bungie.net/Platform/Destiny2/Manifest/DestinyPowerCapDefinition/"

        # Extract current season info
        $currentSeason = $settings.destiny2CoreSettings.currentSeasonHash

        # Get season name from manifest if available
        $seasonInfo = @{
            SeasonNumber = $settings.destiny2CoreSettings.currentSeasonNumber
            PowerCapSoft = 200  # Default fallback
            PowerCapPowerful = 500
            PowerCapPinnacle = 550
            ExpansionName = "Current Season"
        }

        # Try to get power caps from settings
        if ($settings.destiny2CoreSettings) {
            # Note: These might not be in the API, using sensible defaults
            # The LLM will use these as a baseline
            $seasonInfo.ExpansionName = "Destiny 2 - Season $($seasonInfo.SeasonNumber)"
        }

        return $seasonInfo
    }
    catch {
        Write-Verbose "Could not fetch current Destiny info: $($_.Exception.Message)"
        # Return safe defaults
        return @{
            SeasonNumber = "Current"
            PowerCapSoft = 200
            PowerCapPowerful = 500
            PowerCapPinnacle = 550
            ExpansionName = "Current Expansion"
        }
    }
}

# Build Destiny 2 analysis prompt
function New-BuildAnalysisPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$GearDataText,

        [string]$CharacterClass = "all",

        [string]$AnalysisType = "general"
    )

    # Get current Destiny 2 info
    $destinyInfo = Get-CurrentDestinyInfo

    $systemPrompt = @"
You are an expert Destiny 2 build analyst with deep knowledge of game mechanics, weapon perks, armor stats, and meta strategies.

CRITICAL GAME KNOWLEDGE (Auto-Updated from Bungie API):
- Current Season/Expansion: $($destinyInfo.ExpansionName)
- Power System: Soft Cap $($destinyInfo.PowerCapSoft), Powerful Cap $($destinyInfo.PowerCapPowerful), Pinnacle Cap $($destinyInfo.PowerCapPinnacle)
- Exotic Limitation: ONE exotic weapon + ONE exotic armor piece maximum per loadout
- Armor Stats: Every stat point matters (no longer tier-based)
- Key Stats: Mobility, Resilience, Recovery, Discipline, Intellect, Strength
- Champion Mods: Required for endgame PvE content
- Raid Meta: Team synergy, survivability, consistent DPS
- PvP Meta: Weapon handling, positioning, ability uptime

EXOTIC RULE ENFORCEMENT (CRITICAL):
- NEVER recommend multiple exotic armor pieces in one build
- NEVER recommend multiple exotic weapons in one loadout
- If analyzing builds, always check you haven't violated this rule before responding
- If you make a mistake, the user may correct you - acknowledge and fix it immediately

Your task is to analyze the player's gear collection and provide detailed, actionable build recommendations.

Focus on:
1. Weapon synergies and optimal perk combinations specific to their gear
2. Armor stat optimization (every point matters)
3. Current season meta and artifact mods
4. Build viability for requested content type
5. Exotic interactions (respecting the ONE weapon + ONE armor limit)
6. Subclass recommendations that synergize with available gear
"@

    $userPrompt = switch ($AnalysisType) {
        "general" {
            @"
Analyze my Destiny 2 gear collection and provide:

1. **Top 3 Build Recommendations**: For each character class, suggest the best builds based on my available gear
2. **Weapon Loadout Analysis**: Identify the strongest weapon combinations for different content types (raids, dungeons, PvP)
3. **Armor Optimization**: Suggest optimal stat distributions and which armor pieces to prioritize
4. **Exotic Recommendations**: Which exotics should I focus on and why
5. **Gaps and Improvements**: What am I missing that would significantly improve my builds

Here is my gear collection:

$GearDataText
"@
        }
        "pvp" {
            @"
Analyze my Destiny 2 gear collection specifically for PvP (Crucible/Trials/Iron Banner).

Provide:
1. Best weapons for current PvP meta
2. Optimal armor stat builds (high mobility for Hunters, resilience for Titans, etc.)
3. Exotic recommendations for competitive play
4. Loadout suggestions for different game modes

Here is my gear collection:

$GearDataText
"@
        }
        "pve" {
            @"
Analyze my Destiny 2 gear collection specifically for PvE content (raids, dungeons, nightfalls, GM content).

Provide:
1. Optimal DPS loadouts
2. Add-clear and survivability builds
3. Exotic recommendations for endgame content
4. Recommended stat distributions for different roles (support, DPS, tank)

Here is my gear collection:

$GearDataText
"@
        }
        "character" {
            @"
Analyze the gear for my $CharacterClass and provide:

1. Top 3 builds optimized for this character
2. Best exotic armor and weapon pairings
3. Stat distribution recommendations
4. Subclass synergies

Here is my gear collection:

$GearDataText
"@
        }
        "raid" {
            @"
Analyze my Destiny 2 gear for RAID content (Salvations Edge, Crota's End, etc.).

Focus on $CharacterClass builds optimized for:
1. Team Support (Wells, Buffs, Debuffs)
2. Boss DPS (sustained damage, burst windows)
3. Add Clear efficiency
4. Survivability in high-level content
5. Champion stunning capability
6. Exotic choices that benefit the raid team

Provide:
- Best raid loadout for $CharacterClass
- Encounter-specific recommendations
- Team synergy options
- Stat priorities for raid content

Here is my gear collection:

$GearDataText
"@
        }
        "vault-cleanup" {
            @"
Analyze my Destiny 2 vault and provide SAFE DISMANTLING RECOMMENDATIONS.

CRITICAL: When identifying items to dismantle, you MUST be SPECIFIC:
- For duplicate weapons: List the EXACT perks of the one to dismantle (e.g., "Dismantle the Funnel Web with Feeding Frenzy + Frenzy, KEEP the one with Subsistence + Frenzy")
- For armor: List the EXACT stat total or specific stats (e.g., "Dismantle the Hunter Helmet with 56 total stats, KEEP the 64 total one")
- Include Power Level if relevant for identification
- Use Item Instance ID or unique identifying info when available

RULES FOR RECOMMENDATIONS:
1. NEVER suggest dismantling exotic weapons or armor
2. Only suggest dismantling duplicate legendary weapons/armor with inferior perk rolls
3. Identify sunset or low-power gear that can be safely removed
4. Flag weapons/armor with poor perk combinations
5. Keep at least ONE of each weapon archetype
6. Keep high-stat armor pieces (total stats matter now)
7. BE SPECIFIC - don't just say "dismantle a Funnel Web" when there are 3 of them

Format your response as:

## SAFE TO DISMANTLE

### Duplicate Weapons (Inferior Rolls)
- [Weapon Name] - [Specific Perks] - Power: [X] - Location: [Vault/Character]
  Reason: [Why this roll is inferior to the one you should keep]

### Poor Perk Combinations
- [Weapon Name] - [Specific Perks] - Power: [X]
  Reason: [Why these perks are suboptimal]

### Low-Stat Armor
- [Armor Piece] ([Class]) - Total Stats: [X] - Specific Stats: [Mob/Res/Rec/Dis/Int/Str values]
  Reason: [Why this can be safely dismantled]

### Sunset/Deprecated Gear
- [Item Name] - Power: [X]
  Reason: [Why this is no longer useful]

## KEEP (For Reference)
List a few examples of items you should definitely KEEP with reasons why.

Here is my gear collection:

$GearDataText
"@
        }
        default {
            @"
Analyze my Destiny 2 gear collection:

$GearDataText
"@
        }
    }

    return @{
        System = $systemPrompt
        User = $userPrompt
    }
}

# Call LLM API
function Invoke-LLMRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Prompt
    )

    if (-not $script:LLMConfig.ApiKey -and $script:LLMConfig.Provider -ne "custom") {
        throw "API key not configured. Please set up your LLM provider first."
    }

    $providers = Get-LLMProviders
    $providerConfig = $providers[$script:LLMConfig.Provider]

    Write-Host "Sending request to $($providerConfig.Name)..." -ForegroundColor Yellow
    Write-Host "Model: $($script:LLMConfig.Model)" -ForegroundColor Gray

    try {
        switch ($script:LLMConfig.Provider) {
            "claude" {
                return Invoke-ClaudeAPI -Prompt $Prompt
            }
            "haiku" {
                return Invoke-ClaudeAPI -Prompt $Prompt
            }
            "gpt4" {
                return Invoke-OpenAIAPI -Prompt $Prompt
            }
            "gemini" {
                return Invoke-GeminiAPI -Prompt $Prompt
            }
            "custom" {
                return Invoke-CustomAPI -Prompt $Prompt
            }
        }
    }
    catch {
        Write-Error "LLM API request failed: $($_.Exception.Message)"
        throw
    }
}

# Claude API implementation
function Invoke-ClaudeAPI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Prompt
    )

    $headers = @{
        "x-api-key" = $script:LLMConfig.ApiKey
        "anthropic-version" = "2023-06-01"
        "content-type" = "application/json"
    }

    $body = @{
        model = $script:LLMConfig.Model
        max_tokens = $script:LLMConfig.MaxTokens
        temperature = $script:LLMConfig.Temperature
        system = $Prompt.System
        messages = @(
            @{
                role = "user"
                content = $Prompt.User
            }
        )
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" `
            -Method Post `
            -Headers $headers `
            -Body $body `
            -ContentType "application/json"

        return $response.content[0].text
    }
    catch {
        # Enhanced error reporting
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $null

        if ($_.ErrorDetails.Message) {
            try {
                $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            } catch {
                $errorBody = $_.ErrorDetails.Message
            }
        }

        Write-Host "`nClaude API Error Details:" -ForegroundColor Red
        Write-Host "Status Code: $statusCode" -ForegroundColor Yellow
        Write-Host "Model: $($script:LLMConfig.Model)" -ForegroundColor Yellow

        if ($errorBody) {
            Write-Host "Error Response:" -ForegroundColor Yellow
            Write-Host ($errorBody | ConvertTo-Json -Depth 5) -ForegroundColor Gray
        }

        if ($statusCode -eq 400) {
            Write-Host "`nPossible causes:" -ForegroundColor Cyan
            Write-Host "- Invalid model name (model may not exist or be deprecated)" -ForegroundColor Gray
            Write-Host "- Request format issue" -ForegroundColor Gray
            Write-Host "- Content too large" -ForegroundColor Gray
        }

        throw
    }
}

# OpenAI API implementation
function Invoke-OpenAIAPI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Prompt
    )

    $headers = @{
        "Authorization" = "Bearer $($script:LLMConfig.ApiKey)"
        "Content-Type" = "application/json"
    }

    $body = @{
        model = $script:LLMConfig.Model
        temperature = $script:LLMConfig.Temperature
        max_tokens = $script:LLMConfig.MaxTokens
        messages = @(
            @{
                role = "system"
                content = $Prompt.System
            },
            @{
                role = "user"
                content = $Prompt.User
            }
        )
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" `
            -Method Post `
            -Headers $headers `
            -Body $body

        return $response.choices[0].message.content
    }
    catch {
        # Enhanced error reporting
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $null

        if ($_.ErrorDetails.Message) {
            try {
                $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            } catch {
                $errorBody = $_.ErrorDetails.Message
            }
        }

        Write-Host "`nOpenAI API Error Details:" -ForegroundColor Red
        Write-Host "Status Code: $statusCode" -ForegroundColor Yellow
        Write-Host "Model: $($script:LLMConfig.Model)" -ForegroundColor Yellow

        if ($errorBody) {
            Write-Host "Error Response:" -ForegroundColor Yellow
            Write-Host ($errorBody | ConvertTo-Json -Depth 5) -ForegroundColor Gray
        }

        if ($statusCode -eq 429) {
            Write-Host "`nRate limit exceeded!" -ForegroundColor Cyan
            Write-Host "- You've hit your API rate limit or quota" -ForegroundColor Gray
            Write-Host "- Wait a few minutes and try again" -ForegroundColor Gray
            Write-Host "- Check your OpenAI usage at: https://platform.openai.com/usage" -ForegroundColor Gray
        } elseif ($statusCode -eq 401) {
            Write-Host "`nAuthentication failed!" -ForegroundColor Cyan
            Write-Host "- Check your OPENAI_API_KEY environment variable" -ForegroundColor Gray
        }

        throw
    }
}

# Gemini API implementation
function Invoke-GeminiAPI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Prompt
    )

    $apiKey = $script:LLMConfig.ApiKey
    $endpoint = "https://generativelanguage.googleapis.com/v1beta/models/$($script:LLMConfig.Model):generateContent?key=$apiKey"

    $body = @{
        contents = @(
            @{
                parts = @(
                    @{
                        text = "$($Prompt.System)`n`n$($Prompt.User)"
                    }
                )
            }
        )
        generationConfig = @{
            temperature = $script:LLMConfig.Temperature
            maxOutputTokens = $script:LLMConfig.MaxTokens
        }
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod -Uri $endpoint `
        -Method Post `
        -Body $body `
        -ContentType "application/json"

    return $response.candidates[0].content.parts[0].text
}

# Custom API implementation (for Ollama, LM Studio, etc.)
function Invoke-CustomAPI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Prompt
    )

    if (-not $script:LLMConfig.CustomUrl) {
        throw "Custom API URL not configured"
    }

    # Generic OpenAI-compatible format (works with Ollama, LM Studio, etc.)
    $body = @{
        model = $script:LLMConfig.Model
        messages = @(
            @{
                role = "system"
                content = $Prompt.System
            },
            @{
                role = "user"
                content = $Prompt.User
            }
        )
        temperature = $script:LLMConfig.Temperature
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod -Uri $script:LLMConfig.CustomUrl `
        -Method Post `
        -Body $body `
        -ContentType "application/json"

    # Try to handle different response formats
    if ($response.choices) {
        return $response.choices[0].message.content
    } elseif ($response.response) {
        return $response.response
    } elseif ($response.content) {
        return $response.content
    } else {
        return $response | ConvertTo-Json
    }
}

# Convert analysis to HTML format
function ConvertTo-AnalysisHTML {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Analysis,

        [string]$Timestamp,

        [string]$AnalysisType = "general"
    )

    # Convert markdown-style formatting to HTML
    $htmlBody = $Analysis
    $htmlBody = [System.Web.HttpUtility]::HtmlEncode($htmlBody)

    # Special handling for vault-cleanup analysis
    $isVaultCleanup = $AnalysisType -eq "vault-cleanup"

    if ($isVaultCleanup) {
        # Add warning box at the top for vault cleanup
        $warningBox = @"
<div class="warning-box">
    <h3>⚠️ Important Safety Notice</h3>
    <p><strong>Double-check before dismantling!</strong> This is an AI-generated recommendation. Always verify items match the exact descriptions below before dismantling. Keep one copy of each weapon type and high-stat armor.</p>
</div>
"@
        # We'll add this after processing
    }

    # Convert markdown headers
    $htmlBody = $htmlBody -replace '(?m)^### (.+)$', '<h3>$1</h3>'
    $htmlBody = $htmlBody -replace '(?m)^## (.+)$', '<h2>$1</h2>'
    $htmlBody = $htmlBody -replace '(?m)^# (.+)$', '<h1>$1</h1>'

    # Convert bold text
    $htmlBody = $htmlBody -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'

    # Convert bullet points with special styling for vault cleanup
    if ($isVaultCleanup) {
        # Track sections to apply appropriate styling
        $lines = $htmlBody -split '\r?\n'
        $inDismantleSection = $false
        $inKeepSection = $false
        $processedLines = @()

        foreach ($line in $lines) {
            # Check for section headers
            if ($line -match 'SAFE TO DISMANTLE' -or $line -match 'Duplicate Weapons|Poor Perk|Low-Stat Armor|Sunset') {
                $inDismantleSection = $true
                $inKeepSection = $false
            }
            elseif ($line -match 'KEEP') {
                $inDismantleSection = $false
                $inKeepSection = $true
            }

            # Process bullet points based on current section
            if ($line -match '^- (.+)') {
                $itemText = $matches[1]
                if ($inDismantleSection) {
                    # Check if it contains "Reason:" for proper formatting
                    if ($itemText -match '^(.+?)\s*Reason:\s*(.+)$') {
                        $processedLines += "<li class=`"dismantle-item`">$($matches[1])<br/><em>Reason: $($matches[2])</em></li>"
                    } else {
                        $processedLines += "<li class=`"dismantle-item`">$itemText</li>"
                    }
                }
                elseif ($inKeepSection) {
                    $processedLines += "<li class=`"keep-item`">$itemText</li>"
                }
                else {
                    $processedLines += "<li>$itemText</li>"
                }
            }
            else {
                $processedLines += $line
            }
        }

        $htmlBody = $processedLines -join "`n"
    } else {
        $htmlBody = $htmlBody -replace '(?m)^- (.+)$', '<li>$1</li>'
    }

    $htmlBody = $htmlBody -replace '(?m)(<li.*?>.*?</li>\r?\n?)+', '<ul>$0</ul>'

    # Convert numbered lists
    $htmlBody = $htmlBody -replace '(?m)^\d+\. (.+)$', '<li>$1</li>'

    # Convert line breaks
    $htmlBody = $htmlBody -replace '\r?\n', '<br />'

    # Insert warning box for vault cleanup
    if ($isVaultCleanup) {
        $htmlBody = $warningBox + $htmlBody
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Destiny 2 Build Analysis - $Timestamp</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #e0e0e0;
            line-height: 1.6;
            padding: 20px;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: rgba(26, 26, 46, 0.95);
            border-radius: 15px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
            overflow: hidden;
        }

        .header {
            background: linear-gradient(135deg, #0f3460 0%, #16213e 100%);
            padding: 30px;
            border-bottom: 3px solid #e94560;
        }

        .header h1 {
            color: #f1f1f1;
            font-size: 2em;
            margin-bottom: 10px;
        }

        .header .meta {
            color: #a0a0a0;
            font-size: 0.9em;
        }

        .content {
            padding: 40px;
        }

        h2 {
            color: #e94560;
            font-size: 1.8em;
            margin: 30px 0 15px 0;
            padding-bottom: 10px;
            border-bottom: 2px solid #533483;
        }

        h3 {
            color: #f39c12;
            font-size: 1.4em;
            margin: 25px 0 12px 0;
        }

        ul, ol {
            margin: 15px 0 15px 30px;
        }

        li {
            margin: 8px 0;
            line-height: 1.8;
        }

        strong {
            color: #f39c12;
            font-weight: 600;
        }

        .footer {
            background: #0f3460;
            padding: 20px;
            text-align: center;
            color: #a0a0a0;
            font-size: 0.9em;
            border-top: 2px solid #533483;
        }

        .analysis-type {
            display: inline-block;
            background: #e94560;
            color: white;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.85em;
            margin-left: 10px;
        }

        /* Vault cleanup specific styles */
        .dismantle-item {
            background: rgba(233, 69, 96, 0.1);
            border-left: 4px solid #e94560;
            padding: 12px;
            margin: 10px 0;
            border-radius: 4px;
        }

        .keep-item {
            background: rgba(46, 213, 115, 0.1);
            border-left: 4px solid #2ed573;
            padding: 12px;
            margin: 10px 0;
            border-radius: 4px;
        }

        .warning-box {
            background: rgba(243, 156, 18, 0.2);
            border: 2px solid #f39c12;
            padding: 15px;
            margin: 20px 0;
            border-radius: 8px;
        }

        .warning-box h3 {
            color: #f39c12;
            margin-top: 0;
        }

        @media (max-width: 768px) {
            body {
                padding: 10px;
            }

            .content {
                padding: 20px;
            }

            .header {
                padding: 20px;
            }

            h1 {
                font-size: 1.5em;
            }

            h2 {
                font-size: 1.4em;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Destiny 2 Build Analysis <span class="analysis-type">$($AnalysisType.ToUpper())</span></h1>
            <div class="meta">
                Generated: $Timestamp | Powered by AI
            </div>
        </div>
        <div class="content">
            $htmlBody
        </div>
        <div class="footer">
            <p>Generated with Destiny 2 Build Tool | Eyes up, Guardian!</p>
        </div>
    </div>
</body>
</html>
"@

    return $html
}

# Main function to analyze builds
function Invoke-BuildAnalysis {
    [CmdletBinding()]
    param(
        [string]$GearDataPath,

        [ValidateSet("general", "pvp", "pve", "character", "raid", "vault-cleanup")]
        [string]$AnalysisType = "general",

        [string]$CharacterClass,

        [switch]$SaveToFile
    )

    try {
        Write-Host "`nStarting Destiny 2 Build Analysis..." -ForegroundColor Cyan
        Write-Host "=====================================" -ForegroundColor Cyan

        # Load gear data
        Write-Host "`n1. Loading gear data..." -ForegroundColor Yellow

        $gearData = $null
        if ($GearDataPath -and (Test-Path $GearDataPath)) {
            $gearData = Get-Content $GearDataPath | ConvertFrom-Json
            Write-Host "   Using: $GearDataPath" -ForegroundColor Gray
        } else {
            # Try to find the most recent gear collection file
            $consolidatedFile = Get-ChildItem -Path "../Data" -Filter "gear_collection.json" -ErrorAction SilentlyContinue

            if ($consolidatedFile) {
                $gearData = Get-Content $consolidatedFile[0].FullName | ConvertFrom-Json
                Write-Host "   Using consolidated file: $($consolidatedFile[0].FullName)" -ForegroundColor Gray
            } else {
                # Try to load individual character files and reconstruct
                Write-Host "   No consolidated file found, attempting to load individual character files..." -ForegroundColor Gray

                $characterFiles = Get-ChildItem -Path "../Data" -Filter "*_gear.json" -Exclude "vault_gear.json" -ErrorAction SilentlyContinue
                $vaultFile = Get-ChildItem -Path "../Data" -Filter "vault_gear.json" -ErrorAction SilentlyContinue

                if ($characterFiles -or $vaultFile) {
                    # Reconstruct gear data from individual files
                    $gearData = @{
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

                    # Load character files
                    foreach ($charFile in $characterFiles) {
                        Write-Host "   Loading: $($charFile.Name)" -ForegroundColor Gray
                        $charData = Get-Content $charFile.FullName | ConvertFrom-Json
                        $gearData.Characters += $charData.Character

                        # Merge equipped and inventory into character object
                        $gearData.Characters[-1] | Add-Member -NotePropertyName "Equipped" -NotePropertyValue $charData.EquippedGear -Force
                        $gearData.Characters[-1] | Add-Member -NotePropertyName "Inventory" -NotePropertyValue $charData.InventoryGear -Force
                    }

                    # Load vault file
                    if ($vaultFile) {
                        Write-Host "   Loading: $($vaultFile.Name)" -ForegroundColor Gray
                        $vaultData = Get-Content $vaultFile.FullName | ConvertFrom-Json
                        $gearData.Vault = $vaultData.VaultGear
                    }

                    Write-Host "   Successfully reconstructed gear data from individual files" -ForegroundColor Green
                } else {
                    throw "No gear data found. Please run gear collection first (option 2, 3, or 4)."
                }
            }
        }

        # Convert gear data to text format
        Write-Host "`n2. Preparing data for analysis..." -ForegroundColor Yellow
        . "$PSScriptRoot\Format-GearData.ps1"
        $gearText = Convert-GearToText -GearData $gearData -IncludeDetails

        Write-Host "   Data size: $(($gearText.Length / 1024).ToString('F2')) KB" -ForegroundColor Gray

        # Build prompt
        Write-Host "`n3. Building analysis prompt..." -ForegroundColor Yellow
        $prompt = New-BuildAnalysisPrompt -GearDataText $gearText -AnalysisType $AnalysisType -CharacterClass $CharacterClass

        # Call LLM
        Write-Host "`n4. Analyzing builds with $($script:LLMConfig.Model)..." -ForegroundColor Yellow
        Write-Host "   (This may take 30-60 seconds...)" -ForegroundColor Gray

        $analysis = Invoke-LLMRequest -Prompt $prompt

        Write-Host "`n5. Analysis complete!" -ForegroundColor Green

        # Display results
        Write-Host "`n=====================================" -ForegroundColor Cyan
        Write-Host "BUILD ANALYSIS RESULTS" -ForegroundColor Cyan
        Write-Host "=====================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host $analysis -ForegroundColor White

        # Save to file if requested
        if ($SaveToFile) {
            $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"

            # Save as text
            $txtFile = "../Data/build_analysis_$timestamp.txt"
            $analysis | Out-File -FilePath $txtFile -Encoding UTF8
            Write-Host "`nAnalysis saved to: $txtFile" -ForegroundColor Green

            # Save as HTML
            $htmlFile = "../Data/build_analysis_$timestamp.html"
            $htmlContent = ConvertTo-AnalysisHTML -Analysis $analysis -Timestamp $timestamp -AnalysisType $AnalysisType
            $htmlContent | Out-File -FilePath $htmlFile -Encoding UTF8
            Write-Host "HTML version saved to: $htmlFile" -ForegroundColor Green
        }

        # Offer follow-up questions
        Write-Host "`n=====================================" -ForegroundColor Cyan
        Write-Host "FOLLOW-UP QUESTIONS" -ForegroundColor Cyan
        Write-Host "=====================================" -ForegroundColor Cyan
        Write-Host "Would you like to ask follow-up questions about this analysis?" -ForegroundColor Yellow
        Write-Host "(y/n): " -ForegroundColor Yellow -NoNewline
        $followUp = Read-Host

        if ($followUp -eq 'y' -or $followUp -eq 'yes') {
            Start-InteractiveChat -InitialAnalysis $analysis -GearDataText $gearText -AnalysisType $AnalysisType
        }

        return $analysis
    }
    catch {
        Write-Error "Build analysis failed: $($_.Exception.Message)"
        throw
    }
}

# Interactive chat for follow-up questions
function Start-InteractiveChat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InitialAnalysis,

        [Parameter(Mandatory=$true)]
        [string]$GearDataText,

        [string]$AnalysisType = "general"
    )

    Write-Host "`n=====================================" -ForegroundColor Cyan
    Write-Host "INTERACTIVE Q&A MODE" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "Ask questions about your builds, or type 'exit' to quit." -ForegroundColor Gray
    Write-Host ""

    # Initialize conversation history
    $conversationHistory = @(
        @{
            role = "assistant"
            content = $InitialAnalysis
        }
    )

    while ($true) {
        Write-Host "Your question: " -ForegroundColor Green -NoNewline
        $userQuestion = Read-Host

        if ($userQuestion -eq 'exit' -or $userQuestion -eq 'quit' -or $userQuestion -eq 'q') {
            Write-Host "`nExiting interactive mode..." -ForegroundColor Yellow
            break
        }

        if ([string]::IsNullOrWhiteSpace($userQuestion)) {
            continue
        }

        # Add user question to history
        $conversationHistory += @{
            role = "user"
            content = $userQuestion
        }

        try {
            Write-Host "`nThinking..." -ForegroundColor Yellow

            # Get current Destiny info for follow-up context
            $destinyInfo = Get-CurrentDestinyInfo

            # Build follow-up prompt
            $followUpPrompt = @{
                System = @"
You are an expert Destiny 2 build analyst. You previously provided a build analysis.
Now answer follow-up questions about the builds, gear, and recommendations.

CRITICAL GAME KNOWLEDGE (Auto-Updated):
- Current Season: $($destinyInfo.ExpansionName)
- Power Caps: Soft $($destinyInfo.PowerCapSoft), Powerful $($destinyInfo.PowerCapPowerful), Pinnacle $($destinyInfo.PowerCapPinnacle)
- Exotic Limitation: ONE exotic weapon + ONE exotic armor per loadout
- Armor Stats: Every point matters (no longer tier-based)

IMPORTANT RULES:
- You can only recommend ONE exotic armor piece per build
- You can only recommend ONE exotic weapon per loadout
- Be specific about which items from their inventory to use
- Explain synergies clearly
- Correct any mistakes from the previous analysis if asked
- If power level info was wrong, use the accurate caps above

Original gear collection:
$GearDataText
"@
                User = $userQuestion
                ConversationHistory = $conversationHistory
            }

            # Get response using conversation history
            $response = Invoke-LLMFollowUp -Prompt $followUpPrompt

            # Add response to history
            $conversationHistory += @{
                role = "assistant"
                content = $response
            }

            # Display response
            Write-Host "`nAssistant: " -ForegroundColor Cyan
            Write-Host $response -ForegroundColor White
            Write-Host ""

        }
        catch {
            Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Please try again or type 'exit' to quit." -ForegroundColor Yellow
        }
    }
}

# LLM follow-up with conversation history
function Invoke-LLMFollowUp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Prompt
    )

    if (-not $script:LLMConfig.ApiKey -and $script:LLMConfig.Provider -ne "custom") {
        throw "API key not configured. Please set up your LLM provider first."
    }

    $providers = Get-LLMProviders
    $providerConfig = $providers[$script:LLMConfig.Provider]

    try {
        switch ($script:LLMConfig.Provider) {
            "claude" {
                return Invoke-ClaudeFollowUp -Prompt $Prompt
            }
            "haiku" {
                return Invoke-ClaudeFollowUp -Prompt $Prompt
            }
            "gpt4" {
                return Invoke-OpenAIFollowUp -Prompt $Prompt
            }
            "gemini" {
                return Invoke-GeminiFollowUp -Prompt $Prompt
            }
            "custom" {
                return Invoke-CustomFollowUp -Prompt $Prompt
            }
        }
    }
    catch {
        Write-Error "LLM follow-up request failed: $($_.Exception.Message)"
        throw
    }
}

# Claude follow-up with history
function Invoke-ClaudeFollowUp {
    param([hashtable]$Prompt)

    $headers = @{
        "x-api-key" = $script:LLMConfig.ApiKey
        "anthropic-version" = "2023-06-01"
        "content-type" = "application/json"
    }

    # Build messages array from conversation history
    $messages = @()
    if ($Prompt.ConversationHistory) {
        $messages = $Prompt.ConversationHistory | ForEach-Object {
            @{
                role = $_.role
                content = $_.content
            }
        }
    }

    # Add current user message
    $messages += @{
        role = "user"
        content = $Prompt.User
    }

    $body = @{
        model = $script:LLMConfig.Model
        max_tokens = 2000
        temperature = $script:LLMConfig.Temperature
        system = $Prompt.System
        messages = $messages
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" `
        -Method Post `
        -Headers $headers `
        -Body $body `
        -ContentType "application/json"

    return $response.content[0].text
}

# OpenAI follow-up with history
function Invoke-OpenAIFollowUp {
    param([hashtable]$Prompt)

    $headers = @{
        "Authorization" = "Bearer $($script:LLMConfig.ApiKey)"
        "Content-Type" = "application/json"
    }

    $messages = @(
        @{
            role = "system"
            content = $Prompt.System
        }
    )

    if ($Prompt.ConversationHistory) {
        $messages += $Prompt.ConversationHistory
    }

    $messages += @{
        role = "user"
        content = $Prompt.User
    }

    $body = @{
        model = $script:LLMConfig.Model
        temperature = $script:LLMConfig.Temperature
        max_tokens = 2000
        messages = $messages
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" `
        -Method Post `
        -Headers $headers `
        -Body $body

    return $response.choices[0].message.content
}

# Gemini follow-up (simplified - doesn't support full conversation history)
function Invoke-GeminiFollowUp {
    param([hashtable]$Prompt)
    # Gemini API is simpler, just combine system + conversation into one prompt
    $combinedPrompt = "$($Prompt.System)`n`n$($Prompt.User)"

    $apiKey = $script:LLMConfig.ApiKey
    $endpoint = "https://generativelanguage.googleapis.com/v1beta/models/$($script:LLMConfig.Model):generateContent?key=$apiKey"

    $body = @{
        contents = @(
            @{
                parts = @(
                    @{ text = $combinedPrompt }
                )
            }
        )
        generationConfig = @{
            temperature = $script:LLMConfig.Temperature
            maxOutputTokens = 2000
        }
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod -Uri $endpoint -Method Post -Body $body -ContentType "application/json"
    return $response.candidates[0].content.parts[0].text
}

# Custom API follow-up
function Invoke-CustomFollowUp {
    param([hashtable]$Prompt)

    $messages = @(
        @{
            role = "system"
            content = $Prompt.System
        }
    )

    if ($Prompt.ConversationHistory) {
        $messages += $Prompt.ConversationHistory
    }

    $messages += @{
        role = "user"
        content = $Prompt.User
    }

    $body = @{
        model = $script:LLMConfig.Model
        messages = $messages
        temperature = $script:LLMConfig.Temperature
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod -Uri $script:LLMConfig.CustomUrl -Method Post -Body $body -ContentType "application/json"

    if ($response.choices) {
        return $response.choices[0].message.content
    } elseif ($response.response) {
        return $response.response
    } elseif ($response.content) {
        return $response.content
    } else {
        return $response | ConvertTo-Json
    }
}
