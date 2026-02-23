# Deploy Neural Predictor to MT5
# This script copies all necessary files to MT5 installation directory

Write-Host "Neural Predictor - MT5 Deployment Script" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Find MT5 Data Directory
$mt5DataPath = "$env:APPDATA\MetaQuotes\Terminal"

if (!(Test-Path $mt5DataPath)) {
   Write-Host "ERROR: MT5 Terminal directory not found" -ForegroundColor Red
   exit 1
}

# Find terminal instances
$terminals = Get-ChildItem -Path $mt5DataPath -Directory | Where-Object { $_.Name -notmatch "Common" }

if ($terminals.Count -eq 0) {
   Write-Host "ERROR: No MT5 terminal instances found" -ForegroundColor Red
   exit 1
}

# Select terminal
if ($terminals.Count -gt 1) {
   Write-Host "Multiple MT5 instances found:" -ForegroundColor Yellow
   for ($i = 0; $i -lt $terminals.Count; $i++) {
      Write-Host "  [$i] $($terminals[$i].Name)" -ForegroundColor White
   }
   $choice = Read-Host "Select instance (0-$($terminals.Count-1))"
   $terminal = $terminals[$choice]
}
else {
   $terminal = $terminals[0]
}

$mt5MQL5Path = Join-Path $terminal.FullName "MQL5"

Write-Host ""
Write-Host "Target: $mt5MQL5Path" -ForegroundColor Green
Write-Host ""

# Create directories
$directories = @(
   "$mt5MQL5Path\Experts",
   "$mt5MQL5Path\Scripts",
   "$mt5MQL5Path\Include"
)

foreach ($dir in $directories) {
   if (!(Test-Path $dir)) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
   }
}

# Copy Experts
Write-Host "Copying Experts..." -ForegroundColor Cyan
Copy-Item "$PSScriptRoot\MQL5\Experts\NeuralPredictorEA.mq5" -Destination "$mt5MQL5Path\Experts\" -Force
Write-Host "  OK NeuralPredictorEA.mq5" -ForegroundColor Green

# Copy Scripts
Write-Host "Copying Scripts..." -ForegroundColor Cyan
Copy-Item "$PSScriptRoot\MQL5\Scripts\NNTrainer.mq5" -Destination "$mt5MQL5Path\Scripts\" -Force
Copy-Item "$PSScriptRoot\MQL5\Scripts\MT5DataExporter.mq5" -Destination "$mt5MQL5Path\Scripts\" -Force
Write-Host "  OK NNTrainer.mq5" -ForegroundColor Green
Write-Host "  OK MT5DataExporter.mq5" -ForegroundColor Green

# Copy Include files
Write-Host "Copying Include files..." -ForegroundColor Cyan
Copy-Item "$PSScriptRoot\MQL5\Include\NNPredictorLib.mqh" -Destination "$mt5MQL5Path\Include\" -Force
Write-Host "  OK NNPredictorLib.mqh" -ForegroundColor Green

# Copy NeuroNetworksBook framework
Write-Host "Copying NeuroNetworksBook..." -ForegroundColor Cyan
$nnbSource = "$PSScriptRoot\MQL5\Include\NeuroNetworksBook"
if (Test-Path $nnbSource) {
   Copy-Item -Path $nnbSource -Destination "$mt5MQL5Path\Include\" -Recurse -Force
   Write-Host "  OK NeuroNetworksBook framework" -ForegroundColor Green
}
else {
   Write-Host "  WARNING: NeuroNetworksBook not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next: Open MT5 MetaEditor and compile NeuralPredictorEA.mq5" -ForegroundColor Yellow
Write-Host ""
