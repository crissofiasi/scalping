//+------------------------------------------------------------------+
//|                                           NNPredictorLib.mqh     |
//|                    Helper Library for Neural Predictor EA        |
//+------------------------------------------------------------------+
#property copyright "Neural Predictor Library"
#property version   "1.00"

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
//| Neural Predictor Library Class                                    |
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
   //--- Constructor
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
   
   //--- Setters
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
   
   //--- Multi-timeframe setters
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
   
   //--- Prepare features for neural network input
   bool PrepareFeatures(double &features[], int bar_shift, int lookback_bars)
   {
      //--- Calculate total number of features
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
      
      //--- Extract features from primary timeframe
      if(!ExtractTimeframeFeatures(features, feature_idx, m_timeframe, bar_shift, lookback_bars,
                                     m_rsi_handle, m_rsi_fast_handle, m_macd_handle, m_atr_handle, m_bb_handle))
         return false;
      
      //--- Extract features from TF2 if enabled
      if(m_use_multi_tf && m_timeframe2 != PERIOD_CURRENT && m_rsi_handle_tf2 != INVALID_HANDLE)
      {
         int bar_shift_tf2 = iBarShift(m_symbol, m_timeframe2, iTime(m_symbol, m_timeframe, bar_shift));
         if(!ExtractTimeframeFeatures(features, feature_idx, m_timeframe2, bar_shift_tf2, lookback_bars,
                                        m_rsi_handle_tf2, m_rsi_fast_handle_tf2, m_macd_handle_tf2, m_atr_handle_tf2, m_bb_handle_tf2))
            return false;
      }
      
      //--- Extract features from TF3 if enabled
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
   
   //--- Extract features from a single timeframe
   bool ExtractTimeframeFeatures(double &features[], int &feature_idx, ENUM_TIMEFRAMES tf, int bar_shift, int lookback_bars,
                                   int rsi_h, int rsi_fast_h, int macd_h, int atr_h, int bb_h)
   {
      //--- Calculate total number of features
      // Features: RSI, RSI_Fast, MACD_Main, MACD_Signal, ATR, BB_Upper, BB_Lower, BB_Middle
      // Plus: Price patterns (last N bars normalized)
      // Plus: Hour of day, day of week
      
      //--- 1. Get indicator values
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
      
      //--- Normalize RSI values (0-100 -> 0-1)
      features[feature_idx++] = rsi[0] / 100.0;
      features[feature_idx++] = rsi_fast[0] / 100.0;
      
      //--- Normalize MACD (typically -0.5 to 0.5 for most pairs, normalize to -1 to 1)
      features[feature_idx++] = NormalizeValue(macd_main[0], -1.0, 1.0);
      features[feature_idx++] = NormalizeValue(macd_signal[0], -1.0, 1.0);
      
      //--- Normalize ATR (relative to price)
      double current_price = iClose(m_symbol, tf, bar_shift);
      features[feature_idx++] = (current_price > 0) ? (atr[0] / current_price) : 0.0;
      
      //--- Bollinger Bands (normalize position between bands)
      double bb_width = bb_upper[0] - bb_lower[0];
      if(bb_width > 0)
      {
         features[feature_idx++] = (bb_upper[0] - current_price) / bb_width; // Distance to upper
         features[feature_idx++] = (current_price - bb_lower[0]) / bb_width; // Distance to lower
         features[feature_idx++] = (current_price - bb_middle[0]) / bb_width; // Distance to middle
      }
      else
      {
         features[feature_idx++] = 0.5;
         features[feature_idx++] = 0.5;
         features[feature_idx++] = 0.0;
      }
      
      //--- 2. Price pattern features (normalized price changes)
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
      
      //--- 3. Time-based features
      MqlDateTime dt;
      TimeToStruct(iTime(m_symbol, tf, bar_shift), dt);
      
      features[feature_idx++] = dt.hour / 24.0; // Hour normalized
      features[feature_idx++] = dt.day_of_week / 7.0; // Day of week normalized
      
      return true;
   }
   
   //--- Normalize value between min and max to 0-1 range
   double NormalizeValue(double value, double min_val, double max_val)
   {
      if(max_val <= min_val) return 0.5;
      
      double normalized = (value - min_val) / (max_val - min_val);
      
      // Clamp to 0-1
      if(normalized < 0.0) normalized = 0.0;
      if(normalized > 1.0) normalized = 1.0;
      
      return normalized;
   }
};
//+------------------------------------------------------------------+
