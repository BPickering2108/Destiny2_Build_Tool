# Get-BungieAuth.ps1
# Bungie API Authentication Functions

[CmdletBinding()]
param()

$script:SessionToken = $null

# Get configuration from environment variables
function Get-BungieConfig {
    [CmdletBinding()]
    param()
    
    $config = @{
        ClientId = [System.Environment]::GetEnvironmentVariable('BUNGIE_CLIENT_ID', 'User')
        ClientSecret = [System.Environment]::GetEnvironmentVariable('BUNGIE_CLIENT_SECRET', 'User')  
        RedirectUri = [System.Environment]::GetEnvironmentVariable('BUNGIE_REDIRECT_URI', 'User')
        ApiKey = [System.Environment]::GetEnvironmentVariable('BUNGIE_API_ID', 'User')
    }
    
    # Validate configuration
    $missing = @()
    if ([string]::IsNullOrEmpty($config.ClientId)) { $missing += "BUNGIE_CLIENT_ID" }
    if ([string]::IsNullOrEmpty($config.ClientSecret)) { $missing += "BUNGIE_CLIENT_SECRET" }
    if ([string]::IsNullOrEmpty($config.RedirectUri)) { $missing += "BUNGIE_REDIRECT_URI" }
    
    if ($missing.Count -gt 0) {
        throw "Missing required environment variables: $($missing -join ', ')"
    }
    
    return $config
}

# Start OAuth flow - opens browser and gets authorization code
function Start-BungieOAuth {
    [CmdletBinding()]
    param()
    
    try {
        $config = Get-BungieConfig
        
        Write-Host "Starting Bungie OAuth authentication..." -ForegroundColor Green
        
        # Build authorization URL
        $authUrl = "https://www.bungie.net/en/OAuth/Authorize?" +
                   "client_id=$($config.ClientId)&" +
                   "response_type=code&" +
                   "redirect_uri=$([uri]::EscapeDataString($config.RedirectUri))"
        
        Write-Host "`nOpening browser for Bungie authentication..." -ForegroundColor Yellow
        Write-Host "You will be redirected to your OAuth page after authorization." -ForegroundColor Yellow
        Write-Host "Copy the authorization code from the page and paste it below.`n" -ForegroundColor Yellow
        
        # Open browser
        Start-Process $authUrl
        
        # Wait for user input
        do {
            $authCode = Read-Host "Enter the authorization code"
            if ([string]::IsNullOrWhiteSpace($authCode)) {
                Write-Host "Authorization code cannot be empty. Please try again." -ForegroundColor Red
            }
        } while ([string]::IsNullOrWhiteSpace($authCode))
        
        return $authCode.Trim()
    }
    catch {
        Write-Error "Failed to start OAuth flow: $($_.Exception.Message)"
        throw
    }
}

# Exchange authorization code for access token
function Get-BungieAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AuthorizationCode
    )
    
    try {
        $config = Get-BungieConfig
        
        Write-Host "Exchanging authorization code for access token..." -ForegroundColor Green
        
        # Prepare token request
        $tokenUrl = "https://www.bungie.net/platform/app/oauth/token/"
        
        $headers = @{
            'Content-Type' = 'application/x-www-form-urlencoded'
            'X-API-Key' = $config.ApiKey
        }
        
        # Ensure body parameters are properly URL encoded, but token response won't be
        $bodyString = "grant_type=authorization_code&code=$([uri]::EscapeDataString($AuthorizationCode))&redirect_uri=$([uri]::EscapeDataString($config.RedirectUri))&client_id=$([uri]::EscapeDataString($config.ClientId))&client_secret=$([uri]::EscapeDataString($config.ClientSecret))"
        
        # Make token request
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $bodyString -Headers $headers
        
        if ($response.access_token) {
            Write-Host "Successfully obtained access token!" -ForegroundColor Green
            
            # Calculate expiration time
            $expiresAt = (Get-Date).AddSeconds($response.expires_in)
            
            $tokenInfo = @{
                AccessToken = $response.access_token
                RefreshToken = $response.refresh_token
                TokenType = $response.token_type
                ExpiresIn = $response.expires_in
                ExpiresAt = $expiresAt
                Scope = $response.scope
            }
            
            # Cache the token
            Save-BungieToken $tokenInfo
            
            return $tokenInfo
        } else {
            throw "No access token received in response"
        }
    }
    catch {
        Write-Error "Failed to get access token: $($_.Exception.Message)"
        throw
    }
}

# Save token to cache file - ULTRA SIMPLIFIED
function Save-BungieToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$TokenInfo
    )
    
    try {
        $cacheFile = "../Data/bungie_token.json"
        
        # Ensure Data directory exists
        $dataDir = Split-Path $cacheFile -Parent
        if (!(Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        
        # Save with creation time instead of expiration
        $tokenData = $TokenInfo.Clone()
        $tokenData.CreatedAt = (Get-Date).ToString()
        $tokenData.Remove('ExpiresAt')
        
        $tokenData | ConvertTo-Json | Out-File -FilePath $cacheFile -Encoding UTF8
        Write-Verbose "Token cached to: $cacheFile"
    }
    catch {
        Write-Warning "Failed to cache token: $($_.Exception.Message)"
    }
}

# Load cached token - ULTRA SIMPLIFIED
function Get-CachedBungieToken {
    [CmdletBinding()]
    param()
    
    try {
        $cacheFile = "../Data/bungie_token.json"
        
        if (!(Test-Path $cacheFile)) {
            Write-Verbose "No cached token found"
            return $null
        }
        
        $tokenData = Get-Content $cacheFile | ConvertFrom-Json
        
        # Calculate if token is still valid (tokens last 1 hour)
        try {
            $createdAt = [DateTime]::Parse($tokenData.CreatedAt)
        } catch {
            $createdAt = [DateTime]::ParseExact($tokenData.CreatedAt, "dd/MM/yyyy HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
        }
        $expiresAt = $createdAt.AddHours(1)
        
        $tokenInfo = @{
            AccessToken = $tokenData.AccessToken
            RefreshToken = $tokenData.RefreshToken  
            TokenType = $tokenData.TokenType
            ExpiresIn = $tokenData.ExpiresIn
            Scope = $tokenData.Scope
        }
        
        # Check if token is still valid (with 5 minute buffer)
        if ($expiresAt -le (Get-Date).AddMinutes(5)) {
            Write-Verbose "Token expired, attempting refresh..."
            $refreshedToken = Update-BungieToken -RefreshToken $tokenData.RefreshToken
            if ($refreshedToken) {
                return $refreshedToken
            } else {
                Write-Verbose "Refresh failed, cached token expired"
                return $null
            }
        }
    }
    catch {
        Write-Warning "Failed to load cached token: $($_.Exception.Message)"
        # Delete corrupted cache file
        $cacheFile = "../Data/bungie_token.json"
        if (Test-Path $cacheFile) {
            Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
        }
        return $null
    }
}

# Get valid access token (cached or new)
function Get-ValidBungieToken {
    [CmdletBinding()]
    param()
    
    # Try to use cached token first
    $cachedToken = Get-CachedBungieToken
    if ($cachedToken) {
        return $cachedToken
    }
    
    # Need to get new token
    Write-Host "No valid cached token found. Starting OAuth flow..." -ForegroundColor Yellow
    $authCode = Start-BungieOAuth
    $tokenInfo = Get-BungieAccessToken -AuthorizationCode $authCode
    
    return $tokenInfo
}

# Connect to Bungie API
function Invoke-BungieApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Uri,
        
        [string]$Method = "GET",
        
        [hashtable]$Body,
        
        [switch]$RequireAuth,
        
        [switch]$UseSessionToken,  # Add this parameter
        
        [int]$MaxRetries = 2
    )
    
    for ($attempt = 1; $attempt -le ($MaxRetries + 1); $attempt++) {
        try {
            $config = Get-BungieConfig
            
            # Base headers
            $headers = @{
                'X-API-Key' = $config.ApiKey
            }
            
            # Add authentication if required
            if ($RequireAuth) {
                if ($UseSessionToken) {
                    # Use session token (preferred)
                    $token = Get-SessionToken
                    if (-not $token) {
                        throw "No session token available. Initialize session first."
                    }
                } else {
                    # Fall back to individual token retrieval (old method)
                    if ($attempt -gt 1) {
                        Write-Host "Attempt $attempt - forcing fresh authentication..." -ForegroundColor Yellow
                        $cacheFile = "../Data/bungie_token.json"
                        if (Test-Path $cacheFile) {
                            Remove-Item $cacheFile -Force
                        }
                    }
                    $token = Get-ValidBungieToken
                }
                
                $headers['Authorization'] = "$($token.TokenType) $($token.AccessToken)"
                Write-Verbose "Using token type: $($token.TokenType)"
                Write-Verbose "Token expires at: $($token.ExpiresAt)"
            }
            
            # Rest of the function stays the same...
            $requestParams = @{
                Uri = $Uri
                Method = $Method
                Headers = $headers
                UseBasicParsing = $true
            }
            
            if ($Body) {
                $requestParams.Body = ($Body | ConvertTo-Json)
                $headers['Content-Type'] = 'application/json'
            }
            
            Write-Verbose "Making API request to: $Uri (attempt $attempt)"
            $response = Invoke-RestMethod @requestParams
            
            if ($response.ErrorCode -ne 1) {
                throw "Bungie API error: $($response.Message) (Code: $($response.ErrorCode))"
            }
            
            return $response.Response
        }
        catch {
            $isServerError = $_.Exception.Message -like "*500*"
            $isLastAttempt = $attempt -eq ($MaxRetries + 1)
            
            if ($isServerError -and !$isLastAttempt) {
                Write-Host "Got 500 error on attempt $attempt, retrying..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                continue
            } else {
                Write-Error "API request failed: $($_.Exception.Message)"
                throw
            }
        }
    }
}

# Test API connection
function Test-BungieApiConnection {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "Testing Bungie API connection..." -ForegroundColor Green
        
        # Test unauthenticated endpoint
        $manifest = Invoke-BungieApiRequest -Uri "https://www.bungie.net/Platform/Destiny2/Manifest/"
        Write-Host "Unauthenticated API access working" -ForegroundColor Green
        Write-Host "   Current game version: $($manifest.version)" -ForegroundColor Gray
        
        # Initialize session ONCE
        Initialize-BungieSession | Out-Null
        
        # Test authenticated endpoint using session token
        $user = Invoke-BungieApiRequest -Uri "https://www.bungie.net/Platform/User/GetMembershipsForCurrentUser/" -RequireAuth -UseSessionToken
        Write-Host "Authenticated API access working" -ForegroundColor Green
        Write-Host "   Found $($user.destinyMemberships.Count) Destiny membership(s)" -ForegroundColor Gray
        return $user
    }
    catch {
        Write-Host "API connection test failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Get token once and store in session
function Initialize-BungieSession {
    [CmdletBinding()]
    param()
    
    Write-Host "Initializing Bungie API session..." -ForegroundColor Green
    
    # Try cached token first
    $cachedToken = Get-CachedBungieToken
    if ($cachedToken) {
        Write-Host "Using cached authentication token" -ForegroundColor Green
        $script:SessionToken = $cachedToken
        return $cachedToken
    }
    
    # Need new token
    Write-Host "Getting new authentication token..." -ForegroundColor Yellow
    $authCode = Start-BungieOAuth
    $tokenInfo = Get-BungieAccessToken -AuthorizationCode $authCode
    
    # Store in session
    $script:SessionToken = $tokenInfo
    Write-Host "Bungie API session initialized successfully" -ForegroundColor Green
    
    return $tokenInfo
}

# Get session token (no additional auth required)
function Get-SessionToken {
    [CmdletBinding()]
    param()
    
    if ($script:SessionToken) {
        # Check if still valid
        if ($script:SessionToken.ExpiresAt -gt (Get-Date).AddMinutes(5)) {
            return $script:SessionToken
        } else {
            Write-Verbose "Session token expired, clearing"
            $script:SessionToken = $null
        }
    }
    
    Write-Warning "No valid session token available. Call Initialize-BungieSession first."
    return $null
}

function Update-BungieToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RefreshToken
    )
    
    try {
        $config = Get-BungieConfig
        Write-Host "Refreshing access token..." -ForegroundColor Yellow
        
        $tokenUrl = "https://www.bungie.net/platform/app/oauth/token/"
        $headers = @{
            'Content-Type' = 'application/x-www-form-urlencoded'
            'X-API-Key' = $config.ApiKey
        }
        
        $bodyString = "grant_type=refresh_token&refresh_token=$([uri]::EscapeDataString($RefreshToken))"
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $bodyString -Headers $headers
        
        if ($response.access_token) {
            $expiresAt = (Get-Date).AddSeconds($response.expires_in)
            
            $tokenInfo = @{
                AccessToken = $response.access_token
                RefreshToken = $response.refresh_token
                TokenType = $response.token_type
                ExpiresIn = $response.expires_in
                ExpiresAt = $expiresAt
                Scope = $response.scope
            }
            
            Save-BungieToken $tokenInfo
            return $tokenInfo
        }
    }
    catch {
        Write-Warning "Failed to refresh token: $($_.Exception.Message)"
        return $null
    }
}