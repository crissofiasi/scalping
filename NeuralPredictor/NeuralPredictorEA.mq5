//+------------------------------------------------------------------+
//|                                         NeuralPredictorEA.mq5    |
//|                          Neural Network Market Move Predictor    |
//+------------------------------------------------------------------+
#property copyright "Neural Predictor EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include "../mql5/Include/NeuroNetworksBook/realization/neuronnet.mqh"
#include "NNPredictorLib.mqh"

// Type alias for compatibility
#define CNeuronNet CNet

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

//--- General Settings
input group "═══════════ General Settings ═══════════"
input string             Input_Symbol = "";                            // Symbol (empty = current)
input int                Input_Magic_Number = 20260223;                // Magic Number
input string             Input_Comment = "NN_Pred";                    // Trade Comment
input bool               Input_Enable_EA = true;                       // Master EA Enable

//--- Neural Network Settings
input group "═══════════ Neural Network Settings ═══════════"
input string             Input_Model_File = "NNPredictor_Model.nnw";  // Model Weights File
input double             Input_Min_Confidence = 0.65;                  // Minimum Confidence (0.5-1.0)
input double             Input_Target_Move_Pips = 10.0;                // Target Move in Pips
input bool               Input_Auto_Reload_Model = true;               // Auto-Reload Model if Updated
input int                Input_Prediction_Bar_Shift = 1;               // Bar Shift for Prediction
input ENUM_TIMEFRAMES    Input_Prediction_Timeframe = PERIOD_M5;       // Prediction Timeframe

//--- Multi-Timeframe Analysis
input group "═══════════ Multi-Timeframe Analysis ═══════════"
input bool               Input_Use_Multi_Timeframe = false;            // Enable Multi-Timeframe Analysis
input ENUM_TIMEFRAMES    Input_Timeframe_2 = PERIOD_M15;               // Timeframe 2 (Higher TF)
input ENUM_TIMEFRAMES    Input_Timeframe_3 = PERIOD_M30;               // Timeframe 3 (Highest TF)

//--- Feature Settings (Indicators for NN Input)
input group "═══════════ Feature Settings ═══════════"
input bool               Input_Use_Parameter_Features = true;          // Include EA Parameters in Model
input int                Input_RSI_Period = 14;                        // RSI Period
input int                Input_RSI_Fast_Period = 5;                    // RSI Fast Period
input int                Input_MACD_Fast = 12;                         // MACD Fast EMA
input int                Input_MACD_Slow = 26;                         // MACD Slow EMA
input int                Input_MACD_Signal = 9;                        // MACD Signal
input int                Input_ATR_Period = 14;                        // ATR Period
input int                Input_BB_Period = 20;                         // Bollinger Bands Period
input double             Input_BB_Deviation = 2.0;                     // BB Deviation
input int                Input_Lookback_Bars = 61;                     // Lookback Bars for Patterns (MUST match training data!)

//--- Money Management
input group "═══════════ Money Management ═══════════"
input double             Input_Fixed_Lot = 0.01;                       // Fixed Lot Size
input bool               Input_Use_Auto_Lot = false;                   // Use Auto Lot (Risk %)
input double             Input_Risk_Percent = 1.0;                     // Risk Percent (if Auto Lot)
input double             Input_Max_Lot = 0.50;                         // Maximum Lot Size
input int                Input_Max_Open_Positions = 3;                 // Max Open Positions

//--- Trade Management
input group "═══════════ Trade Management ═══════════"
input bool               Input_Use_Stop_Loss = true;                   // Use Stop Loss
input double             Input_Stop_Loss_Pips = 20.0;                  // Stop Loss in Pips
input bool               Input_Use_Take_Profit = true;                 // Use Take Profit
input double             Input_Take_Profit_Pips = 30.0;                // Take Profit in Pips
input bool               Input_Use_Trailing_Stop = false;              // Use Trailing Stop
input double             Input_Trailing_Start_Pips = 15.0;             // Trailing Start Pips
input double             Input_Trailing_Step_Pips = 5.0;               // Trailing Step Pips
input bool               Input_Close_On_Opposite = true;               // Close on Opposite Signal

//--- Risk Management
input group "═══════════ Risk Management ═══════════"
input bool               Input_Use_Daily_Loss_Limit = true;            // Enable Daily Loss Limit
input double             Input_Daily_Loss_Limit = 100.0;               // Daily Loss Limit
input bool               Input_Use_Max_Spread = true;                  // Enable Max Spread Filter
input double             Input_Max_Spread_Pips = 3.0;                  // Max Spread in Pips

//--- Trading Hours
input group "═══════════ Trading Hours ═══════════"
input bool               Input_Use_Trading_Hours = false;              // Enable Trading Hours
input int                Input_Start_Hour = 0;                         // Start Hour
input int                Input_End_Hour = 23;                          // End Hour

//--- Debug
input group "═══════════ Debug ═══════════"
input bool               Input_Debug_Mode = false;                     // Debug Mode
input bool               Input_Show_Predictions = true;                // Show Predictions on Chart

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade               m_trade;
CNeuronNet          *m_network = NULL;
CNNPredictorLib     *m_predictor = NULL;
CBufferType         *m_input_buffer = NULL;
CBufferType         *m_output_buffer = NULL;

datetime             m_last_bar_time = 0;
datetime             m_model_last_modified = 0;
double               m_daily_loss = 0.0;
datetime             m_daily_reset_time = 0;
bool                 m_model_loaded = false;

//--- Indicator handles
int                  m_rsi_handle = INVALID_HANDLE;
int                  m_rsi_fast_handle = INVALID_HANDLE;
int                  m_macd_handle = INVALID_HANDLE;
int                  m_atr_handle = INVALID_HANDLE;
int                  m_bb_handle = INVALID_HANDLE;

//--- Multi-timeframe indicator handles
int                  m_rsi_handle_tf2 = INVALID_HANDLE;
int                  m_rsi_fast_handle_tf2 = INVALID_HANDLE;
int                  m_macd_handle_tf2 = INVALID_HANDLE;
int                  m_atr_handle_tf2 = INVALID_HANDLE;
int                  m_bb_handle_tf2 = INVALID_HANDLE;

int                  m_rsi_handle_tf3 = INVALID_HANDLE;
int                  m_rsi_fast_handle_tf3 = INVALID_HANDLE;
int                  m_macd_handle_tf3 = INVALID_HANDLE;
int                  m_atr_handle_tf3 = INVALID_HANDLE;
int                  m_bb_handle_tf3 = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   //--- Initialize trade object
   m_trade.SetExpertMagicNumber(Input_Magic_Number);
   m_trade.SetDeviationInPoints(30);
   m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   //--- Initialize indicators
   m_rsi_handle = iRSI(symbol, Input_Prediction_Timeframe, Input_RSI_Period, PRICE_CLOSE);
   m_rsi_fast_handle = iRSI(symbol, Input_Prediction_Timeframe, Input_RSI_Fast_Period, PRICE_CLOSE);
   m_macd_handle = iMACD(symbol, Input_Prediction_Timeframe, Input_MACD_Fast, Input_MACD_Slow, Input_MACD_Signal, PRICE_CLOSE);
   m_atr_handle = iATR(symbol, Input_Prediction_Timeframe, Input_ATR_Period);
   m_bb_handle = iBands(symbol, Input_Prediction_Timeframe, Input_BB_Period, 0, Input_BB_Deviation, PRICE_CLOSE);
   
   if(m_rsi_handle == INVALID_HANDLE || m_rsi_fast_handle == INVALID_HANDLE || 
      m_macd_handle == INVALID_HANDLE || m_atr_handle == INVALID_HANDLE || 
      m_bb_handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicators");
      return INIT_FAILED;
   }
   
   //--- Initialize multi-timeframe indicators if enabled
   if(Input_Use_Multi_Timeframe)
   {
      m_rsi_handle_tf2 = iRSI(symbol, Input_Timeframe_2, Input_RSI_Period, PRICE_CLOSE);
      m_rsi_fast_handle_tf2 = iRSI(symbol, Input_Timeframe_2, Input_RSI_Fast_Period, PRICE_CLOSE);
      m_macd_handle_tf2 = iMACD(symbol, Input_Timeframe_2, Input_MACD_Fast, Input_MACD_Slow, Input_MACD_Signal, PRICE_CLOSE);
      m_atr_handle_tf2 = iATR(symbol, Input_Timeframe_2, Input_ATR_Period);
      m_bb_handle_tf2 = iBands(symbol, Input_Timeframe_2, Input_BB_Period, 0, Input_BB_Deviation, PRICE_CLOSE);
      
      m_rsi_handle_tf3 = iRSI(symbol, Input_Timeframe_3, Input_RSI_Period, PRICE_CLOSE);
      m_rsi_fast_handle_tf3 = iRSI(symbol, Input_Timeframe_3, Input_RSI_Fast_Period, PRICE_CLOSE);
      m_macd_handle_tf3 = iMACD(symbol, Input_Timeframe_3, Input_MACD_Fast, Input_MACD_Slow, Input_MACD_Signal, PRICE_CLOSE);
      m_atr_handle_tf3 = iATR(symbol, Input_Timeframe_3, Input_ATR_Period);
      m_bb_handle_tf3 = iBands(symbol, Input_Timeframe_3, Input_BB_Period, 0, Input_BB_Deviation, PRICE_CLOSE);
      
      if(m_rsi_handle_tf2 == INVALID_HANDLE || m_rsi_fast_handle_tf2 == INVALID_HANDLE ||
         m_rsi_handle_tf3 == INVALID_HANDLE || m_rsi_fast_handle_tf3 == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create multi-timeframe indicators");
         return INIT_FAILED;
      }
      
      Print("Multi-timeframe analysis enabled: TF1=", EnumToString(Input_Prediction_Timeframe),
            " TF2=", EnumToString(Input_Timeframe_2), " TF3=", EnumToString(Input_Timeframe_3));
   }
   
   //--- Initialize predictor library
   m_predictor = new CNNPredictorLib();
   m_predictor.SetSymbol(symbol);
   m_predictor.SetTimeframe(Input_Prediction_Timeframe);
   m_predictor.SetIndicatorHandles(m_rsi_handle, m_rsi_fast_handle, m_macd_handle, m_atr_handle, m_bb_handle);
   
   //--- Set multi-timeframe if enabled
   if(Input_Use_Multi_Timeframe)
   {
      m_predictor.EnableMultiTimeframe(true, Input_Timeframe_2, Input_Timeframe_3);
      m_predictor.SetIndicatorHandlesTF2(m_rsi_handle_tf2, m_rsi_fast_handle_tf2, m_macd_handle_tf2, m_atr_handle_tf2, m_bb_handle_tf2);
      m_predictor.SetIndicatorHandlesTF3(m_rsi_handle_tf3, m_rsi_fast_handle_tf3, m_macd_handle_tf3, m_atr_handle_tf3, m_bb_handle_tf3);
   }
   
   //--- Set parameter features if enabled
   if(Input_Use_Parameter_Features)
   {
      SParameterFeatures params;
      params.stop_loss_pips = Input_Stop_Loss_Pips;
      params.take_profit_pips = Input_Take_Profit_Pips;
      params.target_move_pips = Input_Target_Move_Pips;
      params.risk_percent = Input_Risk_Percent;
      params.max_positions = Input_Max_Open_Positions;
      params.use_trading_hours = Input_Use_Trading_Hours;
      params.use_multi_tf = Input_Use_Multi_Timeframe;
      params.timeframe1 = Input_Prediction_Timeframe;
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
      
      m_predictor.EnableParameterFeatures(true);
      m_predictor.SetParameters(params);
      
      Print("Parameter features ENABLED - Model will receive EA settings as inputs");
   }
   else
   {
      Print("Parameter features DISABLED - Model receives only market data");
   }
   
   //--- Create neural network
   m_network = new CNeuronNet();
   
   //--- Create buffer objects for NN input/output
   m_input_buffer = new CBufferType();
   m_output_buffer = new CBufferType();
   
   if(m_input_buffer == NULL || m_output_buffer == NULL)
   {
      Print("ERROR: Failed to create buffer objects");
      return INIT_FAILED;
   }
   
   //--- Load trained model
   if(!LoadModel())
   {
      Print("WARNING: Failed to load model file: ", Input_Model_File);
      Print("EA will wait for model file to be available");
      m_model_loaded = false;
   }
   else
   {
      m_model_loaded = true;
      Print("Neural network model loaded successfully");
   }
   
   //--- Initialize bar time
   m_last_bar_time = iTime(symbol, Input_Prediction_Timeframe, 0);
   m_daily_reset_time = TimeCurrent();
   
   Print("NeuralPredictorEA initialized successfully");
   Print("Symbol: ", symbol, " | Timeframe: ", EnumToString(Input_Prediction_Timeframe));
   Print("Target Move: ", Input_Target_Move_Pips, " pips | Min Confidence: ", Input_Min_Confidence);
   Print("Lookback Bars: ", Input_Lookback_Bars);
   
   // Calculate expected features
   int expected_features = 8 + Input_Lookback_Bars + 2; // indicators + lookback + time
   int param_features = Input_Use_Parameter_Features ? 18 : 0; // parameter features
   
   if(Input_Use_Multi_Timeframe)
   {
      Print("Multi-timeframe mode: ", EnumToString(Input_Prediction_Timeframe), " + ",
            EnumToString(Input_Timeframe_2), " + ", EnumToString(Input_Timeframe_3));
      Print("Expected features: ", (expected_features * 3 + param_features), 
            " (", expected_features, " x 3 timeframes + ", param_features, " params)");
   }
   else
   {
      Print("Single timeframe mode - Expected features: ", (expected_features + param_features),
            " (", expected_features, " market + ", param_features, " params)");
   }
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   if(m_rsi_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_handle);
   if(m_rsi_fast_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_fast_handle);
   if(m_macd_handle != INVALID_HANDLE) IndicatorRelease(m_macd_handle);
   if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
   if(m_bb_handle != INVALID_HANDLE) IndicatorRelease(m_bb_handle);
   
   //--- Release multi-timeframe handles
   if(m_rsi_handle_tf2 != INVALID_HANDLE) IndicatorRelease(m_rsi_handle_tf2);
   if(m_rsi_fast_handle_tf2 != INVALID_HANDLE) IndicatorRelease(m_rsi_fast_handle_tf2);
   if(m_macd_handle_tf2 != INVALID_HANDLE) IndicatorRelease(m_macd_handle_tf2);
   if(m_atr_handle_tf2 != INVALID_HANDLE) IndicatorRelease(m_atr_handle_tf2);
   if(m_bb_handle_tf2 != INVALID_HANDLE) IndicatorRelease(m_bb_handle_tf2);
   
   if(m_rsi_handle_tf3 != INVALID_HANDLE) IndicatorRelease(m_rsi_handle_tf3);
   if(m_rsi_fast_handle_tf3 != INVALID_HANDLE) IndicatorRelease(m_rsi_fast_handle_tf3);
   if(m_macd_handle_tf3 != INVALID_HANDLE) IndicatorRelease(m_macd_handle_tf3);
   if(m_atr_handle_tf3 != INVALID_HANDLE) IndicatorRelease(m_atr_handle_tf3);
   if(m_bb_handle_tf3 != INVALID_HANDLE) IndicatorRelease(m_bb_handle_tf3);
   
   //--- Delete objects
   if(m_network != NULL) delete m_network;
   if(m_predictor != NULL) delete m_predictor;
   if(m_input_buffer != NULL) delete m_input_buffer;
   if(m_output_buffer != NULL) delete m_output_buffer;
   
   Print("NeuralPredictorEA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!Input_Enable_EA) return;
   
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   //--- Check for new bar
   datetime current_bar_time = iTime(symbol, Input_Prediction_Timeframe, 0);
   if(current_bar_time != m_last_bar_time)
   {
      m_last_bar_time = current_bar_time;
      
      //--- Auto-reload model if file updated
      if(Input_Auto_Reload_Model && m_model_loaded)
      {
         CheckAndReloadModel();
      }
      
      //--- Try to load model if not loaded yet
      if(!m_model_loaded)
      {
         if(LoadModel())
         {
            m_model_loaded = true;
            Print("Model loaded successfully on retry");
         }
      }
      
      //--- Process new bar
      if(m_model_loaded)
      {
         ProcessNewBar();
      }
   }
   
   //--- Update trailing stops
   if(Input_Use_Trailing_Stop)
   {
      UpdateTrailingStops();
   }
}

//+------------------------------------------------------------------+
//| Process new bar                                                   |
//+------------------------------------------------------------------+
void ProcessNewBar()
{
   //--- Check risk management
   if(!CheckRiskManagement()) return;
   
   //--- Check trading hours
   if(Input_Use_Trading_Hours && !IsWithinTradingHours()) return;
   
   //--- Check spread
   if(Input_Use_Max_Spread && !IsSpreadAcceptable()) return;
   
   //--- Get prediction from neural network
   double confidence = 0.0;
   int prediction = GetPrediction(confidence);
   
   if(Input_Debug_Mode || Input_Show_Predictions)
   {
      Print("Prediction: ", prediction == 1 ? "BUY" : (prediction == -1 ? "SELL" : "NEUTRAL"), 
            " | Confidence: ", DoubleToString(confidence * 100, 2), "%");
   }
   
   //--- Check if confidence meets threshold
   if(confidence < Input_Min_Confidence)
   {
      if(Input_Debug_Mode)
         Print("Confidence too low: ", confidence, " < ", Input_Min_Confidence);
      return;
   }
   
   //--- Count open positions
   int open_positions = CountOpenPositions();
   if(open_positions >= Input_Max_Open_Positions)
   {
      if(Input_Debug_Mode)
         Print("Max open positions reached: ", open_positions);
      return;
   }
   
   //--- Execute trade based on prediction
   if(prediction == 1) // BUY signal
   {
      //--- Close opposite positions if enabled
      if(Input_Close_On_Opposite)
         ClosePositionsByType(POSITION_TYPE_SELL);
      
      //--- Open BUY position
      OpenPosition(ORDER_TYPE_BUY, confidence);
   }
   else if(prediction == -1) // SELL signal
   {
      //--- Close opposite positions if enabled
      if(Input_Close_On_Opposite)
         ClosePositionsByType(POSITION_TYPE_BUY);
      
      //--- Open SELL position
      OpenPosition(ORDER_TYPE_SELL, confidence);
   }
}

//+------------------------------------------------------------------+
//| Get prediction from neural network                                |
//+------------------------------------------------------------------+
int GetPrediction(double &confidence)
{
   //--- Prepare input features
   double features[];
   if(!m_predictor.PrepareFeatures(features, Input_Prediction_Bar_Shift, Input_Lookback_Bars))
   {
      Print("ERROR: Failed to prepare features");
      confidence = 0.0;
      return 0;
   }
   
   int num_features = ArraySize(features);
   if(num_features == 0)
   {
      Print("ERROR: No features prepared");
      confidence = 0.0;
      return 0;
   }
   
   if(Input_Debug_Mode)
   {
      Print("Features prepared: ", num_features, " (Expected: ", (8 + Input_Lookback_Bars + 2), ")");
   }
   
   //--- Initialize input buffer with features
   if(!m_input_buffer.BufferInit(1, num_features, 0.0))
   {
      Print("ERROR: Failed to initialize input buffer");
      confidence = 0.0;
      return 0;
   }
   
   //--- Copy features to buffer matrix
   for(int i = 0; i < num_features; i++)
   {
      m_input_buffer.m_mMatrix[0, i] = (TYPE)features[i];
   }
   
   //--- Feed forward through network
   if(!m_network.FeedForward(m_input_buffer))
   {
      Print("ERROR: Neural network feed forward failed");
      confidence = 0.0;
      return 0;
   }
   
   //--- Get output (probability of upward move)
   if(!m_network.GetResults(m_output_buffer))
   {
      Print("ERROR: Failed to get network results");
      confidence = 0.0;
      return 0;
   }
   
   if(m_output_buffer.Total() == 0)
   {
      Print("ERROR: No network outputs");
      confidence = 0.0;
      return 0;
   }
   
   double probability = (double)m_output_buffer.At(0); // Output should be 0-1 (sigmoid)
   
   //--- Interpret output
   // probability > 0.5 = BUY (expecting upward move)
   // probability < 0.5 = SELL (expecting downward move)
   
   if(probability > 0.5)
   {
      confidence = probability; // Confidence for BUY
      return 1; // BUY
   }
   else
   {
      confidence = 1.0 - probability; // Confidence for SELL
      return -1; // SELL
   }
}

//+------------------------------------------------------------------+
//| Open position                                                     |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE order_type, double confidence)
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   //--- Calculate lot size
   double lot = CalculateLotSize();
   if(lot <= 0.0)
   {
      Print("ERROR: Invalid lot size calculated");
      return;
   }
   
   //--- Get price
   double price = (order_type == ORDER_TYPE_BUY) ? 
                   SymbolInfoDouble(symbol, SYMBOL_ASK) : 
                   SymbolInfoDouble(symbol, SYMBOL_BID);
   
   //--- Calculate SL and TP
   double sl = 0.0, tp = 0.0;
   
   if(Input_Use_Stop_Loss || Input_Use_Take_Profit)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      
      if(Input_Use_Stop_Loss)
      {
         if(order_type == ORDER_TYPE_BUY)
            sl = NormalizeDouble(price - Input_Stop_Loss_Pips * 10 * point, digits);
         else
            sl = NormalizeDouble(price + Input_Stop_Loss_Pips * 10 * point, digits);
      }
      
      if(Input_Use_Take_Profit)
      {
         if(order_type == ORDER_TYPE_BUY)
            tp = NormalizeDouble(price + Input_Take_Profit_Pips * 10 * point, digits);
         else
            tp = NormalizeDouble(price - Input_Take_Profit_Pips * 10 * point, digits);
      }
   }
   
   //--- Open position
   bool success = false;
   string comment = Input_Comment + "_" + DoubleToString(confidence * 100, 0);
   
   if(order_type == ORDER_TYPE_BUY)
   {
      success = m_trade.Buy(lot, symbol, price, sl, tp, comment);
   }
   else
   {
      success = m_trade.Sell(lot, symbol, price, sl, tp, comment);
   }
   
   if(success)
   {
      Print("Position opened: ", EnumToString(order_type), " | Lot: ", lot, 
            " | Price: ", price, " | Confidence: ", DoubleToString(confidence * 100, 2), "%");
   }
   else
   {
      Print("ERROR: Failed to open position. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   double lot = Input_Fixed_Lot;
   
   if(Input_Use_Auto_Lot)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk_amount = balance * Input_Risk_Percent / 100.0;
      
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double sl_points = Input_Stop_Loss_Pips * 10;
      
      if(sl_points > 0 && tick_value > 0)
      {
         lot = risk_amount / (sl_points * tick_value);
      }
   }
   
   //--- Normalize lot
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   lot = MathFloor(lot / lot_step) * lot_step;
   lot = MathMax(lot, min_lot);
   lot = MathMin(lot, Input_Max_Lot);
   lot = MathMin(lot, max_lot);
   
   return lot;
}

//+------------------------------------------------------------------+
//| Load neural network model                                         |
//+------------------------------------------------------------------+
bool LoadModel()
{
   string filename = Input_Model_File;
   
   //--- Check if file exists
   if(!FileIsExist(filename, FILE_COMMON))
   {
      if(Input_Debug_Mode)
         Print("Model file not found: ", filename);
      return false;
   }
   
   //--- Calculate expected input features
   int features_per_tf = 8 + Input_Lookback_Bars + 2; // indicators + lookback + time
   int param_features = Input_Use_Parameter_Features ? 18 : 0;
   int input_features = Input_Use_Multi_Timeframe ? (features_per_tf * 3 + param_features) : (features_per_tf + param_features);
   
   //--- Create network architecture BEFORE loading weights
   //--- Architecture: input_features -> [input*2, input, input/2] -> 1
   CLayerDescription *desc = NULL;
   
   // Clear any existing layers
   if(!m_network.Clear())
   {
      Print("ERROR: Failed to clear network");
      return false;
   }
   
   // Layer 1: Input layer
   desc = new CLayerDescription();
   desc.type = defNeuronBaseOCL;
   desc.count = input_features;
   desc.window = 0;
   desc.optimization = ADAM;
   desc.activation = AF_SWISH;
   if(!m_network.Add(desc))
   {
      Print("ERROR: Failed to add input layer");
      delete desc;
      return false;
   }
   delete desc;
   
   // Layer 2: Hidden layer 1 (input*2)
   desc = new CLayerDescription();
   desc.type = defNeuronBaseOCL;
   desc.count = input_features * 2;
   desc.optimization = ADAM;
   desc.activation = AF_SWISH;
   if(!m_network.Add(desc))
   {
      Print("ERROR: Failed to add hidden layer 1");
      delete desc;
      return false;
   }
   delete desc;
   
   // Layer 3: Hidden layer 2 (input)
   desc = new CLayerDescription();
   desc.type = defNeuronBaseOCL;
   desc.count = input_features;
   desc.optimization = ADAM;
   desc.activation = AF_SWISH;
   if(!m_network.Add(desc))
   {
      Print("ERROR: Failed to add hidden layer 2");
      delete desc;
      return false;
   }
   delete desc;
   
   // Layer 4: Hidden layer 3 (input/2)
   desc = new CLayerDescription();
   desc.type = defNeuronBaseOCL;
   desc.count = (int)MathMax(input_features / 2, 10);
   desc.optimization = ADAM;
   desc.activation = AF_SWISH;
   if(!m_network.Add(desc))
   {
      Print("ERROR: Failed to add hidden layer 3");
      delete desc;
      return false;
   }
   delete desc;
   
   // Layer 5: Output layer
   desc = new CLayerDescription();
   desc.type = defNeuronBaseOCL;
   desc.count = 1;
   desc.optimization = ADAM;
   desc.activation = AF_SIGMOID;
   if(!m_network.Add(desc))
   {
      Print("ERROR: Failed to add output layer");
      delete desc;
      return false;
   }
   delete desc;
   
   Print("Created network architecture: ", input_features, " -> [", input_features*2, ", ", input_features, ", ", input_features/2, "] -> 1");
   
   //--- Load weights (correct Load method signature)
   if(!m_network.Load(filename, true))
   {
      Print("ERROR: Failed to load neural network weights from ", filename);
      Print("Make sure the model was trained with ", input_features, " input features");
      return false;
   }
   
   //--- Store file modification time
   m_model_last_modified = (datetime)FileGetInteger(filename, FILE_MODIFY_DATE, FILE_COMMON);
   
   Print("Model loaded successfully with ", input_features, " input features");
   
   return true;
}

//+------------------------------------------------------------------+
//| Check and reload model if updated                                 |
//+------------------------------------------------------------------+
void CheckAndReloadModel()
{
   string filename = Input_Model_File;
   
   if(!FileIsExist(filename, FILE_COMMON))
      return;
   
   datetime file_time = (datetime)FileGetInteger(filename, FILE_MODIFY_DATE, FILE_COMMON);
   
   if(file_time > m_model_last_modified)
   {
      Print("Model file updated. Reloading...");
      if(LoadModel())
      {
         Print("Model reloaded successfully");
      }
   }
}

//+------------------------------------------------------------------+
//| Count open positions                                              |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number)
         {
            count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Close positions by type                                           |
//+------------------------------------------------------------------+
void ClosePositionsByType(ENUM_POSITION_TYPE pos_type)
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number &&
            PositionGetInteger(POSITION_TYPE) == pos_type)
         {
            m_trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update trailing stops                                             |
//+------------------------------------------------------------------+
void UpdateTrailingStops()
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   double trailing_start = Input_Trailing_Start_Pips * 10 * point;
   double trailing_step = Input_Trailing_Step_Pips * 10 * point;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number)
         {
            double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            double price_current = (pos_type == POSITION_TYPE_BUY) ? 
                                   SymbolInfoDouble(symbol, SYMBOL_BID) : 
                                   SymbolInfoDouble(symbol, SYMBOL_ASK);
            
            double profit_distance = (pos_type == POSITION_TYPE_BUY) ? 
                                     price_current - price_open : 
                                     price_open - price_current;
            
            if(profit_distance >= trailing_start)
            {
               double new_sl = 0.0;
               
               if(pos_type == POSITION_TYPE_BUY)
               {
                  new_sl = NormalizeDouble(price_current - trailing_step, digits);
                  if(new_sl > sl || sl == 0.0)
                  {
                     m_trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
                  }
               }
               else
               {
                  new_sl = NormalizeDouble(price_current + trailing_step, digits);
                  if(new_sl < sl || sl == 0.0)
                  {
                     m_trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check risk management                                             |
//+------------------------------------------------------------------+
bool CheckRiskManagement()
{
   //--- Check daily loss limit
   if(Input_Use_Daily_Loss_Limit)
   {
      //--- Reset daily loss
      MqlDateTime dt_current, dt_reset;
      TimeToStruct(TimeCurrent(), dt_current);
      TimeToStruct(m_daily_reset_time, dt_reset);
      
      if(dt_current.day != dt_reset.day)
      {
         m_daily_loss = 0.0;
         m_daily_reset_time = TimeCurrent();
      }
      
      //--- Calculate daily loss
      CalculateDailyLoss();
      
      if(m_daily_loss >= Input_Daily_Loss_Limit)
      {
         if(Input_Debug_Mode)
            Print("Daily loss limit reached: ", m_daily_loss);
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate daily loss                                              |
//+------------------------------------------------------------------+
void CalculateDailyLoss()
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   m_daily_loss = 0.0;
   
   MqlDateTime dt_today;
   TimeToStruct(TimeCurrent(), dt_today);
   dt_today.hour = 0;
   dt_today.min = 0;
   dt_today.sec = 0;
   datetime today_start = StructToTime(dt_today);
   
   HistorySelect(today_start, TimeCurrent());
   
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Input_Magic_Number &&
            HistoryDealGetString(ticket, DEAL_SYMBOL) == symbol &&
            HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            if(profit < 0.0)
               m_daily_loss += MathAbs(profit);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                     |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   if(Input_Start_Hour <= Input_End_Hour)
   {
      return (dt.hour >= Input_Start_Hour && dt.hour <= Input_End_Hour);
   }
   else
   {
      return (dt.hour >= Input_Start_Hour || dt.hour <= Input_End_Hour);
   }
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                     |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   double spread_pips = (ask - bid) / (10 * point);
   
   if(spread_pips > Input_Max_Spread_Pips)
   {
      if(Input_Debug_Mode)
         Print("Spread too high: ", spread_pips, " pips");
      return false;
   }
   
   return true;
}
//+------------------------------------------------------------------+
