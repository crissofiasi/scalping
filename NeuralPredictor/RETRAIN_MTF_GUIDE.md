# Multi-Timeframe Retraining Guide

## Current Issue
Your trained model has **71 features** (single timeframe) but your EA is configured for **multi-timeframe analysis** which generates **213 features** (71 × 3 timeframes). This causes a dimension mismatch error.

## Solution: Retrain with Multi-Timeframe Data

### Step 1: Export Multi-Timeframe Data (On VPS)

1. **Pull latest changes on VPS:**
   ```bash
   cd /path/to/scalping
   git pull
   ```

2. **Copy updated data exporter to MT5:**
   - File: `NeuralPredictor/MQL5/Scripts/MT5DataExporter.mq5`
   - Location: Copy to your MT5 → `MQL5/Scripts/`
   - Compile in MetaEditor (F7)

3. **Run the data exporter:**
   - In MT5, drag `MT5DataExporter` script onto an M5 chart (EURUSD or XAUUSD recommended)
   - **Verify settings:**
     - ✅ `Input_Use_Multi_Timeframe = true`
     - ✅ `Input_Timeframe_2 = M15`
     - ✅ `Input_Timeframe_3 = M30`
     - ✅ `Input_Include_Parameters = true`
     - ✅ `Input_Export_Bars = 10000` (or more for better training)
   - Click OK and wait (2-5 minutes)
   - Output: `nn_training_data.csv` in MT5 Common Files folder

4. **Verify the export:**
   - Open CSV file
   - Count columns (should be **214 columns**: 213 features + 1 label)
   - **Feature breakdown:**
     - TF1 (M5): 71 features (8 indicators + 61 lookback + 2 time)
     - TF2 (M15): 71 features
     - TF3 (M30): 71 features
     - Parameters: 18 features
     - Label: 1 column (BUY/SELL)
     - **Total: 213 + 1 = 214 columns**

5. **Copy CSV back:**
   - From: `C:\Users\YourUser\AppData\Roaming\MetaQuotes\Terminal\Common\Files\nn_training_data.csv`
   - To: Your repository → `NeuralPredictor/PythonTraining/nn_training_data.csv`

### Step 2: Upload CSV to Repository

```bash
cd /path/to/scalping
git add NeuralPredictor/PythonTraining/nn_training_data.csv
git commit -m "Add multi-timeframe training data (213 features)"
git push
```

### Step 3: Pull and Retrain (Here)

Once you've pushed the CSV, I'll:
1. Pull the new CSV file
2. Run the Python training script
3. Generate new model with 213-feature architecture
4. Convert weights to MQL5 format
5. Commit and push the trained model

### Expected Results After Retraining

**New Model Architecture:**
```
Input: 213 features (3 timeframes × 71 features/TF)
  ↓
Layer 1: 426 neurons (Swish + BatchNorm + Dropout)
  ↓
Layer 2: 213 neurons (Swish + BatchNorm + Dropout)
  ↓
Layer 3: 106 neurons (Swish + BatchNorm + Dropout)
  ↓
Output: 1 neuron (Sigmoid) → BUY/SELL probability
```

**EA Configuration:**
- ✅ `Input_Use_Multi_Timeframe = true`
- ✅ `Input_Timeframe_2 = PERIOD_M15`
- ✅ `Input_Timeframe_3 = PERIOD_M30`
- ✅ Feature count will match: 213 in both training and prediction

## Benefits of Multi-Timeframe Analysis

1. **Context from multiple time scales:**
   - M5: Fast signals and entry timing
   - M15: Trend confirmation
   - M30: Major trend direction

2. **Reduced false signals:**
   - Model sees if M5 signal aligns with M15/M30 trends

3. **Better accuracy:**
   - More information = better predictions
   - Typical improvement: 2-5% higher accuracy

## Alternative: Use Single Timeframe

If you prefer to keep single timeframe (faster predictions, simpler):

**In EA (NeuralPredictorEA.mq5):**
```mql5
input bool Input_Use_Multi_Timeframe = false;  // Disable MTF
```

Then your current trained model (71 features) will work fine.

## Questions?

- **Q: How long will retraining take?**
  - A: 10-20 minutes (depends on data size and CPU/GPU)

- **Q: Will performance improve?**
  - A: Typically yes, 2-5% better accuracy with MTF

- **Q: Can I change timeframes later?**
  - A: Yes, but you'll need to re-export data and retrain

---

**Ready to proceed?** 
Upload the new CSV and let me know when it's pushed!
