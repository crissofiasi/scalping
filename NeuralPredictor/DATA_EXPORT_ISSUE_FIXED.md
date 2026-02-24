# Data Export Issue - FIXED!

## What Was Wrong

You set `Input_Export_Bars = 100000` but only got **398 samples**. Here's why:

### **Bug #1: Hardcoded Lookback Bars**
```mql5
// OLD (WRONG):
if(!g_lib.PrepareFeatures(features, i, 15))  // Only 15 bars!

// NEW (FIXED):
if(!g_lib.PrepareFeatures(features, i, 61))  // 61 bars to match model
```

**Impact:** 
- CSV header had 15 price columns (wrong)
- Features extracted with 15 bars (wrong)
- Model expects 61 lookback bars (mismatch!)

### **Bug #2: Labeling Too Strict**
```mql5
// OLD:
Input_Lookforward_Bars = 15  // Only 75 minutes on M5

// NEW:
Input_Lookforward_Bars = 50  // 250 minutes on M5
```

**Why This Matters:**

The labeling logic **requires a clean directional move:**
- **BUY label:** Price moves UP 10 pips without moving DOWN 10 pips
- **SELL label:** Price moves DOWN 10 pips without moving UP 10 pips
- **Skipped:** Any bar where both directions hit 10 pips (choppy market)

With only **15 bars lookforward** (75 minutes):
- Very few bars show a clean 10-pip move in one direction
- Most M5 bars in ranging markets get skipped
- Result: **Only 398 out of 100,000 bars qualified (0.4%)**

With **50 bars lookforward** (250 minutes):
- More time for the target move to develop
- More samples will qualify
- Expected: **5,000-15,000 samples (5-15%)**

### **Bug #3: Header Column Count Mismatch**
```mql5
// OLD:
for(int i = 1; i <= 15; i++)  // 15 columns

// NEW:
for(int i = 1; i <= 61; i++)  // 61 columns
```

**Impact:** CSV header didn't match the actual feature data!

---

## What's Been Fixed

✅ **Lookback bars:** 15 → **61** (matches model requirement)  
✅ **Lookforward bars:** 15 → **50** (more samples will qualify)  
✅ **Header columns:** 15 → **61** (matches feature data)

---

## Expected Results After Re-Export

### **Single Timeframe Mode** (`Input_Use_Multi_Timeframe = false`):
- **Columns:** 72 (71 features + 1 label)
  - 8 indicators
  - 61 lookback price bars ✅ **FIXED**
  - 2 time features
  - 1 label column

### **Multi-Timeframe Mode** (`Input_Use_Multi_Timeframe = true`):
- **Columns:** 214 (213 features + 1 label)
  - TF1 (M5): 71 features (8 indicators + 61 lookback + 2 time)
  - TF2 (M15): 71 features (8 indicators + 61 lookback)
  - TF3 (M30): 71 features (8 indicators + 61 lookback)
  - 1 label column

### **Sample Count:**
- **Before:** 398 samples from 100,000 bars (0.4%)
- **After:** 5,000-15,000 samples (5-15%) ← **Much better!**

---

## Next Steps on VPS

1. **Pull latest changes:**
   ```bash
   cd /path/to/scalping
   git pull
   ```

2. **Copy updated exporter to MT5:**
   - File: `NeuralPredictor/MQL5/Scripts/MT5DataExporter.mq5`
   - Copy to: `MT5/MQL5/Scripts/`
   - **Compile in MetaEditor (F7)**

3. **Run the exporter:**
   - Drag script onto M5 chart
   - **Settings:**
     - ✅ `Input_Export_Bars = 100000` (or more)
     - ✅ `Input_Use_Multi_Timeframe = true` ← **Enable MTF!**
     - ✅ `Input_Timeframe_2 = M15`
     - ✅ `Input_Timeframe_3 = M30`
     - ✅ `Input_Target_Move_Pips = 10.0`
     - ✅ `Input_Lookforward_Bars = 50` ← **Auto-set now**
     - ✅ `Input_Include_Parameters = true`
   - Click OK and wait (5-10 minutes for 100K bars)

4. **Verify the export:**
   ```
   Expected with MTF enabled:
   - Rows: 5,000-15,000 (instead of 398!)
   - Columns: 214 (instead of 72)
   - Column headers: RSI_TF1, RSI_TF2, RSI_TF3, etc.
   ```

5. **Push new data:**
   ```bash
   git add NeuralPredictor/PythonTraining/nn_training_data.csv
   git commit -m "Multi-timeframe training data (100K bars, 5K+ samples)"
   git push
   ```

Then I'll retrain with the proper data! 🚀

---

## Why the Labeling is Designed This Way

The strict labeling ensures **high-quality training data:**

✅ **Only clear directional moves are labeled**  
✅ **Avoids choppy/ranging bars that confuse the model**  
✅ **Model learns clean patterns, not market noise**

The tradeoff:
- ❌ Fewer training samples
- ✅ But higher quality data = better predictions

With 100,000+ bars and 50 lookforward, you'll still get 5,000-15,000 **high-quality samples** - more than enough for training!
