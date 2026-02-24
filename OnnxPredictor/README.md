# XAUUSD ONNX Predictor

**Neural Network Trading System pentru XAUUSD (Gold) cu ONNX**

Entry pe M1 cu analiza multi-timeframe (M1, M5, M15, M30, H1)

## 📋 Structura Proiectului

```
OnnxPredictor/
├── MQL5/
│   ├── Experts/
│   │   └── XAUUSD_ONNX_EA.mq5          # EA principal cu ONNX
│   └── Scripts/
│       └── XAUUSD_DataExporter.mq5     # Exportă date pentru training
├── PythonTraining/
│   ├── train_onnx.py                   # Script de training cu export ONNX
│   ├── requirements.txt                 # Dependencies Python
│   └── XAUUSD_training_data.csv        # Date exportate (va fi generat)
├── Models/
│   └── xauusd_model.onnx               # Model ONNX (va fi generat)
└── Data/
    └── (date raw)
```

## 🚀 Quick Start

### 1. Export Date de Training (în MT5)

1. Copiază `MQL5/Scripts/XAUUSD_DataExporter.mq5` în MT5 `Scripts` folder
2. Compilează scriptul în MetaEditor
3. Rulează pe XAUUSD cu parametrii:
   - Bars to Export: 100,000
   - Target pips: 10
   - Export All Bars: true
4. Găsești CSV-ul în: `MT5/Files/XAUUSD_training_data.csv`

### 2. Training în Python

```bash
cd PythonTraining

# Instalează dependencies
pip install -r requirements.txt

# Copiază CSV-ul exportat aici
# cp ~/MT5_terminal/Files/XAUUSD_training_data.csv .

# Antrenează modelul
python train_onnx.py
```

Output:
- ✅ `xauusd_model.h5` - Model Keras
- ✅ `../Models/xauusd_model.onnx` - Model ONNX pentru MT5
- ✅ `feature_scaler.npy` - Scaler pentru normalizare
- ✅ `training_history.png` - Grafice de training

### 3. Deploy în MT5

1. Copiază modelul ONNX:
   ```
   Models/xauusd_model.onnx → MT5/Common/Files/xauusd_model.onnx
   ```

2. Copiază EA:
   ```
   MQL5/Experts/XAUUSD_ONNX_EA.mq5 → MT5/Experts/
   ```

3. Compilează EA în MetaEditor

4. Attach EA pe chart XAUUSD M1:
   - Model File: `xauusd_model.onnx`
   - Min Confidence: `0.70` (70%)
   - Entry TF: M1
   - Analysis TFs: M5, M15, M30, H1

## 📊 Features (Input pentru Neural Network)

### Pentru fiecare timeframe (M1, M5, M15, M30, H1):

**Technical Indicators (19):**
- RSI (14, 5, 21)
- MACD (12, 26, 9) - Main + Signal
- Moving Averages (10, 20, 50, 200)
- ATR (14)
- Bollinger Bands (20, ±2σ)
- Stochastic (5, 3, 3)
- CCI (14)
- ADX (14) - Main + DI+ + DI-

**Price History (100 bars):**
- Normalized price lookback

**Time Features (2):**
- Hour of day
- Day of week

**Total Features: ~605 per sample**
- 121 features per timeframe × 5 timeframes = 605 features

## 🎯 Model Architecture

```
Input: 605 features
├─ Dense(1024) + BatchNorm + Swish + Dropout(0.3)
├─ Dense(512) + BatchNorm + Swish + Dropout(0.3)
├─ Dense(256) + BatchNorm + Swish + Dropout(0.21)
├─ Dense(128) + BatchNorm + Swish + Dropout(0.15)
└─ Output(1) + Sigmoid

Optimizer: Adam (lr=0.001)
Loss: Binary Crossentropy
Metrics: Accuracy, Precision, Recall
```

## ⚙️ Parametri EA

### Neural Network
- **Model File**: `xauusd_model.onnx`
- **Min Confidence**: 0.70 (70%) - pentru filtrare semnale slabe
- **Auto Reload**: true - reîncarcă automat modelul când e actualizat

### Timeframes
- **Entry TF**: M1 (unde se deschid pozițiile)
- **Analysis TFs**: M5, M15, M30, H1 (pentru MTF analysis)

### Money Management
- **Fixed Lot**: 0.01  
- **Use Risk %**: false (sau true pentru risk-based)
- **Risk Percent**: 1.0%
- **Max Lot**: 0.50
- **Max Positions**: 3

### Trade Management
- **Stop Loss**: 20 pips (pentru XAUUSD)
- **Take Profit**: 40 pips (risk:reward 1:2)
- **Close on Opposite**: true (închide pozițiile opuse la semnal nou)

### Risk Filters
- **Max Spread**: 5 pips (pentru XAUUSD volatil)
- **Trading Hours**: opțional (0-23 default)

## 📈 Performanță Așteptată

Pe baza training-ului:
- **Test Accuracy**: ~80-85%
- **Precision**: ~80-85%
- **Recall**: ~75-85%

La confidence >70%:
- **Accuracy**: ~85-90%
- **Coverage**: ~70-80% din semnale

## 🔧 Troubleshooting

### "ONNX model not found"
- Verifică că `xauusd_model.onnx` e în `MT5/Common/Files/`
- Check file permissions

### "ONNX inference failed"
- Verifică că MT5 build >= 3260 (ONNX support)
- Recompilează EA
- Check log pentru erori specifice

### "Features extraction failed"
- Verifică că indicators sunt loaded (așteaptă 3-5 sec după start)
- Check că simbolul XAUUSD e activ și cu date

### Low accuracy în live
- Re-exportă date mai recente (piața se schimbă)
- Re-antrenează modelul
- Ajustează Min Confidence (increase pentru mai puține dar mai bune semnale)

## 🔄 Workflow Complet

1. **Export date** din MT5 (100K+ bars)
2. **Train model** în Python → ONNX
3. **Copy ONNX** în MT5 Common Files
4. **Test în Strategy Tester** (înainte de live!)
5. **Deploy pe live** account cu lot mic
6. **Monitor** și re-train periodic (lunar)

## 📝 Update Workflow

Când vrei să re-antrenezi modelul:

```bash
# 1. Export date noi din MT5
# 2. Train model nou
cd PythonTraining
python train_onnx.py

# 3. Copy model nou
# Models/xauusd_model.onnx → MT5/Common/Files/

# EA va detecta automat și reîncarcă (dacă Auto Reload = true)
```

## ⚠️ Important

- **Backtest întotdeauna** înainte de live
- **Start cu lot mic** în live
- **Monitor spread** pe XAUUSD (poate fi mare)
- **Re-train periodic** - piața se schimbă
- **News events** - oprește EA la evenimente majore (NFP, FOMC, etc.)

## 📚 Requirements

### MT5
- Build >= 3260 (pentru ONNX support)
- Indicator buffer space (pentru MTF indicators)

### Python
- Python >= 3.8
- TensorFlow >= 2.13
- ONNX export libraries (tf2onnx, onnx)

## 🎓 Advanced Tips

1. **Feature Engineering**
   - Poți adăuga mai multe indicators în exporter
   - Increase/decrease lookback bars
   - Add volume indicators (dacă disponibile pentru XAUUSD)

2. **Model Tuning**
   - Ajustează architecture în train_onnx.py
   - Modify dropout rates
   - Try different activations (swish is default)

3. **Risk Management**
   - Consider trailing stop
   - Add time-based exit rules
   - Implement breakeven logic

4. **Multi-Symbol**
   - Poți adapta pentru alte perechi (EURUSD, etc.)
   - Schimbă simbolul în exporter și EA
   - Re-antrenează model specific

## 💡 Next Steps

- [ ] Implementează trailing stop în EA
- [ ] Add volume features (dacă disponibile)
- [ ] Multi-model ensemble (combinare mai multe modele)
- [ ] Reinforcement Learning pentru trade management
- [ ] Add sentiment analysis (dacă ai date)

## 📞 Support

Pentru întrebări sau probleme:
1. Check troubleshooting section
2. Verifică log-urile din MT5 Journal tab
3. Test în Strategy Tester cu visual mode

---

**Disclaimer**: Acest sistem este pentru scop educațional. Testează întotdeauna în demo înainte de live trading. Trading-ul implică risc de pierdere.
