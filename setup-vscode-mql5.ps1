<#
.SYNOPSIS
    Generic MQL5 Project Initializer for VS Code
.EXAMPLE
    .\init-mql5-project.ps1
#>

[CmdletBinding()]
param(
    [switch]$SkipExtensions,
    [switch]$OpenAfterSetup = $true
)

$ErrorActionPreference = "Continue"
$CurrentFolder = Get-Location

$extensions = @(
    @{id="mql5.mql5"; name="MQL5 Language Support"},
    @{id="ms-vscode.cpptools"; name="C/C++ IntelliSense"},
    @{id="streetsidesoftware.code-spell-checker"; name="Code Spell Checker"},
    @{id="eamodio.gitlens"; name="GitLens"},
    @{id="CoenraadS.bracket-pair-colorizer-2"; name="Bracket Pair Colorizer"},
    @{id="aaron-bond.better-comments"; name="Better Comments"},
    @{id="usernamehw.errorlens"; name="Error Lens"},
    @{id="christian-kohler.path-intellisense"; name="Path Intellisense"},
    @{id="wayou.vscode-todo-highlight"; name="TODO Highlight"},
    @{id="PKief.material-icon-theme"; name="Material Icon Theme"}
)

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "======================================" -ForegroundColor Yellow
    Write-Host " $Text" -ForegroundColor Yellow
    Write-Host "======================================" -ForegroundColor Yellow
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Info {
    param([string]$Text)
    Write-Host "  [INFO] $Text" -ForegroundColor Gray
}

function Write-Fail {
    param([string]$Text)
    Write-Host "  [FAIL] $Text" -ForegroundColor Red
}

function Test-VSCode {
    try {
        $version = code --version 2>&1 | Select-Object -First 1
        return @{Success=$true; Version=$version}
    } catch {
        return @{Success=$false; Version=$null}
    }
}

function Install-VSCodeExtension {
    param([string]$ExtensionId, [string]$ExtensionName)
    try {
        code --install-extension $ExtensionId --force 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$ExtensionName"
            return $true
        } else {
            Write-Fail "$ExtensionName"
            return $false
        }
    } catch {
        Write-Fail "$ExtensionName"
        return $false
    }
}

function New-ProjectStructure {
    param([string]$BasePath)
    $folders = @(
        "$BasePath\Experts",
        "$BasePath\Include",
        "$BasePath\Scripts",
        "$BasePath\Indicators",
        "$BasePath\.vscode",
        "$BasePath\Docs"
    )
    $created = 0
    $existing = 0
    foreach ($folder in $folders) {
        if (-not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            Write-Success "Created: $(Split-Path $folder -Leaf)\"
            $created++
        } else {
            Write-Info "Exists: $(Split-Path $folder -Leaf)\"
            $existing++
        }
    }
    return @{Created=$created; Existing=$existing}
}

function New-ConfigFile {
    param([string]$Path, [string]$Content, [string]$Name)
    try {
        $Content | Out-File -FilePath $Path -Encoding UTF8 -Force
        Write-Success "Created: $Name"
        return $true
    } catch {
        Write-Fail "Failed: $Name"
        return $false
    }
}

Clear-Host
Write-Header "MQL5 Project Initializer"
Write-Host "Current folder: $CurrentFolder" -ForegroundColor White
Write-Host "Project name: $(Split-Path $CurrentFolder -Leaf)" -ForegroundColor White
Write-Host ""

Write-Step "Step 1/4: Checking VS Code..."
$vscodeCheck = Test-VSCode
if ($vscodeCheck.Success) {
    Write-Success "VS Code found: $($vscodeCheck.Version)"
} else {
    Write-Fail "VS Code not found in PATH!"
    Write-Host ""
    Write-Host "Add VS Code to PATH:" -ForegroundColor Yellow
    Write-Host "  1. Open VS Code" -ForegroundColor White
    Write-Host "  2. Press Ctrl+Shift+P" -ForegroundColor White
    Write-Host "  3. Type: 'Shell Command: Install code command in PATH'" -ForegroundColor White
    Write-Host ""
    exit 1
}
Write-Host ""

if (-not $SkipExtensions) {
    Write-Step "Step 2/4: Installing extensions..."
    Write-Host ""
    $total = $extensions.Count
    $current = 0
    $success = 0
    foreach ($ext in $extensions) {
        $current++
        Write-Host "  [$current/$total] $($ext.name)" -ForegroundColor White
        if (Install-VSCodeExtension -ExtensionId $ext.id -ExtensionName $ext.name) {
            $success++
        }
    }
    Write-Host ""
    Write-Host "  Installed: $success/$total" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Step "Step 2/4: Skipping extensions"
    Write-Host ""
}

Write-Step "Step 3/4: Creating project structure..."
$structureResult = New-ProjectStructure -BasePath $CurrentFolder
Write-Host ""
Write-Host "  Created: $($structureResult.Created) folders" -ForegroundColor Green
Write-Host ""

Write-Step "Step 4/4: Creating configuration files..."
$configsCreated = 0

$extensionsJsonContent = "{`n  `"recommendations`": [`n"
$extensionsJsonContent += ($extensions | ForEach-Object { "    `"$($_.id)`"" }) -join ",`n"
$extensionsJsonContent += "`n  ]`n}"
if (New-ConfigFile -Path "$CurrentFolder\.vscode\extensions.json" -Content $extensionsJsonContent -Name "extensions.json") {
    $configsCreated++
}

$settingsJsonContent = @'
{
  "files.associations": {
    "*.mq5": "mql5",
    "*.mqh": "mql5",
    "*.mq4": "mql4"
  },
  "editor.tabSize": 3,
  "editor.insertSpaces": true,
  "editor.formatOnSave": true,
  "editor.bracketPairColorization.enabled": true,
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000,
  "workbench.colorTheme": "Monokai",
  "workbench.iconTheme": "material-icon-theme"
}
'@
if (New-ConfigFile -Path "$CurrentFolder\.vscode\settings.json" -Content $settingsJsonContent -Name "settings.json") {
    $configsCreated++
}

$mt5Path = "C:/Program Files/MetaTrader 5"
$cppPropertiesContent = "{`n"
$cppPropertiesContent += '  "configurations": [' + "`n"
$cppPropertiesContent += '    {' + "`n"
$cppPropertiesContent += '      "name": "Win32",' + "`n"
$cppPropertiesContent += '      "includePath": [' + "`n"
$cppPropertiesContent += '        "${workspaceFolder}/**",' + "`n"
$cppPropertiesContent += "        `"$mt5Path/MQL5/**`"`n"
$cppPropertiesContent += '      ],' + "`n"
$cppPropertiesContent += '      "defines": ["_DEBUG", "UNICODE", "_UNICODE"],' + "`n"
$cppPropertiesContent += "      `"compilerPath`": `"$mt5Path/metaeditor64.exe`",`n"
$cppPropertiesContent += '      "cStandard": "c17",' + "`n"
$cppPropertiesContent += '      "cppStandard": "c++17",' + "`n"
$cppPropertiesContent += '      "intelliSenseMode": "windows-msvc-x64"' + "`n"
$cppPropertiesContent += '    }' + "`n"
$cppPropertiesContent += '  ],' + "`n"
$cppPropertiesContent += '  "version": 4' + "`n"
$cppPropertiesContent += "}`n"
if (New-ConfigFile -Path "$CurrentFolder\.vscode\c_cpp_properties.json" -Content $cppPropertiesContent -Name "c_cpp_properties.json") {
    $configsCreated++
}

$tasksContent = "{`n"
$tasksContent += '  "version": "2.0.0",' + "`n"
$tasksContent += '  "tasks": [' + "`n"
$tasksContent += '    {' + "`n"
$tasksContent += '      "label": "Compile MQL5",' + "`n"
$tasksContent += '      "type": "shell",' + "`n"
$tasksContent += "      `"command`": `"`"$mt5Path/metaeditor64.exe`"`",`n"
$tasksContent += '      "args": ["/compile:${file}", "/log"],' + "`n"
$tasksContent += '      "group": {"kind": "build", "isDefault": true},' + "`n"
$tasksContent += '      "presentation": {"reveal": "always"}' + "`n"
$tasksContent += '    }' + "`n"
$tasksContent += '  ]' + "`n"
$tasksContent += "}`n"
if (New-ConfigFile -Path "$CurrentFolder\.vscode\tasks.json" -Content $tasksContent -Name "tasks.json") {
    $configsCreated++
}

$gitignoreContent = "*.ex5`n*.ex4`n*.log`n.DS_Store`nThumbs.db`n*.tmp`n*.bak`n"
if (New-ConfigFile -Path "$CurrentFolder\.gitignore" -Content $gitignoreContent -Name ".gitignore") {
    $configsCreated++
}

$projectName = Split-Path $CurrentFolder -Leaf
$readmeContent = "# $projectName`n`nMQL5 Expert Advisor Project`n`n"
$readmeContent += "## Structure`n`n"
$readmeContent += "- Experts/ - EA files`n"
$readmeContent += "- Include/ - Header files`n"
$readmeContent += "- Scripts/ - Utility scripts`n"
$readmeContent += "- Indicators/ - Custom indicators`n`n"
$readmeContent += "## Development`n`n"
$readmeContent += "Compile: Ctrl+Shift+B`n"
$readmeContent += "IntelliSense: Ctrl+Space`n"
$readmeContent += "Go to definition: F12`n`n"
$readmeContent += "Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n"
if (New-ConfigFile -Path "$CurrentFolder\README.md" -Content $readmeContent -Name "README.md") {
    $configsCreated++
}

Write-Host ""
Write-Host "  Created: $configsCreated config files" -ForegroundColor Green
Write-Host ""

Write-Header "Setup Complete!"
Write-Host "Project initialized in:" -ForegroundColor Cyan
Write-Host "  $CurrentFolder" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart VS Code (Ctrl+Shift+P -> Reload Window)" -ForegroundColor Yellow
Write-Host "  2. Start coding in Experts/ folder" -ForegroundColor Yellow
Write-Host "  3. Compile with Ctrl+Shift+B" -ForegroundColor Yellow
Write-Host ""

if ($OpenAfterSetup) {
    Write-Host "Opening VS Code..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    code $CurrentFolder
    Write-Host "[OK] VS Code opened!" -ForegroundColor Green
    Write-Host ""
}

Write-Host "======================================" -ForegroundColor Green
Write-Host " Project ready! Happy coding!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
