# Setup.ps1
# First-time setup script for Destiny 2 Build Tool

[CmdletBinding()]
param()

$ToolRoot = $PSScriptRoot

Clear-Host
Write-Host ""
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "  Destiny 2 Build Tool Setup     " -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Check PowerShell version
Write-Host "Checking system requirements..." -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
Write-Host "  PowerShell Version: $($psVersion.Major).$($psVersion.Minor)" -ForegroundColor Gray

if ($psVersion.Major -lt 5) {
    Write-Host ""
    Write-Host "ERROR: This tool requires PowerShell 5.1 or higher." -ForegroundColor Red
    Write-Host "Please update PowerShell and try again." -ForegroundColor Red
    Write-Host ""
    Write-Host "Press Enter to exit..." -ForegroundColor Yellow
    Read-Host
    exit 1
}

Write-Host "  PowerShell version OK!" -ForegroundColor Green
Write-Host ""

# Create required directories
Write-Host "Creating required directories..." -ForegroundColor Yellow
$requiredDirs = @("Data", "Manifest", "Scripts")
foreach ($dir in $requiredDirs) {
    $dirPath = Join-Path $ToolRoot $dir
    if (-not (Test-Path $dirPath)) {
        New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
        Write-Host "  Created: $dir" -ForegroundColor Gray
    } else {
        Write-Host "  Exists: $dir" -ForegroundColor Gray
    }
}
Write-Host ""

# Check for .env file
$envFile = Join-Path $ToolRoot ".env"
if (Test-Path $envFile) {
    Write-Host "Configuration file (.env) already exists." -ForegroundColor Green
    Write-Host ""
    Write-Host "Would you like to reconfigure? (y/n): " -ForegroundColor Yellow -NoNewline
    $reconfigure = Read-Host
    if ($reconfigure -ne 'y' -and $reconfigure -ne 'yes') {
        Write-Host ""
        Write-Host "Setup complete! Run Start-DestinyBuildTool.bat to launch the tool." -ForegroundColor Green
        Write-Host ""
        Write-Host "Press Enter to exit..." -ForegroundColor Yellow
        Read-Host
        exit 0
    }
    Write-Host ""
}

# Guide user through API setup
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "  Bungie.net API Configuration   " -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "To use this tool, you need a Bungie.net API key." -ForegroundColor White
Write-Host ""
Write-Host "Follow these steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Go to: https://www.bungie.net/en/Application" -ForegroundColor White
Write-Host "2. Click 'Create New App'" -ForegroundColor White
Write-Host "3. Fill in the form:" -ForegroundColor White
Write-Host "   - Application Name: (anything you want)" -ForegroundColor Gray
Write-Host "   - Application Status: Private" -ForegroundColor Gray
Write-Host "   - Website: http://localhost" -ForegroundColor Gray
Write-Host "   - OAuth Client Type: Confidential" -ForegroundColor Gray
Write-Host "   - Redirect URL: http://localhost:8080/oauth_redirect.html" -ForegroundColor Gray
Write-Host "   - Scope: Check 'Read your Destiny 2 information'" -ForegroundColor Gray
Write-Host "4. Click 'Create New App'" -ForegroundColor White
Write-Host "5. Copy the API Key and OAuth Client ID from the confirmation page" -ForegroundColor White
Write-Host ""
Write-Host "Press Enter when you're ready to enter your API credentials..." -ForegroundColor Yellow
Read-Host

Write-Host ""
Write-Host "Enter your Bungie.net API Key: " -ForegroundColor Yellow -NoNewline
$apiKey = Read-Host

Write-Host "Enter your OAuth Client ID: " -ForegroundColor Yellow -NoNewline
$clientId = Read-Host

Write-Host "Enter your OAuth Client Secret: " -ForegroundColor Yellow -NoNewline
$clientSecret = Read-Host -AsSecureString
$clientSecretText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientSecret)
)

# Create .env file
$envContent = @"
# Bungie.net API Configuration
BUNGIE_API_KEY=$apiKey
BUNGIE_CLIENT_ID=$clientId
BUNGIE_CLIENT_SECRET=$clientSecretText

# LLM API Keys (Optional - configure these if you want AI build analysis)
# Get keys from:
# - Claude: https://console.anthropic.com/
# - OpenAI: https://platform.openai.com/api-keys
# - Google: https://ai.google.dev/

# CLAUDE_API_KEY=your_claude_api_key_here
# OPENAI_API_KEY=your_openai_api_key_here
# GOOGLE_API_KEY=your_google_api_key_here
"@

$envContent | Out-File -FilePath $envFile -Encoding UTF8
Write-Host ""
Write-Host "Configuration saved to .env file!" -ForegroundColor Green
Write-Host ""

# Ask about LLM setup
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "  LLM API Configuration (Optional)" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "The tool can use AI to analyze your builds and provide recommendations." -ForegroundColor White
Write-Host "This requires an API key from one of these providers:" -ForegroundColor White
Write-Host ""
Write-Host "  - Anthropic Claude (Recommended): https://console.anthropic.com/" -ForegroundColor Gray
Write-Host "  - OpenAI GPT-4: https://platform.openai.com/api-keys" -ForegroundColor Gray
Write-Host "  - Google Gemini: https://ai.google.dev/" -ForegroundColor Gray
Write-Host ""
Write-Host "Would you like to configure an LLM API now? (y/n): " -ForegroundColor Yellow -NoNewline
$configureLLM = Read-Host

if ($configureLLM -eq 'y' -or $configureLLM -eq 'yes') {
    Write-Host ""
    Write-Host "Select your preferred provider:" -ForegroundColor Yellow
    Write-Host "1. Anthropic Claude (Recommended)" -ForegroundColor White
    Write-Host "2. OpenAI GPT-4" -ForegroundColor White
    Write-Host "3. Google Gemini" -ForegroundColor White
    Write-Host ""
    $provider = Read-Host "Select provider (1-3)"

    $llmKey = ""
    $llmKeyName = ""

    switch ($provider) {
        '1' {
            $llmKeyName = "CLAUDE_API_KEY"
            Write-Host ""
            Write-Host "Get your Claude API key from: https://console.anthropic.com/" -ForegroundColor Cyan
            Write-Host "Enter your Claude API Key: " -ForegroundColor Yellow -NoNewline
            $llmKey = Read-Host
        }
        '2' {
            $llmKeyName = "OPENAI_API_KEY"
            Write-Host ""
            Write-Host "Get your OpenAI API key from: https://platform.openai.com/api-keys" -ForegroundColor Cyan
            Write-Host "Enter your OpenAI API Key: " -ForegroundColor Yellow -NoNewline
            $llmKey = Read-Host
        }
        '3' {
            $llmKeyName = "GOOGLE_API_KEY"
            Write-Host ""
            Write-Host "Get your Google API key from: https://ai.google.dev/" -ForegroundColor Cyan
            Write-Host "Enter your Google API Key: " -ForegroundColor Yellow -NoNewline
            $llmKey = Read-Host
        }
        default {
            Write-Host "Invalid selection, skipping LLM configuration." -ForegroundColor Red
        }
    }

    if ($llmKey) {
        # Update .env file with LLM key
        $envContent = Get-Content $envFile
        $envContent = $envContent -replace "# $llmKeyName=.*", "$llmKeyName=$llmKey"
        $envContent | Out-File -FilePath $envFile -Encoding UTF8
        Write-Host ""
        Write-Host "LLM API key configured!" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "Skipping LLM configuration. You can add API keys to the .env file later." -ForegroundColor Gray
}

Write-Host ""
Write-Host "==================================" -ForegroundColor Green
Write-Host "  Setup Complete!                 " -ForegroundColor Green
Write-Host "==================================" -ForegroundColor Green
Write-Host ""
Write-Host "You can now run the tool by:" -ForegroundColor White
Write-Host "  1. Double-clicking: Start-DestinyBuildTool.bat" -ForegroundColor Cyan
Write-Host "  2. Running: .\Start-DestinyBuildTool.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: You can edit the .env file at any time to update your API keys." -ForegroundColor Gray
Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Yellow
Read-Host
