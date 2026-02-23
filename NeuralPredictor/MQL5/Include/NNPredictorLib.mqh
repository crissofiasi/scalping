//+------------------------------------------------------------------+
//|                                           NNPredictorLib.mqh     |
//|                    Helper Library for Neural Predictor EA        |
//+------------------------------------------------------------------+
#property copyright "Neural Predictor Library"
#property version   "1.00"

#ifndef NNPREDICTORLIB_MQH
#define NNPREDICTORLIB_MQH

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
   }
   
   //--- Destructor
   ~CNNPredictorLib()
   {
      //--- Release primary timeframe indicators
      if(m_rsi_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_handle);
      if(m_rsi_fast_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_fast_handle);
      if(m_macd_handle != INVALID_HANDLE) IndicatorRelease(m_macd_handle);
      if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
      if(m_bb_handle != INVALID_HANDLE) IndicatorRelease(m_bb_handle);
      
      //--- Release timeframe 2 indicators
      if(m_rsi_handle_tf2 != INVALID_HANDLE) IndicatorRelease(m_rsi_handle_tf2);
      if(m_rsi_fast_handle_tf2 != INVALID_HANDLE) IndicatorRelease(m_rsi_fast_handle_tf2);
      if(m_macd_handle_tf2 != INVALID_HANDLE) IndicatorRelease(m_macd_handle_tf2);
      if(m_atr_handle_tf2 != INVALID_HANDLE) IndicatorRelease(m_atr_handle_tf2);
      if(m_bb_handle_tf2 != INVALID_HANDLE) IndicatorRelease(m_bb_handle_tf2);
      
      //--- Release timeframe 3 indicators
      if(m_rsi_handle_tf3 != INVALID_HANDLE) IndicatorRelease(m_rsi_handle_tf3);
      if(m_rsi_fast_handle_tf3 != INVALID_HANDLE) IndicatorRelease(m_rsi_fast_handle_tf3);
      if(m_macd_handle_tf3 != INVALID_HANDLE) IndicatorRelease(m_macd_handle_tf3);
      if(m_atr_handle_tf3 != INVALID_HANDLE) IndicatorRelease(m_atr_handle_tf3);
      if(m_bb_handle_tf3 != INVALID_HANDLE) IndicatorRelease(m_bb_handle_tf3);
   }
   
   //--- Setters
   void SetSymbol(string symbol) { m_symbol = symbol; }
   void SetTimeframe(ENUM_TIMEFRAMES tf) { m_timeframe = tf; }
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
   
   //--- Initialize indicators
   bool Initialize(string symbol, ENUM_TIMEFRAMES tf, int rsi_period, int rsi_fast_period,
                   int macd_fast, int macd_slow, int macd_signal, int atr_period,
                   int bb_period, double bb_deviation,
                   bool use_multi_tf = false, ENUM_TIMEFRAMES tf2 = PERIOD_CURRENT, ENUM_TIMEFRAMES tf3 = PERIOD_CURRENT)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_use_multi_tf = use_multi_tf;
      m_timeframe2 = tf2;
      m_timeframe3 = tf3;
      
      //--- Create primary timeframe indicators
      m_rsi_handle = iRSI(m_symbol, m_timeframe, rsi_period, PRICE_CLOSE);
      m_rsi_fast_handle = iRSI(m_symbol, m_timeframe, rsi_fast_period, PRICE_CLOSE);
      m_macd_handle = iMACD(m_symbol, m_timeframe, macd_fast, macd_slow, macd_signal, PRICE_CLOSE);
      m_atr_handle = iATR(m_symbol, m_timeframe, atr_period);
      m_bb_handle = iBands(m_symbol, m_timeframe, bb_period, 0, bb_deviation, PRICE_CLOSE);
      
      if(m_rsi_handle == INVALID_HANDLE || m_rsi_fast_handle == INVALID_HANDLE ||
         m_macd_handle == INVALID_HANDLE || m_atr_handle == INVALID_HANDLE || m_bb_handle == INVALID_HANDLE)
      {
         Print("Failed to create primary timeframe indicators");
         return false;
      }
      
      //--- Create multi-timeframe indicators if enabled
      if(m_use_multi_tf)
      {
         m_rsi_handle_tf2 = iRSI(m_symbol, m_timeframe2, rsi_period, PRICE_CLOSE);
         m_rsi_fast_handle_tf2 = iRSI(m_symbol, m_timeframe2, rsi_fast_period, PRICE_CLOSE);
         m_macd_handle_tf2 = iMACD(m_symbol, m_timeframe2, macd_fast, macd_slow, macd_signal, PRICE_CLOSE);
         m_atr_handle_tf2 = iATR(m_symbol, m_timeframe2, atr_period);
         m_bb_handle_tf2 = iBands(m_symbol, m_timeframe2, bb_period, 0, bb_deviation, PRICE_CLOSE);
         
         m_rsi_handle_tf3 = iRSI(m_symbol, m_timeframe3, rsi_period, PRICE_CLOSE);
         m_rsi_fast_handle_tf3 = iRSI(m_symbol, m_timeframe3, rsi_fast_period, PRICE_CLOSE);
         m_macd_handle_tf3 = iMACD(m_symbol, m_timeframe3, macd_fast, macd_slow, macd_signal, PRICE_CLOSE);
         m_atr_handle_tf3 = iATR(m_symbol, m_timeframe3, atr_period);
         m_bb_handle_tf3 = iBands(m_symbol, m_timeframe3, bb_period, 0, bb_deviation, PRICE_CLOSE);
         
         if(m_rsi_handle_tf2 == INVALID_HANDLE || m_rsi_fast_handle_tf2 == INVALID_HANDLE ||
            m_rsi_handle_tf3 == INVALID_HANDLE || m_rsi_fast_handle_tf3 == INVALID_HANDLE)
         {
            Print("Failed to create multi-timeframe indicators");
            return false;
         }
      }
      
      return true;
   }
   
   //--- Prepare features for neural network input
   bool PrepareFeatures(double &features[], int bar_shift, int lookback_bars)
   {
      //--- Calculate total number of features
      int num_indicators = 8;
      int num_price_features = lookback_bars;
      int num_time_features = 2;
      int features_per_tf = num_indicators + num_price_features + num_time_features;
      
      int num_timeframes = 1;
      if(m_use_multi_tf)
      {
         if(m_timeframe2 != PERIOD_CURRENT && m_rsi_handle_tf2 != INVALID_HANDLE) num_timeframes++;
         if(m_timeframe3 != PERIOD_CURRENT && m_rsi_handle_tf3 != INVALID_HANDLE) num_timeframes++;
      }
      
      int total_features = features_per_tf * num_timeframes;
      
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
      
      return true;
   }
   
   //--- Extract features from a single timeframe
   bool ExtractTimeframeFeatures(double &features[], int &feature_idx, ENUM_TIMEFRAMES tf, int bar_shift, int lookback_bars,
                                   int rsi_h, int rsi_fast_h, int macd_h, int atr_h, int bb_h)
   {
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

#endif // NNPREDICTORLIB_MQH
//+------------------------------------------------------------------+
