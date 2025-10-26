# Destiny 2 Build Tool

An AI-powered PowerShell tool that analyzes your Destiny 2 gear collection and provides intelligent build recommendations using Large Language Models.

## Features

- **Bungie API Integration**: Securely connects to your Destiny 2 account
- **Complete Gear Collection**: Retrieves all weapons, armor, perks, and stats from characters and vault
- **Multi-LLM Support**: Works with Claude, GPT-4, Gemini, or local models
- **Smart Build Analysis**: AI-powered recommendations for PvP, PvE, and general gameplay
- **Interactive Q&A**: Ask follow-up questions to refine build recommendations
- **HTML Reports**: Beautiful, shareable HTML reports of your build analysis
- **Detailed Stats & Perks**: Extracts full item data including sockets, stats, and masterwork info

## Important: API Costs

**This tool requires LLM API access with credits/quota.**

- **Recommended**: Anthropic Claude API ($5-20 credits recommended)
- **Alternative**: OpenAI, Google Gemini, or local models (Ollama - free)
- **Cost per analysis**: $0.05 - $0.20 depending on gear collection size
- **Free option**: Use local models like Ollama (no API costs)

**Don't want to use APIs?** You can:
1. Run gear collection (free, uses Bungie API only)
2. Manually upload generated JSON files to ChatGPT/Claude web interfaces
3. Use the exported data with any LLM of your choice

## Quick Start

### Installation

1. **Download or clone this repository**
   ```bash
   git clone https://github.com/yourusername/DestinyBuildTool.git
   cd DestinyBuildTool
   ```

2. **Run the setup script**
   - **Windows**: Double-click `Setup.ps1` OR right-click and select "Run with PowerShell"
   - **Command Line**: `.\Setup.ps1`

3. **Follow the interactive setup wizard**
   - The script will guide you through Bungie API setup
   - Optionally configure LLM API for AI analysis
   - All credentials are stored securely in a `.env` file

### Running the Tool

**Easy Method (Recommended):**
- **Windows**: Double-click `Start-DestinyBuildTool.bat`
- **PowerShell**: `.\Start-DestinyBuildTool.ps1`

**From anywhere on your system:**
```powershell
# Add to your PowerShell profile for quick access
Set-Alias destiny "C:\Path\To\DestinyBuildTool\Start-DestinyBuildTool.ps1"
# Then just type: destiny
```

### First-Time Setup Details

The setup wizard will help you configure:

**1. Bungie.net API (Required)**
- Go to https://www.bungie.net/en/Application
- Create a new application with these settings:
  - **OAuth Client Type**: Confidential
  - **Redirect URL**: `http://localhost:8080/oauth_redirect.html`
  - **Scope**: "Read your Destiny 2 information"
- Copy your API Key, Client ID, and Client Secret

**2. LLM API (Optional - for AI analysis only)**
- **Anthropic Claude** (Recommended): https://console.anthropic.com/
- **OpenAI GPT-4**: https://platform.openai.com/api-keys
- **Google Gemini**: https://ai.google.dev/
- **Cost**: ~$0.05-$0.20 per analysis, $5-20 recommended for regular use

**Don't want to pay for API?** No problem! You can:
- Skip LLM setup and just collect your gear data (free)
- Manually upload the generated JSON/TXT files to ChatGPT or Claude web interface
- Use local models like Ollama (free, runs on your PC)

## Usage Guide

### Interactive Menu

The tool provides an easy-to-use menu:

1. **Test API Connection** - Verify Bungie API credentials
2. **Get Gear Collection (No Save)** - Retrieve and display your gear
3. **Get Gear Collection + Save Consolidated** - Save all data to one JSON file
4. **Get Gear Collection + Save Individual Files** - Save separate files per character
5. **Get Gear Collection + Save Both Formats** - Save both consolidated and individual files
6. **AI Build Analysis** - Analyze builds with LLM (requires setup)
7. **Configure LLM Provider** - Set up AI analysis provider
8. **Clear Authentication Cache** - Force re-authentication

### Command Line Options

```powershell
# Test connection only
.\DestinyBuildTool.ps1 -TestConnection

# Full collection with save
.\DestinyBuildTool.ps1 -FullCollection -SaveData

# Save separate character files
.\DestinyBuildTool.ps1 -FullCollection -SaveData -SeparateFiles

# Force re-authentication
.\DestinyBuildTool.ps1 -ForceAuth
```

## LLM Analysis Setup

The tool supports multiple LLM providers for AI-powered build analysis.

### Supported LLM Providers

#### 1. **Claude 3.5 Sonnet (Anthropic)** - **RECOMMENDED**
- Best for complex game analysis and build recommendations
- Excellent reasoning about synergies and meta strategies
- 200k context window

**Setup:**
```powershell
$env:ANTHROPIC_API_KEY = "your-api-key-here"
```
Get your API key: https://console.anthropic.com/

#### 2. **GPT-4o (OpenAI)**
- Strong reasoning for meta-analysis

**Setup:**
```powershell
$env:OPENAI_API_KEY = "your-api-key-here"
```
Get your API key: https://platform.openai.com/api-keys

#### 3. **Gemini 1.5 Pro (Google)**
- Large context window, free tier available

**Setup:**
```powershell
$env:GOOGLE_API_KEY = "your-api-key-here"
```
Get your API key: https://makersuite.google.com/app/apikey

#### 4. **Claude 3.5 Haiku (Anthropic)**
- Faster and cheaper alternative

**Setup:**
```powershell
$env:ANTHROPIC_API_KEY = "your-api-key-here"
```

#### 5. **Custom API Endpoint**
For self-hosted models (Ollama, LM Studio, etc.)

**Example - Ollama:**
```bash
ollama run llama3.1
```
Then in tool: URL = `http://localhost:11434/api/chat`

**Example - LM Studio:**
Start server on port 1234, use URL = `http://localhost:1234/v1/chat/completions`

### Analysis Types

- **general**: Overall build recommendations for all characters
- **pvp**: PvP-focused (Crucible, Trials, Iron Banner)
- **pve**: PvE-focused (Raids, Dungeons, Nightfalls, GMs)
- **character**: Character-specific builds

### Cost Estimates (per analysis)

- **Claude 3.5 Sonnet**: $0.05 - $0.15
- **GPT-4o**: $0.08 - $0.20
- **Gemini 1.5 Pro**: $0.02 - $0.08 (often free)
- **Claude 3.5 Haiku**: $0.01 - $0.03
- **Local/Custom**: Free

## Project Structure

```
DestinyBuildTool/
├── Start-DestinyBuildTool.bat    # Windows launcher (double-click)
├── Start-DestinyBuildTool.ps1    # PowerShell launcher
├── Setup.ps1                      # First-time setup wizard
├── .env                           # API credentials (created by Setup.ps1)
├── Scripts/
│   ├── DestinyBuildTool.ps1       # Main tool logic
│   ├── Get-BungieAuth.ps1         # OAuth authentication
│   ├── Get-DestinyInventory.ps1   # Gear collection
│   ├── Format-GearData.ps1        # Data formatting
│   └── Invoke-LLMAnalysis.ps1     # AI analysis
├── Data/                          # Generated gear data (created at runtime)
├── Manifest/                      # Cached Destiny manifest (auto-downloaded)
└── readme.md
```

## Data Output

### Gear Collection Files

All data is saved to the `Data/` folder:

- **gear_collection.json**: Complete consolidated data
- **gear_collection.txt**: Human-readable text format
- **[Class]_gear.json**: Individual character files (with `-SeparateFiles`)
- **vault_gear.json**: Vault items
- **build_analysis_[timestamp].txt**: AI analysis results

### Collected Data Includes

- Character info (class, light level, stats)
- Equipped gear with perks and stats
- Character inventory
- Vault items
- Weapon stats (range, stability, reload, RPM, etc.)
- Armor stats (mobility, resilience, recovery, discipline, intellect, strength)
- Perks and mods (excluding cosmetics)
- Masterwork information
- Item tier (Common, Rare, Legendary, Exotic)

## Authentication Flow

1. First run prompts you to authenticate via browser
2. Login with Bungie.net credentials
3. Authorize the application
4. Token is cached for future use
5. Use option 8 to clear cached token and re-authenticate

## Troubleshooting

### Setup and Launcher Issues

**"Cannot run scripts" or "Execution Policy" error:**
```powershell
# Windows PowerShell (Run as Administrator):
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or run the script with bypass:
powershell.exe -ExecutionPolicy Bypass -File .\Start-DestinyBuildTool.ps1
```

**Double-clicking .bat file does nothing:**
- Right-click `Start-DestinyBuildTool.bat` → "Run as administrator"
- Or right-click `Setup.ps1` → "Run with PowerShell"

**".env file not found" error:**
- Run `Setup.ps1` first to create the configuration file
- Or manually create `.env` in the root directory with your API keys

### API and Authentication Issues

**"API key not configured":**
- Run `Setup.ps1` to configure credentials
- Or manually edit the `.env` file with your API keys

**"No Destiny 2 characters found":**
- Ensure you're logged into the correct Bungie account
- Make sure your Destiny 2 profile is set to public in Bungie.net privacy settings

**"OAuth token has expired":**
- Use menu option 8 to clear cache and re-authenticate
- Or delete `Data/bungie_token.json` manually

**"No gear data found" (for LLM analysis):**
- Run menu option 3, 4, or 5 to collect gear first
- Analysis requires saved gear data

## Privacy & Security

- **API Keys**: Never saved to disk (memory only during session)
- **OAuth Tokens**: Cached locally in `Data/bungie_token.json` (gitignored)
- **Gear Data**: Saved locally, use local LLMs for complete privacy
- **Bungie Credentials**: Never stored, only OAuth flow used

## Best Practices

1. **Collect gear data first** - Run options 3, 4, or 5 to save your gear data
2. **Use Claude Sonnet** - Best results for game-specific analysis (requires API credits)
3. **Ask follow-up questions** - Refine builds, fix mistakes (exotic conflicts, etc.)
4. **Different analysis types** - Try PvP vs PvE for tailored recommendations
5. **Local models** - Use Ollama/LM Studio for privacy and unlimited free usage
6. **Manual upload option** - Export JSON and upload to ChatGPT/Claude web if preferred

## Free Alternative (No API Costs)

If you don't want to pay for API access:

1. Run the tool with option **5** (Save Both Formats)
2. Open `Data/gear_collection.txt`
3. Copy the contents
4. Paste into ChatGPT or Claude web interface
5. Ask for build recommendations directly

**This gives you the same analysis without API costs!**

## For Developers

### Running from Source

1. Clone the repository
2. Copy `.env.example` to `.env` and fill in your API keys
3. Run `.\Start-DestinyBuildTool.ps1`

### Project Structure

- **Start-DestinyBuildTool.ps1**: Main launcher, loads .env file
- **Setup.ps1**: Interactive first-time setup wizard
- **Scripts/**: Core tool modules
  - `DestinyBuildTool.ps1`: Main menu and orchestration
  - `Get-BungieAuth.ps1`: OAuth flow and authentication
  - `Get-DestinyInventory.ps1`: API calls for gear collection
  - `Format-GearData.ps1`: Data processing and formatting
  - `Invoke-LLMAnalysis.ps1`: LLM integration and analysis

### Release Checklist

Before pushing to GitHub:
- [x] `.env` file is in `.gitignore`
- [x] `.env.example` template is included
- [x] Launcher scripts load .env automatically
- [x] README has clear installation instructions
- [x] Setup wizard guides users through API configuration
- [x] No hardcoded API keys or secrets in code
- [x] All sensitive data is gitignored (Data/, tokens, etc.)

## Contributing

Contributions welcome! Please open issues or pull requests on GitHub.

## License

See LICENSE file for details.

## Acknowledgments

- Built using the Bungie.net API
- Powered by various LLM providers
- Thanks to the Destiny 2 community for meta insights

---

**Eyes up, Guardian!**
