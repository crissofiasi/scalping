//+------------------------------------------------------------------+
//|                                        XAUUSD_ONNX_EA.mq5         |
//|                     ONNX-Based Gold Trading Expert Advisor        |
//|                              M1 Entry with MTF Analysis           |
//+------------------------------------------------------------------+
#property copyright "ONNX XAUUSD Predictor"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "═══════════ General Settings ═══════════"
input string             Input_Symbol = "XAUUSD";                   // Symbol
input int                Input_Magic_Number = 20260224;             // Magic Number
input string             Input_Comment = "ONNX_XAUUSD";             //Trade Comment
input bool               Input_Enable_Trading = true;               // Enable Trading

input group "═══════════ ONNX Model Settings ═══════════"
input string             Input_Model_File = "xauusd_model.onnx";   // ONNX Model File
input string             Input_Scaler_File = "feature_scaler.npy"; // Feature Scaler File
input double             Input_Min_Confidence = 0.70;               // Min Confidence (0.5-1.0)
input bool               Input_Auto_Reload = true;                  // Auto-Reload Model

input group "═══════════ Timeframe Settings ═══════════"
input ENUM_TIMEFRAMES    Input_Entry_TF = PERIOD_M1;                // Entry Timeframe (M1)
input ENUM_TIMEFRAMES    Input_TF2 = PERIOD_M5;                     // Analysis TF2
input ENUM_TIMEFRAMES    Input_TF3 = PERIOD_M15;                    // Analysis TF3
input ENUM_TIMEFRAMES    Input_TF4 = PERIOD_M30;                    // Analysis TF4
input ENUM_TIMEFRAMES    Input_TF5 = PERIOD_H1;                     // Analysis TF5

input group "═══════════ Feature Parameters ═══════════"
input int                Input_Lookback = 100;                      // Lookback Bars
input int                Input_RSI = 14;                            // RSI Period
input int                Input_RSI_Fast = 5;                        // RSI Fast
input int                Input_RSI_Slow = 21;                       // RSI Slow
input int                Input_MACD_Fast = 12;                      // MACD Fast
input int                Input_MACD_Slow = 26;                      // MACD Slow
input int                Input_MACD_Signal = 9;                     // MACD Signal
input int                Input_MA_Fast = 10;                        // MA Fast
input int                Input_MA_Medium = 20;                      // MA Medium
input int                Input_MA_Slow = 50;                        // MA Slow
input int                Input_MA_XSlow = 200;                      // MA XSlow
input int                Input_ATR = 14;                            // ATR Period
input int                Input_BB = 20;                             // BB Period
input double             Input_BB_Dev = 2.0;                        // BB Deviation
input int                Input_Stoch_K = 5;                         // Stochastic %K
input int                Input_Stoch_D = 3;                         // Stochastic %D
input int                Input_Stoch_Slow = 3;                      // Stochastic Slowing
input int                Input_CCI = 14;                            // CCI Period
input int                Input_ADX = 14;                            // ADX Period

input group "═══════════ Money Management ═══════════"
input double             Input_Fixed_Lot = 0.01;                    // Fixed Lot Size
input bool               Input_Use_Risk_Percent = false;            // Use Risk %
input double             Input_Risk_Percent = 1.0;                  // Risk Percent
input double             Input_Max_Lot = 0.50;                      // Max Lot Size
input int                Input_Max_Positions = 3;                   // Max Open Positions

input group "═══════════ Trade Management ═══════════"
input bool               Input_Use_SL = true;                       // Use Stop Loss
input double             Input_SL_Pips = 20.0;                      // Stop Loss (pips)
input bool               Input_Use_TP = true;                       // Use Take Profit
input double             Input_TP_Pips = 40.0;                      // Take Profit (pips)
input bool               Input_Close_Opposite = true;               // Close on Opposite Signal

input group "═══════════ Risk Filters ═══════════"
input bool               Input_Use_Max_Spread = true;               // Use Max Spread Filter
input double             Input_Max_Spread = 5.0;                    // Max Spread (pips)
input bool               Input_Use_Trading_Hours = false;           // Use Trading Hours
input int                Input_Start_Hour = 0;                      // Start Hour
input int                Input_End_Hour = 23;                       // End Hour

input group "═══════════ Debug ═══════════"
input bool               Input_Debug = false;                       // Debug Mode
input bool               Input_Show_Predictions = true;             // Show Predictions

//--- Global Variables
CTrade               m_trade;
long                 m_onnx_handle = INVALID_HANDLE;
datetime             m_last_bar_time = 0;
datetime             m_model_last_modified = 0;

//--- Feature scaler (mean and scale for normalization)
double               m_scaler_mean[];
double               m_scaler_scale[];
bool                 m_scaler_loaded = false;

//--- Indicator handles for all timeframes
struct SIndicators
{
   int rsi, rsi_fast, rsi_slow;
   int macd, ma_fast, ma_medium, ma_slow, ma_xslow;
   int atr, bb, stoch, cci, adx;
};

SIndicators g_indicators[5];
ENUM_TIMEFRAMES g_timeframes[5];

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("==================================================");
   Print("XAUUSD ONNX Expert Advisor Initializing...");
   Print("==================================================");
   
   //--- Setup trade
   m_trade.SetExpertMagicNumber(Input_Magic_Number);
   m_trade.SetDeviationInPoints(30);
   m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   //--- Setup timeframes
   g_timeframes[0] = Input_Entry_TF;
   g_timeframes[1] = Input_TF2;
   g_timeframes[2] = Input_TF3;
   g_timeframes[3] = Input_TF4;
   g_timeframes[4] = Input_TF5;
   
   Print("Timeframes: ", EnumToString(g_timeframes[0]), ", ",
         EnumToString(g_timeframes[1]), ", ",
         EnumToString(g_timeframes[2]), ", ",
         EnumToString(g_timeframes[3]), ", ",
         EnumToString(g_timeframes[4]));
   
   //--- Initialize indicators
   if(!InitializeIndicators())
   {
      Print("ERROR: Failed to initialize indicators");
      return INIT_FAILED;
   }
   
   Print("✅ Indicators initialized");
   
   //--- Load feature scaler
   if(!LoadScaler())
   {
      Print("WARNING: Failed to load feature scaler - predictions may be inaccurate");
      Print("Make sure ", Input_Scaler_File, " is in Common Files folder");
   }
   else
   {
      Print("✅ Feature scaler loaded");
   }
   
   //--- Load ONNX model
   if(!LoadOnnxModel())
   {
      Print("ERROR: Failed to load ONNX model");
      Print("Make sure ", Input_Model_File, " is in Common Files folder");
      return INIT_FAILED;
   }
   
   Print("✅ ONNX model loaded successfully");
   
   //--- Initialize bar time
   m_last_bar_time = iTime(Input_Symbol, Input_Entry_TF, 0);
   
   Print("==================================================");
   Print("✅ EA Initialized Successfully");
   Print("Entry TF: M1, Min Confidence: ", Input_Min_Confidence);
   Print("==================================================");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release ONNX model
   if(m_onnx_handle != INVALID_HANDLE)
   {
      OnnxRelease(m_onnx_handle);
      Print("ONNX model released");
   }
   
   //--- Release indicators
   ReleaseIndicators();
   
   Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!Input_Enable_Trading) return;
   
   //--- Check for new bar on entry timeframe
   datetime current_bar_time = iTime(Input_Symbol, Input_Entry_TF, 0);
   if(current_bar_time == m_last_bar_time)
      return;
   
   m_last_bar_time = current_bar_time;
   
   //--- Auto-reload model if updated
   if(Input_Auto_Reload)
      CheckAndReloadModel();
   
   //--- Apply filters
   if(!PassFilters())
      return;
   
   //--- Get prediction
   double confidence;
   int signal = GetPrediction(confidence);
   
   if(Input_Show_Predictions)
   {
      if(signal == 1)
         Comment(StringFormat("Prediction: BUY (%.1f%%)", confidence * 100));
      else if(signal == -1)
         Comment(StringFormat("Prediction: SELL (%.1f%%)", confidence * 100));
      else
         Comment("Prediction: No signal");
   }
   
   //--- Check confidence threshold
   if(confidence < Input_Min_Confidence)
   {
      if(Input_Debug)
         Print("Low confidence: ", confidence, " < ", Input_Min_Confidence);
      return;
   }
   
   //--- Check max positions
   if(CountOpenPositions() >= Input_Max_Positions)
   {
      if(Input_Debug)
         Print("Max positions reached: ", CountOpenPositions());
      return;
   }
   
   //--- Execute trades based on signal
   if(signal == 1) // BUY
   {
      if(Input_Close_Opposite)
         ClosePositionsByType(POSITION_TYPE_SELL);
      
      if(CountOpenPositions() < Input_Max_Positions)
         OpenTrade(ORDER_TYPE_BUY, confidence);
   }
   else if(signal == -1) // SELL
   {
      if(Input_Close_Opposite)
         ClosePositionsByType(POSITION_TYPE_BUY);
      
      if(CountOpenPositions() < Input_Max_Positions)
         OpenTrade(ORDER_TYPE_SELL, confidence);
   }
}

//+------------------------------------------------------------------+
//| Initialize all indicators for all timeframes                     |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
   for(int i = 0; i < 5; i++)
   {
      ENUM_TIMEFRAMES tf = g_timeframes[i];
      
      g_indicators[i].rsi = iRSI(Input_Symbol, tf, Input_RSI, PRICE_CLOSE);
      g_indicators[i].rsi_fast = iRSI(Input_Symbol, tf, Input_RSI_Fast, PRICE_CLOSE);
      g_indicators[i].rsi_slow = iRSI(Input_Symbol, tf, Input_RSI_Slow, PRICE_CLOSE);
      g_indicators[i].macd = iMACD(Input_Symbol, tf, Input_MACD_Fast, Input_MACD_Slow, Input_MACD_Signal, PRICE_CLOSE);
      g_indicators[i].ma_fast = iMA(Input_Symbol, tf, Input_MA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      g_indicators[i].ma_medium = iMA(Input_Symbol, tf, Input_MA_Medium, 0, MODE_EMA, PRICE_CLOSE);
      g_indicators[i].ma_slow = iMA(Input_Symbol, tf, Input_MA_Slow, 0, MODE_SMA, PRICE_CLOSE);
      g_indicators[i].ma_xslow = iMA(Input_Symbol, tf, Input_MA_XSlow, 0, MODE_SMA, PRICE_CLOSE);
      g_indicators[i].atr = iATR(Input_Symbol, tf, Input_ATR);
      g_indicators[i].bb = iBands(Input_Symbol, tf, Input_BB, 0, Input_BB_Dev, PRICE_CLOSE);
      g_indicators[i].stoch = iStochastic(Input_Symbol, tf, Input_Stoch_K, Input_Stoch_D, Input_Stoch_Slow, MODE_SMA, STO_LOWHIGH);
      g_indicators[i].cci = iCCI(Input_Symbol, tf, Input_CCI, PRICE_TYPICAL);
      g_indicators[i].adx = iADX(Input_Symbol, tf, Input_ADX);
      
      if(g_indicators[i].rsi == INVALID_HANDLE || g_indicators[i].macd == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create indicators for TF: ", EnumToString(tf));
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Release all indicator handles                                    |
//+------------------------------------------------------------------+
void ReleaseIndicators()
{
   for(int i = 0; i < 5; i++)
   {
      if(g_indicators[i].rsi != INVALID_HANDLE) IndicatorRelease(g_indicators[i].rsi);
      if(g_indicators[i].rsi_fast != INVALID_HANDLE) IndicatorRelease(g_indicators[i].rsi_fast);
      if(g_indicators[i].rsi_slow != INVALID_HANDLE) IndicatorRelease(g_indicators[i].rsi_slow);
      if(g_indicators[i].macd != INVALID_HANDLE) IndicatorRelease(g_indicators[i].macd);
      if(g_indicators[i].ma_fast != INVALID_HANDLE) IndicatorRelease(g_indicators[i].ma_fast);
      if(g_indicators[i].ma_medium != INVALID_HANDLE) IndicatorRelease(g_indicators[i].ma_medium);
      if(g_indicators[i].ma_slow != INVALID_HANDLE) IndicatorRelease(g_indicators[i].ma_slow);
      if(g_indicators[i].ma_xslow != INVALID_HANDLE) IndicatorRelease(g_indicators[i].ma_xslow);
      if(g_indicators[i].atr != INVALID_HANDLE) IndicatorRelease(g_indicators[i].atr);
      if(g_indicators[i].bb != INVALID_HANDLE) IndicatorRelease(g_indicators[i].bb);
      if(g_indicators[i].stoch != INVALID_HANDLE) IndicatorRelease(g_indicators[i].stoch);
      if(g_indicators[i].cci != INVALID_HANDLE) IndicatorRelease(g_indicators[i].cci);
      if(g_indicators[i].adx != INVALID_HANDLE) IndicatorRelease(g_indicators[i].adx);
   }
}

//+------------------------------------------------------------------+
//| Load ONNX model                                                   |
//+------------------------------------------------------------------+
bool LoadOnnxModel()
{
   //--- Release existing model
   if(m_onnx_handle != INVALID_HANDLE)
   {
      OnnxRelease(m_onnx_handle);
      m_onnx_handle = INVALID_HANDLE;
   }
   
   //--- Load model
   m_onnx_handle = OnnxCreateFromFile(Input_Model_File, ONNX_DEFAULT);
   
   if(m_onnx_handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to load ONNX model: ", Input_Model_File);
      Print("Error code: ", GetLastError());
      return false;
   }
   
   //--- Get model info
   long input_count = 0, output_count = 0;
   OnnxGetInputCount(m_onnx_handle, input_count);
   OnnxGetOutputCount(m_onnx_handle, output_count);
   
   Print("ONNX Model Info:");
   Print("  Inputs: ", input_count);
   Print("  Outputs: ", output_count);
   
   //--- Store modification time
   m_model_last_modified = (datetime)FileGetInteger(Input_Model_File, FILE_MODIFY_DATE, FILE_COMMON);
   
   return true;
}

//+------------------------------------------------------------------+
//| Load feature scaler                                              |
//+------------------------------------------------------------------+
bool LoadScaler()
{
   //--- This is simplified - in reality you'd need to read the .npy file
   //--- For now, we'll just set flag and assume features are pre-normalized
   //--- Or you can export scaler params to a simple text file
   
   m_scaler_loaded = false; // Set to true if you implement scaler loading
   return false; // Return true when implemented
}

//+------------------------------------------------------------------+
//| Check and reload model if updated                                 |
//+------------------------------------------------------------------+
void CheckAndReloadModel()
{
   if(!FileIsExist(Input_Model_File, FILE_COMMON))
      return;
   
   datetime file_time = (datetime)FileGetInteger(Input_Model_File, FILE_MODIFY_DATE, FILE_COMMON);
   
   if(file_time > m_model_last_modified)
   {
      Print("Model file updated. Reloading...");
      if(LoadOnnxModel())
         Print("✅ Model reloaded successfully");
      else
         Print("❌ Failed to reload model");
   }
}

//+------------------------------------------------------------------+
//| Extract features for current bar                                  |
//+------------------------------------------------------------------+
bool ExtractFeatures(float &features[])
{
   int total_features = (19 + Input_Lookback + 2) * 5; // features per TF * 5 TFs
   ArrayResize(features, total_features);
   int idx = 0;
   
   //--- Extract for each timeframe
   for(int tf_idx = 0; tf_idx < 5; tf_idx++)
   {
      ENUM_TIMEFRAMES tf = g_timeframes[tf_idx];
      int bar = 1; // Previous closed bar
      
      //--- Get indicator values
      double rsi[], rsi_fast[], rsi_slow[], macd_main[], macd_signal[];
      double ma_fast[], ma_medium[], ma_slow[], ma_xslow[], atr[];
      double bb_upper[], bb_middle[], bb_lower[];
      double stoch_main[], stoch_signal[], cci[], adx_main[], adx_plus[], adx_minus[];
      
      if(CopyBuffer(g_indicators[tf_idx].rsi, 0, bar, 1, rsi) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].rsi_fast, 0, bar, 1, rsi_fast) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].rsi_slow, 0, bar, 1, rsi_slow) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].macd, MAIN_LINE, bar, 1, macd_main) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].macd, SIGNAL_LINE, bar, 1, macd_signal) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].ma_fast, 0, bar, 1, ma_fast) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].ma_medium, 0, bar, 1, ma_medium) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].ma_slow, 0, bar, 1, ma_slow) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].ma_xslow, 0, bar, 1, ma_xslow) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].atr, 0, bar, 1, atr) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].bb, 0, bar, 1, bb_upper) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].bb, 1, bar, 1, bb_middle) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].bb, 2, bar, 1, bb_lower) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].stoch, MAIN_LINE, bar, 1, stoch_main) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].stoch, SIGNAL_LINE, bar, 1, stoch_signal) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].cci, 0, bar, 1, cci) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].adx, MAIN_LINE, bar, 1, adx_main) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].adx, PLUSDI_LINE, bar, 1, adx_plus) <= 0) return false;
      if(CopyBuffer(g_indicators[tf_idx].adx, MINUSDI_LINE, bar, 1, adx_minus) <= 0) return false;
      
      double close = iClose(Input_Symbol, tf, bar);
      
      //--- Store normalized indicators
      features[idx++] = (float)Normalize(rsi[0], 0, 100);
      features[idx++] = (float)Normalize(rsi_fast[0], 0, 100);
      features[idx++] = (float)Normalize(rsi_slow[0], 0, 100);
      features[idx++] = (float)Normalize(macd_main[0], -1, 1);
      features[idx++] = (float)Normalize(macd_signal[0], -1, 1);
      features[idx++] = (float)Normalize((close - ma_fast[0]) / close, -0.1, 0.1);
      features[idx++] = (float)Normalize((close - ma_medium[0]) / close, -0.1, 0.1);
      features[idx++] = (float)Normalize((close - ma_slow[0]) / close, -0.1, 0.1);
      features[idx++] = (float)Normalize((close - ma_xslow[0]) / close, -0.2, 0.2);
      features[idx++] = (float)Normalize(atr[0] / close, 0, 0.05);
      features[idx++] = (float)Normalize((bb_upper[0] - close) / close, -0.05, 0.05);
      features[idx++] = (float)Normalize((bb_middle[0] - close) / close, -0.05, 0.05);
      features[idx++] = (float)Normalize((bb_lower[0] - close) / close, -0.05, 0.05);
      features[idx++] = (float)Normalize(stoch_main[0], 0, 100);
      features[idx++] = (float)Normalize(stoch_signal[0], 0, 100);
      features[idx++] = (float)Normalize(cci[0], -200, 200);
      features[idx++] = (float)Normalize(adx_main[0], 0, 100);
      features[idx++] = (float)Normalize(adx_plus[0], 0, 100);
      features[idx++] = (float)Normalize(adx_minus[0], 0, 100);
      
      //--- Price history (lookback)
      for(int i = 1; i <= Input_Lookback; i++)
      {
         double hist_close = iClose(Input_Symbol, tf, bar + i);
         features[idx++] = (float)Normalize((hist_close - close) / close, -0.1, 0.1);
      }
      
      //--- Time features
      datetime bar_time = iTime(Input_Symbol, tf, bar);
      MqlDateTime dt;
      TimeToStruct(bar_time, dt);
      features[idx++] = (float)Normalize(dt.hour, 0, 23);
      features[idx++] = (float)Normalize(dt.day_of_week, 0, 6);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get prediction from ONNX model                                    |
//+------------------------------------------------------------------+
int GetPrediction(double &confidence)
{
   confidence = 0.0;
   
   if(m_onnx_handle == INVALID_HANDLE)
      return 0;
   
   //--- Extract features
   float features[];
   if(!ExtractFeatures(features))
   {
      if(Input_Debug)
         Print("ERROR: Failed to extract features");
      return 0;
   }
   
   //--- Run ONNX inference
   float output[];
   ArrayResize(output, 1);
   
   if(!OnnxRun(m_onnx_handle, ONNX_NO_CONVERSION, features, output))
   {
      Print("ERROR: ONNX inference failed");
      return 0;
   }
   
   //--- Interpret output
   confidence = MathAbs(output[0] - 0.5) * 2.0; // Convert to 0-1 confidence
   
   if(output[0] > 0.5)
      return 1;  // BUY
   else if(output[0] < 0.5)
      return -1; // SELL
   
   return 0; // NEUTRAL
}

//+------------------------------------------------------------------+
//| Apply trading filters                                             |
//+------------------------------------------------------------------+
bool PassFilters()
{
   //--- Spread filter
   if(Input_Use_Max_Spread)
   {
      double spread = SymbolInfoInteger(Input_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(Input_Symbol, SYMBOL_POINT);
      double max_spread = Input_Max_Spread * SymbolInfoDouble(Input_Symbol, SYMBOL_POINT) * 10;
      
      if(spread > max_spread)
      {
         if(Input_Debug)
            Print("Spread too high: ", spread / SymbolInfoDouble(Input_Symbol, SYMBOL_POINT) / 10, " pips");
         return false;
      }
   }
   
   //--- Trading hours filter
   if(Input_Use_Trading_Hours)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      
      if(dt.hour < Input_Start_Hour || dt.hour >= Input_End_Hour)
      {
         if(Input_Debug)
            Print("Outside trading hours");
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Open trade                                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, double confidence)
{
   double lot = CalculateLotSize();
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Input_Symbol, SYMBOL_ASK) : SymbolInfoDouble(Input_Symbol, SYMBOL_BID);
   
   double sl = 0, tp = 0;
   
   if(Input_Use_SL)
   {
      double sl_distance = Input_SL_Pips * SymbolInfoDouble(Input_Symbol, SYMBOL_POINT) * 10;
      sl = (type == ORDER_TYPE_BUY) ? price - sl_distance : price + sl_distance;
   }
   
   if(Input_Use_TP)
   {
      double tp_distance = Input_TP_Pips * SymbolInfoDouble(Input_Symbol, SYMBOL_POINT) * 10;
      tp = (type == ORDER_TYPE_BUY) ? price + tp_distance : price - tp_distance;
   }
   
   string comment = Input_Comment + StringFormat(" [%.0f%%]", confidence * 100);
   
   if(m_trade.PositionOpen(Input_Symbol, type, lot, price, sl, tp, comment))
   {
      Print("✅ ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"), " order opened at ", price, 
            " | Lot: ", lot, " | Confidence: ", (confidence * 100), "%");
   }
   else
   {
      Print("❌ Failed to open position. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if(!Input_Use_Risk_Percent)
      return Input_Fixed_Lot;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * Input_Risk_Percent / 100.0;
   double tick_value = SymbolInfoDouble(Input_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double sl_distance = Input_SL_Pips * 10;
   
   double lot = risk_amount / (sl_distance * tick_value);
   lot = MathMin(lot, Input_Max_Lot);
   lot = MathMax(lot, SymbolInfoDouble(Input_Symbol, SYMBOL_VOLUME_MIN));
   
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Count open positions                                              |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == Input_Symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Close positions by type                                           |
//+------------------------------------------------------------------+
void ClosePositionsByType(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == Input_Symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number &&
            PositionGetInteger(POSITION_TYPE) == type)
         {
            m_trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Normalize value to 0-1 range                                     |
//+------------------------------------------------------------------+
double Normalize(double value, double min_val, double max_val)
{
   if(max_val <= min_val) return 0.5;
   double normalized = (value - min_val) / (max_val - min_val);
   return MathMax(0.0, MathMin(1.0, normalized));
}
//+------------------------------------------------------------------+
