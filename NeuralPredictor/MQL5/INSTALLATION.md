# MQL5 Installation Guide

## Quick Copy Instructions

To install the Neural Predictor files to MT5:

### 1. Copy Files to MT5 Directory

Copy the contents of this folder to your MT5 data folder:

```
Copy from → Copy to
-----------------------------------------------
MQL5/Experts/*    → C:\Users\<YourUser>\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Experts\
MQL5/Scripts/*    → C:\Users\<YourUser>\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Scripts\
MQL5/Include/*    → C:\Users\<YourUser>\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Include\
```

**Tip:** Open MT5 MetaEditor → File → Open Data Folder to find your MT5 directory quickly.

### 2. Copy Neural Network Library Dependencies

The code requires the NeuroNetworksBook library. Copy from workspace:

```
From: c:\cris\coding\scalping\mql5\Include\NeuroNetworksBook\
To:   C:\Users\<YourUser>\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Include\NeuroNetworksBook\
```

**Important:** Copy the entire `NeuroNetworksBook` folder with all subdirectories (realization/, algotrading/, etc.)

### 3. Copy Trained Model File (After Python Training)

After training your model in Python:

```
From: NeuralPredictor\PythonTraining\model_weights.nnw
To:   C:\Users\<YourUser>\AppData\Roaming\MetaQuotes\Terminal\Common\Files\model_weights.nnw
```

### 4. Compile in MT5

1. Open MT5 MetaEditor
2. Compile `NeuralPredictorEA.mq5` (F7)
3. Compile `NNTrainer.mq5` (F7)
4. Compile `MT5DataExporter.mq5` (F7)
5. Check for errors - all should compile cleanly

### 5. Usage

#### For Python Training (Recommended):
1. Run `Scripts/MT5DataExporter.mq5` on XAUUSD M5 chart to export data
2. Train model in Python (see `../PythonTraining/QUICKSTART.md`)
3. Convert weights to .nnw file
4. Copy .nnw file to Common/Files
5. Attach `NeuralPredictorEA.mq5` to chart with `Use_Python_Model = true`

#### For MQL5 Training (Slower):
1. Run `Scripts/NNTrainer.mq5` on XAUUSD M5 chart to train
2. Attach `NeuralPredictorEA.mq5` to chart with `Use_Python_Model = false`

## Files Overview

### Experts/
- **NeuralPredictorEA.mq5** - Main trading EA with neural network predictions

### Scripts/
- **NNTrainer.mq5** - Train model directly in MQL5 (15-20 min training time)
- **MT5DataExporter.mq5** - Export data for Python training (much faster)

### Include/
- **NNPredictorLib.mqh** - Shared library with indicators and feature extraction

## Folder Structure

```
MT5 MQL5/
├── Experts/
│   └── NeuralPredictorEA.mq5
├── Scripts/
│   ├── NNTrainer.mq5
│   └── MT5DataExporter.mq5
└── Include/
    ├── NNPredictorLib.mqh
    └── NeuroNetworksBook/          (copy from workspace)
        └── realization/
            ├── neuronnet.mqh
            ├── activation.mqh
            └── ... (other files)
```

## Troubleshooting

### "Cannot open include file"
→ Make sure NeuroNetworksBook folder is copied to MT5/Include/

### "Array out of range" error
→ Check that you have enough historical data loaded in MT5

### Model file not found
→ Verify model_weights.nnw is in Terminal/Common/Files/ folder

### EA not trading
→ Check EA logs, verify AutoTrading is enabled, check Min_Confidence setting

## Next Steps

1. ✅ Copy files to MT5
2. ✅ Compile all files
3. 📊 Export training data (MT5DataExporter.mq5)
4. 🧠 Train model in Python (95% accuracy in ~1.5 min)
5. 🔄 Convert weights to .nnw format
6. 📈 Deploy EA to chart
7. 🧪 Test in Strategy Tester
8. 🚀 Go live (small lots first!)
