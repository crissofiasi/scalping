//+------------------------------------------------------------------+
//|                                              MT5DataExporter.mq5 |
//|                                   Neural Predictor Training Data |
//|                         Exports historical data for Python ML    |
//+------------------------------------------------------------------+
#property copyright "Neural Predictor System"
#property version   "1.00"
#property script_show_inputs

//+------------------------------------------------------------------+
//| Parameter Feature Structure                                       |
//+------------------------------------------------------------------+
struct SParameterFeatures
{
   //--- Trading parameters
   double   stop_loss_pips;
   double   take_profit_pips;
   double   target_move_pips;
   double   risk_percent;
   int      max_positions;
   bool     use_trading_hours;
   
   //--- Multi-timeframe settings
   bool              use_multi_tf;
   ENUM_TIMEFRAMES   timeframe1;
   ENUM_TIMEFRAMES   timeframe2;
   ENUM_TIMEFRAMES   timeframe3;
   
   //--- Indicator parameters
   int      rsi_period;
   int      rsi_fast_period;
   int      macd_fast;
   int      macd_slow;
   int      macd_signal;
   int      atr_period;
   int      bb_period;
   double   bb_deviation;
   
   SParameterFeatures() : stop_loss_pips(20), take_profit_pips(30), target_move_pips(10),
                          risk_percent(1.0), max_positions(3), use_trading_hours(false),
                          use_multi_tf(false), timeframe1(PERIOD_M5), timeframe2(PERIOD_M15), timeframe3(PERIOD_M30),
                          rsi_period(14), rsi_fast_period(5), macd_fast(12), macd_slow(26),
                          macd_signal(9), atr_period(14), bb_period(20), bb_deviation(2.0) {}
};

//+------------------------------------------------------------------+
//| Neural Predictor Library Class (embedded)                        |
//+------------------------------------------------------------------+
class CNNPredictorLib
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   
   //--- Single timeframe handles
   int               m_rsi_handle;
   int               m_rsi_fast_handle;
   int               m_macd_handle;
   int               m_atr_handle;
   int               m_bb_handle;
   
   //--- Multi-timeframe handles
   int               m_rsi_handle_tf2;
   int               m_rsi_fast_handle_tf2;
   int               m_macd_handle_tf2;
   int               m_atr_handle_tf2;
   int               m_bb_handle_tf2;
   
   int               m_rsi_handle_tf3;
   int               m_rsi_fast_handle_tf3;
   int               m_macd_handle_tf3;
   int               m_atr_handle_tf3;
   int               m_bb_handle_tf3;
   
   //--- Multi-timeframe settings
   bool              m_use_multi_tf;
   ENUM_TIMEFRAMES   m_timeframe2;
   ENUM_TIMEFRAMES   m_timeframe3;
   
   //--- Parameter features
   SParameterFeatures m_params;
   bool              m_use_param_features;

public:
   CNNPredictorLib()
   {
      m_symbol = _Symbol;
      m_timeframe = PERIOD_CURRENT;
      m_rsi_handle = INVALID_HANDLE;
      m_rsi_fast_handle = INVALID_HANDLE;
      m_macd_handle = INVALID_HANDLE;
      m_atr_handle = INVALID_HANDLE;
      m_bb_handle = INVALID_HANDLE;
      
      m_rsi_handle_tf2 = INVALID_HANDLE;
      m_rsi_fast_handle_tf2 = INVALID_HANDLE;
      m_macd_handle_tf2 = INVALID_HANDLE;
      m_atr_handle_tf2 = INVALID_HANDLE;
      m_bb_handle_tf2 = INVALID_HANDLE;
      
      m_rsi_handle_tf3 = INVALID_HANDLE;
      m_rsi_fast_handle_tf3 = INVALID_HANDLE;
      m_macd_handle_tf3 = INVALID_HANDLE;
      m_atr_handle_tf3 = INVALID_HANDLE;
      m_bb_handle_tf3 = INVALID_HANDLE;
      
      m_use_multi_tf = false;
      m_timeframe2 = PERIOD_CURRENT;
      m_timeframe3 = PERIOD_CURRENT;
      m_use_param_features = false;
   }
   
   void SetSymbol(string symbol) { m_symbol = symbol; }
   void SetTimeframe(ENUM_TIMEFRAMES tf) { m_timeframe = tf; }
   
   //--- Enable/disable parameter features
   void EnableParameterFeatures(bool enable) { m_use_param_features = enable; }
   
   //--- Set parameter features
   void SetParameters(const SParameterFeatures &params)
   {
      m_params = params;
      m_params.timeframe1 = m_timeframe;
      m_params.timeframe2 = m_timeframe2;
      m_params.timeframe3 = m_timeframe3;
      m_params.use_multi_tf = m_use_multi_tf;
   }
   void SetIndicatorHandles(int rsi, int rsi_fast, int macd, int atr, int bb)
   {
      m_rsi_handle = rsi;
      m_rsi_fast_handle = rsi_fast;
      m_macd_handle = macd;
      m_atr_handle = atr;
      m_bb_handle = bb;
   }
   
   void EnableMultiTimeframe(bool enable, ENUM_TIMEFRAMES tf2, ENUM_TIMEFRAMES tf3)
   {
      m_use_multi_tf = enable;
      m_timeframe2 = tf2;
      m_timeframe3 = tf3;
   }
   
   void SetIndicatorHandlesTF2(int rsi, int rsi_fast, int macd, int atr, int bb)
   {
      m_rsi_handle_tf2 = rsi;
      m_rsi_fast_handle_tf2 = rsi_fast;
      m_macd_handle_tf2 = macd;
      m_atr_handle_tf2 = atr;
      m_bb_handle_tf2 = bb;
   }
   
   void SetIndicatorHandlesTF3(int rsi, int rsi_fast, int macd, int atr, int bb)
   {
      m_rsi_handle_tf3 = rsi;
      m_rsi_fast_handle_tf3 = rsi_fast;
      m_macd_handle_tf3 = macd;
      m_atr_handle_tf3 = atr;
      m_bb_handle_tf3 = bb;
   }
   
   bool PrepareFeatures(double &features[], int bar_shift, int lookback_bars)
   {
      int num_indicators = 8;
      int num_price_features = lookback_bars;
      int num_time_features = 2;
      int features_per_tf = num_indicators + num_price_features + num_time_features;
      int num_param_features = m_use_param_features ? 18 : 0; // Parameter features
      
      int num_timeframes = 1;
      if(m_use_multi_tf)
      {
         if(m_timeframe2 != PERIOD_CURRENT && m_rsi_handle_tf2 != INVALID_HANDLE) num_timeframes++;
         if(m_timeframe3 != PERIOD_CURRENT && m_rsi_handle_tf3 != INVALID_HANDLE) num_timeframes++;
      }
      
      int total_features = features_per_tf * num_timeframes + num_param_features;
      
      ArrayResize(features, total_features);
      ArrayInitialize(features, 0.0);
      
      int feature_idx = 0;
      
      if(!ExtractTimeframeFeatures(features, feature_idx, m_timeframe, bar_shift, lookback_bars,
                                     m_rsi_handle, m_rsi_fast_handle, m_macd_handle, m_atr_handle, m_bb_handle))
         return false;
      
      if(m_use_multi_tf && m_timeframe2 != PERIOD_CURRENT && m_rsi_handle_tf2 != INVALID_HANDLE)
      {
         int bar_shift_tf2 = iBarShift(m_symbol, m_timeframe2, iTime(m_symbol, m_timeframe, bar_shift));
         if(!ExtractTimeframeFeatures(features, feature_idx, m_timeframe2, bar_shift_tf2, lookback_bars,
                                        m_rsi_handle_tf2, m_rsi_fast_handle_tf2, m_macd_handle_tf2, m_atr_handle_tf2, m_bb_handle_tf2))
            return false;
      }
      
      if(m_use_multi_tf && m_timeframe3 != PERIOD_CURRENT && m_rsi_handle_tf3 != INVALID_HANDLE)
      {
         int bar_shift_tf3 = iBarShift(m_symbol, m_timeframe3, iTime(m_symbol, m_timeframe, bar_shift));
         if(!ExtractTimeframeFeatures(features, feature_idx, m_timeframe3, bar_shift_tf3, lookback_bars,
                                        m_rsi_handle_tf3, m_rsi_fast_handle_tf3, m_macd_handle_tf3, m_atr_handle_tf3, m_bb_handle_tf3))
            return false;
      }
      
      //--- Add parameter features if enabled
      if(m_use_param_features)
      {
         AddParameterFeatures(features, feature_idx);
      }
      
      return true;
   }
   
   //--- Add parameter features to feature array
   void AddParameterFeatures(double &features[], int &feature_idx)
   {
      //--- Trading parameters (normalized)
      features[feature_idx++] = NormalizeValue(m_params.stop_loss_pips, 0.0, 100.0);
      features[feature_idx++] = NormalizeValue(m_params.take_profit_pips, 0.0, 100.0);
      features[feature_idx++] = NormalizeValue(m_params.target_move_pips, 0.0, 50.0);
      features[feature_idx++] = NormalizeValue(m_params.risk_percent, 0.0, 5.0);
      features[feature_idx++] = NormalizeValue(m_params.max_positions, 0.0, 10.0);
      features[feature_idx++] = m_params.use_trading_hours ? 1.0 : 0.0;
      
      //--- Multi-timeframe settings
      features[feature_idx++] = m_params.use_multi_tf ? 1.0 : 0.0;
      features[feature_idx++] = NormalizeValue(TimeframeToMinutes(m_params.timeframe1), 0.0, 1440.0);
      features[feature_idx++] = NormalizeValue(TimeframeToMinutes(m_params.timeframe2), 0.0, 1440.0);
      features[feature_idx++] = NormalizeValue(TimeframeToMinutes(m_params.timeframe3), 0.0, 1440.0);
      
      //--- Indicator parameters (normalized)
      features[feature_idx++] = NormalizeValue(m_params.rsi_period, 5.0, 50.0);
      features[feature_idx++] = NormalizeValue(m_params.rsi_fast_period, 3.0, 30.0);
      features[feature_idx++] = NormalizeValue(m_params.macd_fast, 5.0, 30.0);
      features[feature_idx++] = NormalizeValue(m_params.macd_slow, 10.0, 50.0);
      features[feature_idx++] = NormalizeValue(m_params.macd_signal, 5.0, 20.0);
      features[feature_idx++] = NormalizeValue(m_params.atr_period, 5.0, 50.0);
      features[feature_idx++] = NormalizeValue(m_params.bb_period, 10.0, 50.0);
      features[feature_idx++] = NormalizeValue(m_params.bb_deviation, 1.0, 5.0);
   }
   
   //--- Convert timeframe enum to minutes
   double TimeframeToMinutes(ENUM_TIMEFRAMES tf)
   {
      switch(tf)
      {
         case PERIOD_M1:  return 1;
         case PERIOD_M2:  return 2;
         case PERIOD_M3:  return 3;
         case PERIOD_M4:  return 4;
         case PERIOD_M5:  return 5;
         case PERIOD_M6:  return 6;
         case PERIOD_M10: return 10;
         case PERIOD_M12: return 12;
         case PERIOD_M15: return 15;
         case PERIOD_M20: return 20;
         case PERIOD_M30: return 30;
         case PERIOD_H1:  return 60;
         case PERIOD_H2:  return 120;
         case PERIOD_H3:  return 180;
         case PERIOD_H4:  return 240;
         case PERIOD_H6:  return 360;
         case PERIOD_H8:  return 480;
         case PERIOD_H12: return 720;
         case PERIOD_D1:  return 1440;
         case PERIOD_W1:  return 10080;
         case PERIOD_MN1: return 43200;
         default: return 5;
      }
   }
   
   bool ExtractTimeframeFeatures(double &features[], int &feature_idx, ENUM_TIMEFRAMES tf, int bar_shift, int lookback_bars,
                                   int rsi_h, int rsi_fast_h, int macd_h, int atr_h, int bb_h)
   {
      double rsi[], rsi_fast[], macd_main[], macd_signal[], atr[];
      double bb_upper[], bb_middle[], bb_lower[];
      
      ArraySetAsSeries(rsi, true);
      ArraySetAsSeries(rsi_fast, true);
      ArraySetAsSeries(macd_main, true);
      ArraySetAsSeries(macd_signal, true);
      ArraySetAsSeries(atr, true);
      ArraySetAsSeries(bb_upper, true);
      ArraySetAsSeries(bb_middle, true);
      ArraySetAsSeries(bb_lower, true);
      
      if(CopyBuffer(rsi_h, 0, bar_shift, 1, rsi) <= 0) return false;
      if(CopyBuffer(rsi_fast_h, 0, bar_shift, 1, rsi_fast) <= 0) return false;
      if(CopyBuffer(macd_h, 0, bar_shift, 1, macd_main) <= 0) return false;
      if(CopyBuffer(macd_h, 1, bar_shift, 1, macd_signal) <= 0) return false;
      if(CopyBuffer(atr_h, 0, bar_shift, 1, atr) <= 0) return false;
      if(CopyBuffer(bb_h, 1, bar_shift, 1, bb_upper) <= 0) return false;
      if(CopyBuffer(bb_h, 0, bar_shift, 1, bb_middle) <= 0) return false;
      if(CopyBuffer(bb_h, 2, bar_shift, 1, bb_lower) <= 0) return false;
      
      features[feature_idx++] = rsi[0] / 100.0;
      features[feature_idx++] = rsi_fast[0] / 100.0;
      features[feature_idx++] = NormalizeValue(macd_main[0], -1.0, 1.0);
      features[feature_idx++] = NormalizeValue(macd_signal[0], -1.0, 1.0);
      
      double current_price = iClose(m_symbol, tf, bar_shift);
      features[feature_idx++] = (current_price > 0) ? (atr[0] / current_price) : 0.0;
      
      double bb_width = bb_upper[0] - bb_lower[0];
      if(bb_width > 0)
      {
         features[feature_idx++] = (bb_upper[0] - current_price) / bb_width;
         features[feature_idx++] = (current_price - bb_lower[0]) / bb_width;
         features[feature_idx++] = (current_price - bb_middle[0]) / bb_width;
      }
      else
      {
         features[feature_idx++] = 0.5;
         features[feature_idx++] = 0.5;
         features[feature_idx++] = 0.0;
      }
      
      double prices[];
      ArraySetAsSeries(prices, true);
      
      if(CopyClose(m_symbol, tf, bar_shift, lookback_bars + 1, prices) <= 0)
         return false;
      
      for(int i = 0; i < lookback_bars; i++)
      {
         if(prices[i + 1] > 0)
         {
            double price_change = (prices[i] - prices[i + 1]) / prices[i + 1];
            features[feature_idx++] = NormalizeValue(price_change, -0.1, 0.1);
         }
         else
         {
            features[feature_idx++] = 0.0;
         }
      }
      
      MqlDateTime dt;
      TimeToStruct(iTime(m_symbol, tf, bar_shift), dt);
      
      features[feature_idx++] = dt.hour / 24.0;
      features[feature_idx++] = dt.day_of_week / 7.0;
      
      return true;
   }
   
   double NormalizeValue(double value, double min_val, double max_val)
   {
      if(max_val <= min_val) return 0.5;
      
      double normalized = (value - min_val) / (max_val - min_val);
      
      if(normalized < 0.0) normalized = 0.0;
      if(normalized > 1.0) normalized = 1.0;
      
      return normalized;
   }
};

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input int      Input_Export_Bars = 10000;           // Bars to export
input double   Input_Target_Move_Pips = 10.0;       // Target move for labeling (pips)
input int      Input_Lookforward_Bars = 15;         // Bars to look ahead for label
input bool     Input_Use_Multi_Timeframe = true;    // Export multi-timeframe data
input ENUM_TIMEFRAMES Input_Timeframe_2 = PERIOD_M15;  // Second timeframe (if MTA)
input ENUM_TIMEFRAMES Input_Timeframe_3 = PERIOD_M30;  // Third timeframe (if MTA)
input string   Input_Output_Filename = "nn_training_data.csv";  // Output filename

//--- Parameter features to include in training
input group "═══════════ Parameter Features ═══════════"
input bool     Input_Include_Parameters = true;     // Include EA parameters in export
input double   Input_Stop_Loss_Pips = 20.0;         // Stop Loss (pips)
input double   Input_Take_Profit_Pips = 30.0;       // Take Profit (pips)
input double   Input_Risk_Percent = 1.0;            // Risk Percent
input int      Input_Max_Positions = 3;             // Max Positions
input bool     Input_Use_Trading_Hours = false;     // Trading Hours Enabled

//--- Indicator parameters for export
input group "═══════════ Indicator Parameters ═══════════"
input int      Input_RSI_Period = 14;               // RSI Period
input int      Input_RSI_Fast_Period = 5;           // RSI Fast Period
input int      Input_MACD_Fast = 12;                // MACD Fast
input int      Input_MACD_Slow = 26;                // MACD Slow
input int      Input_MACD_Signal = 9;               // MACD Signal
input int      Input_ATR_Period = 14;               // ATR Period
input int      Input_BB_Period = 20;                // BB Period
input double   Input_BB_Deviation = 2.0;            // BB Deviation

//--- Global variables
CNNPredictorLib g_lib;
int g_rsi_handle, g_rsi_fast_handle, g_macd_handle, g_atr_handle, g_bb_handle;
int g_rsi_handle_tf2, g_rsi_fast_handle_tf2, g_macd_handle_tf2, g_atr_handle_tf2, g_bb_handle_tf2;
int g_rsi_handle_tf3, g_rsi_fast_handle_tf3, g_macd_handle_tf3, g_atr_handle_tf3, g_bb_handle_tf3;

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== MT5 Data Exporter for Python Training ===");
   Print("Exporting ", Input_Export_Bars, " bars...");
   
   //--- Initialize indicators for primary timeframe (using input parameters)
   g_rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, Input_RSI_Period, PRICE_CLOSE);
   g_rsi_fast_handle = iRSI(_Symbol, PERIOD_CURRENT, Input_RSI_Fast_Period, PRICE_CLOSE);
   g_macd_handle = iMACD(_Symbol, PERIOD_CURRENT, Input_MACD_Fast, Input_MACD_Slow, Input_MACD_Signal, PRICE_CLOSE);
   g_atr_handle = iATR(_Symbol, PERIOD_CURRENT, Input_ATR_Period);
   g_bb_handle = iBands(_Symbol, PERIOD_CURRENT, Input_BB_Period, 0, Input_BB_Deviation, PRICE_CLOSE);
   
   if(g_rsi_handle == INVALID_HANDLE || g_macd_handle == INVALID_HANDLE || 
      g_atr_handle == INVALID_HANDLE || g_bb_handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to initialize indicators!");
      return;
   }
   
   //--- Set indicator handles for library (primary timeframe)
   g_lib.SetIndicatorHandles(g_rsi_handle, g_rsi_fast_handle, g_macd_handle, g_atr_handle, g_bb_handle);
   
   //--- Multi-timeframe setup
   if(Input_Use_Multi_Timeframe)
   {
      Print("Multi-Timeframe Mode: ", EnumToString(PERIOD_CURRENT), " + ", 
            EnumToString(Input_Timeframe_2), " + ", EnumToString(Input_Timeframe_3));
            
      g_lib.EnableMultiTimeframe(true, Input_Timeframe_2, Input_Timeframe_3);
      
      // Initialize TF2 indicators (using input parameters)
      g_rsi_handle_tf2 = iRSI(_Symbol, Input_Timeframe_2, Input_RSI_Period, PRICE_CLOSE);
      g_rsi_fast_handle_tf2 = iRSI(_Symbol, Input_Timeframe_2, Input_RSI_Fast_Period, PRICE_CLOSE);
      g_macd_handle_tf2 = iMACD(_Symbol, Input_Timeframe_2, Input_MACD_Fast, Input_MACD_Slow, Input_MACD_Signal, PRICE_CLOSE);
      g_atr_handle_tf2 = iATR(_Symbol, Input_Timeframe_2, Input_ATR_Period);
      g_bb_handle_tf2 = iBands(_Symbol, Input_Timeframe_2, Input_BB_Period, 0, Input_BB_Deviation, PRICE_CLOSE);
      
      g_lib.SetIndicatorHandlesTF2(g_rsi_handle_tf2, g_rsi_fast_handle_tf2, 
                                    g_macd_handle_tf2, g_atr_handle_tf2, g_bb_handle_tf2);
      
      // Initialize TF3 indicators (using input parameters)
      g_rsi_handle_tf3 = iRSI(_Symbol, Input_Timeframe_3, Input_RSI_Period, PRICE_CLOSE);
      g_rsi_fast_handle_tf3 = iRSI(_Symbol, Input_Timeframe_3, Input_RSI_Fast_Period, PRICE_CLOSE);
      g_macd_handle_tf3 = iMACD(_Symbol, Input_Timeframe_3, Input_MACD_Fast, Input_MACD_Slow, Input_MACD_Signal, PRICE_CLOSE);
      g_atr_handle_tf3 = iATR(_Symbol, Input_Timeframe_3, Input_ATR_Period);
      g_bb_handle_tf3 = iBands(_Symbol, Input_Timeframe_3, Input_BB_Period, 0, Input_BB_Deviation, PRICE_CLOSE);
      
      g_lib.SetIndicatorHandlesTF3(g_rsi_handle_tf3, g_rsi_fast_handle_tf3, 
                                    g_macd_handle_tf3, g_atr_handle_tf3, g_bb_handle_tf3);
   }
   
   //--- Set parameter features if enabled
   if(Input_Include_Parameters)
   {
      SParameterFeatures params;
      params.stop_loss_pips = Input_Stop_Loss_Pips;
      params.take_profit_pips = Input_Take_Profit_Pips;
      params.target_move_pips = Input_Target_Move_Pips;
      params.risk_percent = Input_Risk_Percent;
      params.max_positions = Input_Max_Positions;
      params.use_trading_hours = Input_Use_Trading_Hours;
      params.use_multi_tf = Input_Use_Multi_Timeframe;
      params.timeframe1 = PERIOD_CURRENT;
      params.timeframe2 = Input_Timeframe_2;
      params.timeframe3 = Input_Timeframe_3;
      params.rsi_period = Input_RSI_Period;
      params.rsi_fast_period = Input_RSI_Fast_Period;
      params.macd_fast = Input_MACD_Fast;
      params.macd_slow = Input_MACD_Slow;
      params.macd_signal = Input_MACD_Signal;
      params.atr_period = Input_ATR_Period;
      params.bb_period = Input_BB_Period;
      params.bb_deviation = Input_BB_Deviation;
      
      g_lib.SetParameters(params);
      
      Print("Parameter features ENABLED - Will include EA settings in export");
   }
   else
   {
      Print("Parameter features DISABLED");
   }
   
   //--- Wait for indicator data
   Print("Waiting for indicator calculations...");
   Sleep(3000);
   
   //--- Open output file
   int file_handle = FileOpen(Input_Output_Filename, FILE_WRITE|FILE_CSV|FILE_COMMON);
   if(file_handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create file ", Input_Output_Filename, " Error: ", GetLastError());
      return;
   }
   
   //--- Write header
   WriteCSVHeader(file_handle);
   
   //--- Export data
   int exported_count = 0;
   int skipped_count = 0;
   
   for(int i = Input_Export_Bars + Input_Lookforward_Bars; i >= Input_Lookforward_Bars; i--)
   {
      //--- Extract features
      double features[];
      if(!g_lib.PrepareFeatures(features, i, 15))  // 15 lookback bars for price patterns
      {
         skipped_count++;
         continue;
      }
      
      //--- Calculate label
      double label = LabelBar(i);
      if(label < 0)  // No clear direction
      {
         skipped_count++;
         continue;
      }
      
      //--- Write row to CSV
      WriteCSVRow(file_handle, features, label);
      exported_count++;
      
      //--- Progress update
      if(exported_count % 500 == 0)
         Print("Exported ", exported_count, " rows...");
   }
   
   //--- Close file
   FileClose(file_handle);
   
   //--- Summary
   Print("========================================");
   Print("Export Complete!");
   Print("Total exported: ", exported_count, " rows");
   Print("Skipped: ", skipped_count, " rows (no clear label)");
   Print("File: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", Input_Output_Filename);
   Print("========================================");
   Print("Next step: Run Python training script");
}

//+------------------------------------------------------------------+
//| Write CSV header                                                  |
//+------------------------------------------------------------------+
void WriteCSVHeader(int file_handle)
{
   string header = "";
   
   int num_timeframes = Input_Use_Multi_Timeframe ? 3 : 1;
   
   for(int tf = 1; tf <= num_timeframes; tf++)
   {
      string tf_suffix = (num_timeframes > 1) ? ("_TF" + IntegerToString(tf)) : "";
      
      //--- Indicators (8 features)
      header += "RSI" + tf_suffix + ",";
      header += "RSI_Fast" + tf_suffix + ",";
      header += "MACD_Main" + tf_suffix + ",";
      header += "MACD_Signal" + tf_suffix + ",";
      header += "ATR" + tf_suffix + ",";
      header += "BB_Upper_Dist" + tf_suffix + ",";
      header += "BB_Lower_Dist" + tf_suffix + ",";
      header += "BB_Middle_Dist" + tf_suffix + ",";
      
      //--- Price patterns (15 features)
      for(int i = 1; i <= 15; i++)
         header += "Price_Bar" + IntegerToString(i) + tf_suffix + ",";
      
      //--- Time features (2 features) - only for first timeframe
      if(tf == 1)
      {
         header += "Hour" + tf_suffix + ",";
         header += "DayOfWeek" + tf_suffix + ",";
      }
   }
   
   //--- Label
   header += "Label";
   
   FileWrite(file_handle, header);
}

//+------------------------------------------------------------------+
//| Write CSV row                                                     |
//+------------------------------------------------------------------+
void WriteCSVRow(int file_handle, double &features[], double label)
{
   string row = "";
   
   //--- Features
   for(int i = 0; i < ArraySize(features); i++)
   {
      row += DoubleToString(features[i], 6);
      if(i < ArraySize(features) - 1)
         row += ",";
   }
   
   //--- Label
   row += "," + DoubleToString(label, 1);
   
   FileWrite(file_handle, row);
}

//+------------------------------------------------------------------+
//| Label bar based on future price movement                         |
//+------------------------------------------------------------------+
double LabelBar(int bar_index)
{
   double target_points = Input_Target_Move_Pips * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   
   double open_price = iOpen(_Symbol, PERIOD_CURRENT, bar_index);
   double max_up = 0;
   double max_down = 0;
   
   //--- Look forward to find maximum movement
   for(int i = 1; i <= Input_Lookforward_Bars; i++)
   {
      if(bar_index - i < 0) break;
      
      double high = iHigh(_Symbol, PERIOD_CURRENT, bar_index - i);
      double low = iLow(_Symbol, PERIOD_CURRENT, bar_index - i);
      
      double up_move = high - open_price;
      double down_move = open_price - low;
      
      if(up_move > max_up) max_up = up_move;
      if(down_move > max_down) max_down = down_move;
   }
   
   //--- Determine label
   bool is_buy_move = (max_up >= target_points);
   bool is_sell_move = (max_down >= target_points);
   
   //--- Clear directional move
   if(is_buy_move && !is_sell_move)
      return 1.0;  // BUY
   else if(is_sell_move && !is_buy_move)
      return 0.0;  // SELL
   else
      return -1.0; // No clear direction (excluded)
}
//+------------------------------------------------------------------+
