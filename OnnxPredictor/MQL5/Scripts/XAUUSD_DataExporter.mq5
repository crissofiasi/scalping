//+------------------------------------------------------------------+
//|                                     XAUUSD_DataExporter.mq5       |
//|                     Multi-Timeframe Data Exporter for ONNX        |
//|                            XAUUSD (Gold) Optimized                |
//+------------------------------------------------------------------+
#property copyright "ONNX XAUUSD Predictor"
#property version   "1.00"
#property script_show_inputs

//--- Input Parameters
input string            Input_Symbol = "XAUUSD";                    // Symbol
input ENUM_TIMEFRAMES   Input_Entry_Timeframe = PERIOD_M1;          // Entry Timeframe (M1)
input ENUM_TIMEFRAMES   Input_TF2 = PERIOD_M5;                      // Timeframe 2
input ENUM_TIMEFRAMES   Input_TF3 = PERIOD_M15;                     // Timeframe 3
input ENUM_TIMEFRAMES   Input_TF4 = PERIOD_M30;                     // Timeframe 4
input ENUM_TIMEFRAMES   Input_TF5 = PERIOD_H1;                      // Timeframe 5

input int               Input_Bars_To_Export = 100000;              // Bars to Export
input int               Input_Lookback_Bars = 100;                  // Lookback Bars (price history)
input int               Input_Lookforward_Bars = 50;                // Lookforward Bars (for labeling)
input double            Input_Target_Move_Pips = 10.0;              // Target Move in Pips

input bool              Input_Export_All_Bars = true;               // Export All Bars (vs only clear moves)
input string            Input_Output_File = "XAUUSD_training_data.csv"; // Output CSV File

//--- Indicator Parameters
input group "══════════ RSI Settings ══════════"
input int               Input_RSI_Period = 14;                      // RSI Period
input int               Input_RSI_Fast = 5;                         // RSI Fast Period
input int               Input_RSI_Slow = 21;                        // RSI Slow Period

input group "══════════ MACD Settings ══════════"
input int               Input_MACD_Fast = 12;                       // MACD Fast
input int               Input_MACD_Slow = 26;                       // MACD Slow  
input int               Input_MACD_Signal = 9;                      // MACD Signal

input group "══════════ Moving Averages ══════════"
input int               Input_MA_Fast = 10;                         // MA Fast
input int               Input_MA_Medium = 20;                       // MA Medium
input int               Input_MA_Slow = 50;                         // MA Slow
input int               Input_MA_XSlow = 200;                       // MA Extra Slow

input group "══════════ Other Indicators ══════════"
input int               Input_ATR_Period = 14;                      // ATR Period
input int               Input_BB_Period = 20;                       // Bollinger Bands Period
input double            Input_BB_Deviation = 2.0;                   // BB Deviation
input int               Input_Stoch_K = 5;                          // Stochastic %K
input int               Input_Stoch_D = 3;                          // Stochastic %D
input int               Input_Stoch_Slowing = 3;                    // Stochastic Slowing
input int               Input_CCI_Period = 14;                      // CCI Period
input int               Input_ADX_Period = 14;                      // ADX Period

//+------------------------------------------------------------------+
//| Structure to hold timeframe data                                 |
//+------------------------------------------------------------------+
struct STimeframeData
{
   ENUM_TIMEFRAMES timeframe;
   int rsi_handle;
   int rsi_fast_handle;
   int rsi_slow_handle;
   int macd_handle;
   int ma_fast_handle;
   int ma_medium_handle;
   int ma_slow_handle;
   int ma_xslow_handle;
   int atr_handle;
   int bb_handle;
   int stoch_handle;
   int cci_handle;
   int adx_handle;
};

//--- Global Variables
STimeframeData g_timeframes[5];
int g_total_exported = 0;
int g_buy_signals = 0;
int g_sell_signals = 0;
int g_neutral_signals = 0;

//+------------------------------------------------------------------+
//| Script program start                                             |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("==================================================");
   Print("XAUUSD Multi-Timeframe Data Exporter for ONNX");
   Print("==================================================");
   Print("Symbol: ", Input_Symbol);
   Print("Entry TF: M1, Analysis TFs: M5, M15, M30, H1");
   Print("Target: ", Input_Target_Move_Pips, " pips");
   Print("==================================================");
   
   //--- Initialize timeframes
   g_timeframes[0].timeframe = Input_Entry_Timeframe;
   g_timeframes[1].timeframe = Input_TF2;
   g_timeframes[2].timeframe = Input_TF3;
   g_timeframes[3].timeframe = Input_TF4;
   g_timeframes[4].timeframe = Input_TF5;
   
   //--- Create indicators for all timeframes
   if(!InitializeIndicators())
   {
      Print("ERROR: Failed to initialize indicators");
      return;
   }
   
   Print("Indicators initialized successfully");
   Print("Waiting for indicator data...");
   Sleep(3000); // Wait for indicators to load
   
   //--- Export data
   if(!ExportData())
   {
      Print("ERROR: Failed to export data");
      return;
   }
   
   Print("==================================================");
   Print("Export completed successfully!");
   Print("Total samples: ", g_total_exported);
   Print("BUY signals: ", g_buy_signals, " (", (g_buy_signals*100.0/g_total_exported), "%)");
   Print("SELL signals: ", g_sell_signals, " (", (g_sell_signals*100.0/g_total_exported), "%)");
   Print("Neutral: ", g_neutral_signals, " (", (g_neutral_signals*100.0/g_total_exported), "%)");
   Print("Output file: ", Input_Output_File);
   Print("==================================================");
   
   //--- Cleanup
   ReleaseIndicators();
}

//+------------------------------------------------------------------+
//| Initialize all indicators for all timeframes                     |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
   for(int tf_idx = 0; tf_idx < 5; tf_idx++)
   {
      ENUM_TIMEFRAMES tf = g_timeframes[tf_idx].timeframe;
      
      g_timeframes[tf_idx].rsi_handle = iRSI(Input_Symbol, tf, Input_RSI_Period, PRICE_CLOSE);
      g_timeframes[tf_idx].rsi_fast_handle = iRSI(Input_Symbol, tf, Input_RSI_Fast, PRICE_CLOSE);
      g_timeframes[tf_idx].rsi_slow_handle = iRSI(Input_Symbol, tf, Input_RSI_Slow, PRICE_CLOSE);
      g_timeframes[tf_idx].macd_handle = iMACD(Input_Symbol, tf, Input_MACD_Fast, Input_MACD_Slow, Input_MACD_Signal, PRICE_CLOSE);
      g_timeframes[tf_idx].ma_fast_handle = iMA(Input_Symbol, tf, Input_MA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      g_timeframes[tf_idx].ma_medium_handle = iMA(Input_Symbol, tf, Input_MA_Medium, 0, MODE_EMA, PRICE_CLOSE);
      g_timeframes[tf_idx].ma_slow_handle = iMA(Input_Symbol, tf, Input_MA_Slow, 0, MODE_SMA, PRICE_CLOSE);
      g_timeframes[tf_idx].ma_xslow_handle = iMA(Input_Symbol, tf, Input_MA_XSlow, 0, MODE_SMA, PRICE_CLOSE);
      g_timeframes[tf_idx].atr_handle = iATR(Input_Symbol, tf, Input_ATR_Period);
      g_timeframes[tf_idx].bb_handle = iBands(Input_Symbol, tf, Input_BB_Period, 0, Input_BB_Deviation, PRICE_CLOSE);
      g_timeframes[tf_idx].stoch_handle = iStochastic(Input_Symbol, tf, Input_Stoch_K, Input_Stoch_D, Input_Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
      g_timeframes[tf_idx].cci_handle = iCCI(Input_Symbol, tf, Input_CCI_Period, PRICE_TYPICAL);
      g_timeframes[tf_idx].adx_handle = iADX(Input_Symbol, tf, Input_ADX_Period);
      
      if(g_timeframes[tf_idx].rsi_handle == INVALID_HANDLE ||
         g_timeframes[tf_idx].macd_handle == INVALID_HANDLE ||
         g_timeframes[tf_idx].atr_handle == INVALID_HANDLE)
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
   for(int tf_idx = 0; tf_idx < 5; tf_idx++)
   {
      if(g_timeframes[tf_idx].rsi_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].rsi_handle);
      if(g_timeframes[tf_idx].rsi_fast_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].rsi_fast_handle);
      if(g_timeframes[tf_idx].rsi_slow_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].rsi_slow_handle);
      if(g_timeframes[tf_idx].macd_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].macd_handle);
      if(g_timeframes[tf_idx].ma_fast_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].ma_fast_handle);
      if(g_timeframes[tf_idx].ma_medium_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].ma_medium_handle);
      if(g_timeframes[tf_idx].ma_slow_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].ma_slow_handle);
      if(g_timeframes[tf_idx].ma_xslow_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].ma_xslow_handle);
      if(g_timeframes[tf_idx].atr_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].atr_handle);
      if(g_timeframes[tf_idx].bb_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].bb_handle);
      if(g_timeframes[tf_idx].stoch_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].stoch_handle);
      if(g_timeframes[tf_idx].cci_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].cci_handle);
      if(g_timeframes[tf_idx].adx_handle != INVALID_HANDLE) IndicatorRelease(g_timeframes[tf_idx].adx_handle);
   }
}

//+------------------------------------------------------------------+
//| Export data to CSV                                                |
//+------------------------------------------------------------------+
bool ExportData()
{
   //--- Open file
   int file_handle = FileOpen(Input_Output_File, FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
   if(file_handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create file: ", Input_Output_File);
      return false;
   }
   
   //--- Write header
   if(!WriteHeader(file_handle))
   {
      FileClose(file_handle);
      return false;
   }
   
   //--- Get total bars
   int total_bars = iBars(Input_Symbol, Input_Entry_Timeframe);
   int bars_to_export = MathMin(Input_Bars_To_Export, total_bars - Input_Lookforward_Bars - 10);
   
   Print("Processing ", bars_to_export, " bars...");
   
   //--- Export bars
   int progress_step = bars_to_export / 20;
   
   for(int bar = Input_Lookback_Bars; bar < bars_to_export; bar++)
   {
      if(bar % progress_step == 0)
      {
         Print("Progress: ", (bar * 100 / bars_to_export), "% (", bar, "/", bars_to_export, ")");
      }
      
      //--- Extract features for this bar
      double features[];
      if(!ExtractFeatures(bar, features))
         continue;
      
      //--- Calculate label
      double label = LabelBar(bar);
      
      //--- Filter based on export mode
      if(!Input_Export_All_Bars && label == 0.5)
         continue; // Skip neutral bars if not exporting all
      
      //--- Write row
      string row = "";
      for(int i = 0; i < ArraySize(features); i++)
      {
         row += DoubleToString(features[i], 6);
         if(i < ArraySize(features) - 1) row += ",";
      }
      row += "," + DoubleToString(label, 1);
      
      FileWrite(file_handle, row);
      
      //--- Count signals
      g_total_exported++;
      if(label == 1.0) g_buy_signals++;
      else if(label == 0.0) g_sell_signals++;
      else g_neutral_signals++;
   }
   
   FileClose(file_handle);
   return true;
}

//+------------------------------------------------------------------+
//| Write CSV header                                                  |
//+------------------------------------------------------------------+
bool WriteHeader(int file_handle)
{
   string header = "";
   
   //--- For each timeframe
   for(int tf_idx = 0; tf_idx < 5; tf_idx++)
   {
      string tf_suffix = "_TF" + IntegerToString(tf_idx + 1);
      
      //--- Technical indicators
      header += "RSI" + tf_suffix + ",";
      header += "RSI_Fast" + tf_suffix + ",";
      header += "RSI_Slow" + tf_suffix + ",";
      header += "MACD_Main" + tf_suffix + ",";
      header += "MACD_Signal" + tf_suffix + ",";
      header += "MA_Fast" + tf_suffix + ",";
      header += "MA_Medium" + tf_suffix + ",";
      header += "MA_Slow" + tf_suffix + ",";
      header += "MA_XSlow" + tf_suffix + ",";
      header += "ATR" + tf_suffix + ",";
      header += "BB_Upper" + tf_suffix + ",";
      header += "BB_Middle" + tf_suffix + ",";
      header += "BB_Lower" + tf_suffix + ",";
      header += "Stoch_Main" + tf_suffix + ",";
      header += "Stoch_Signal" + tf_suffix + ",";
      header += "CCI" + tf_suffix + ",";
      header += "ADX" + tf_suffix + ",";
      header += "ADX_Plus" + tf_suffix + ",";
      header += "ADX_Minus" + tf_suffix + ",";
      
      //--- Price action (normalized lookback)
      for(int i = 1; i <= Input_Lookback_Bars; i++)
      {
         header += "Price_Bar" + IntegerToString(i) + tf_suffix + ",";
      }
      
      //--- Time features
      header += "Hour" + tf_suffix + ",";
      header += "DayOfWeek" + tf_suffix + ",";
   }
   
   //--- Label
   header += "Label";
   
   FileWrite(file_handle, header);
   return true;
}

//+------------------------------------------------------------------+
//| Extract all features for a bar (all timeframes)                  |
//+------------------------------------------------------------------+
bool ExtractFeatures(int bar, double &features[])
{
   int total_features = CalculateTotalFeatures();
   ArrayResize(features, total_features);
   int feature_idx = 0;
   
   //--- Extract features for each timeframe
   for(int tf_idx = 0; tf_idx < 5; tf_idx++)
   {
      ENUM_TIMEFRAMES tf = g_timeframes[tf_idx].timeframe;
      int tf_bar = iBarShift(Input_Symbol, tf, iTime(Input_Symbol, Input_Entry_Timeframe, bar));
      
      //--- Get indicator values
      double rsi[], rsi_fast[], rsi_slow[], macd_main[], macd_signal[];
      double ma_fast[], ma_medium[], ma_slow[], ma_xslow[], atr[];
      double bb_upper[], bb_middle[], bb_lower[];
      double stoch_main[], stoch_signal[], cci[], adx_main[], adx_plus[], adx_minus[];
      
      if(CopyBuffer(g_timeframes[tf_idx].rsi_handle, 0, tf_bar, 1, rsi) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].rsi_fast_handle, 0, tf_bar, 1, rsi_fast) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].rsi_slow_handle, 0, tf_bar, 1, rsi_slow) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].macd_handle, MAIN_LINE, tf_bar, 1, macd_main) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].macd_handle, SIGNAL_LINE, tf_bar, 1, macd_signal) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].ma_fast_handle, 0, tf_bar, 1, ma_fast) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].ma_medium_handle, 0, tf_bar, 1, ma_medium) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].ma_slow_handle, 0, tf_bar, 1, ma_slow) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].ma_xslow_handle, 0, tf_bar, 1, ma_xslow) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].atr_handle, 0, tf_bar, 1, atr) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].bb_handle, 0, tf_bar, 1, bb_upper) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].bb_handle, 1, tf_bar, 1, bb_middle) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].bb_handle, 2, tf_bar, 1, bb_lower) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].stoch_handle, MAIN_LINE, tf_bar, 1, stoch_main) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].stoch_handle, SIGNAL_LINE, tf_bar, 1, stoch_signal) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].cci_handle, 0, tf_bar, 1, cci) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].adx_handle, MAIN_LINE, tf_bar, 1, adx_main) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].adx_handle, PLUSDI_LINE, tf_bar, 1, adx_plus) <= 0) return false;
      if(CopyBuffer(g_timeframes[tf_idx].adx_handle, MINUSDI_LINE, tf_bar, 1, adx_minus) <= 0) return false;
      
      double close = iClose(Input_Symbol, tf, tf_bar);
      
      //--- Normalize and store indicators
      features[feature_idx++] = NormalizeValue(rsi[0], 0, 100);
      features[feature_idx++] = NormalizeValue(rsi_fast[0], 0, 100);
      features[feature_idx++] = NormalizeValue(rsi_slow[0], 0, 100);
      features[feature_idx++] = NormalizeValue(macd_main[0], -1, 1);
      features[feature_idx++] = NormalizeValue(macd_signal[0], -1, 1);
      features[feature_idx++] = NormalizeValue((close - ma_fast[0]) / close, -0.1, 0.1);
      features[feature_idx++] = NormalizeValue((close - ma_medium[0]) / close, -0.1, 0.1);
      features[feature_idx++] = NormalizeValue((close - ma_slow[0]) / close, -0.1, 0.1);
      features[feature_idx++] = NormalizeValue((close - ma_xslow[0]) / close, -0.2, 0.2);
      features[feature_idx++] = NormalizeValue(atr[0] / close, 0, 0.05);
      features[feature_idx++] = NormalizeValue((bb_upper[0] - close) / close, -0.05, 0.05);
      features[feature_idx++] = NormalizeValue((bb_middle[0] - close) / close, -0.05, 0.05);
      features[feature_idx++] = NormalizeValue((bb_lower[0] - close) / close, -0.05, 0.05);
      features[feature_idx++] = NormalizeValue(stoch_main[0], 0, 100);
      features[feature_idx++] = NormalizeValue(stoch_signal[0], 0, 100);
      features[feature_idx++] = NormalizeValue(cci[0], -200, 200);
      features[feature_idx++] = NormalizeValue(adx_main[0], 0, 100);
      features[feature_idx++] = NormalizeValue(adx_plus[0], 0, 100);
      features[feature_idx++] = NormalizeValue(adx_minus[0], 0, 100);
      
      //--- Normalized price history (lookback)
      double base_price = close;
      for(int i = 1; i <= Input_Lookback_Bars; i++)
      {
         double hist_close = iClose(Input_Symbol, tf, tf_bar + i);
         features[feature_idx++] = NormalizeValue((hist_close - base_price) / base_price, -0.1, 0.1);
      }
      
      //--- Time features
      datetime bar_time = iTime(Input_Symbol, tf, tf_bar);
      MqlDateTime dt;
      TimeToStruct(bar_time, dt);
      features[feature_idx++] = NormalizeValue(dt.hour, 0, 23);
      features[feature_idx++] = NormalizeValue(dt.day_of_week, 0, 6);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate total number of features                               |
//+------------------------------------------------------------------+
int CalculateTotalFeatures()
{
   int features_per_tf = 19 + Input_Lookback_Bars + 2; // indicators + lookback + time
   return features_per_tf * 5; // 5 timeframes
}

//+------------------------------------------------------------------+
//| Label a bar (1.0 = BUY, 0.0 = SELL, 0.5 = NEUTRAL)              |
//+------------------------------------------------------------------+
double LabelBar(int bar)
{
   double base_price = iClose(Input_Symbol, Input_Entry_Timeframe, bar);
   double target_pips = Input_Target_Move_Pips * SymbolInfoDouble(Input_Symbol, SYMBOL_POINT) * 10;
   
   double max_high = base_price;
   double min_low = base_price;
   
   //--- Look forward
   for(int i = 1; i <= Input_Lookforward_Bars; i++)
   {
      double high = iHigh(Input_Symbol, Input_Entry_Timeframe, bar - i);
      double low = iLow(Input_Symbol, Input_Entry_Timeframe, bar - i);
      
      if(high > max_high) max_high = high;
      if(low < min_low) min_low = low;
   }
   
   double up_move = max_high - base_price;
   double down_move = base_price - min_low;
   
   //--- Strict labeling: target hit one direction only
   if(up_move >= target_pips && down_move < target_pips)
      return 1.0; // BUY
   
   if(down_move >= target_pips && up_move < target_pips)
      return 0.0; // SELL
   
   //--- Relative labeling for unclear cases (if exporting all bars)
   if(Input_Export_All_Bars)
   {
      if(up_move > down_move * 1.5) return 1.0; // UP moved more
      if(down_move > up_move * 1.5) return 0.0; // DOWN moved more
   }
   
   return 0.5; // NEUTRAL
}

//+------------------------------------------------------------------+
//| Normalize value to 0-1 range                                     |
//+------------------------------------------------------------------+
double NormalizeValue(double value, double min_val, double max_val)
{
   if(max_val <= min_val) return 0.5;
   double normalized = (value - min_val) / (max_val - min_val);
   return MathMax(0.0, MathMin(1.0, normalized));
}
