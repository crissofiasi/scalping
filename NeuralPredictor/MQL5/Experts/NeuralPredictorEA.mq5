//+------------------------------------------------------------------+
//|                                         NeuralPredictorEA.mq5    |
//|                          Neural Network Market Move Predictor    |
//+------------------------------------------------------------------+
#property copyright "Neural Predictor EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <NeuroNetworksBook/realization/neuronnet.mqh>
#include <NeuroNetworksBook/realization/buffer.mqh>
#include <NeuroNetworksBook/realization/layerdescription.mqh>
#include <NNPredictorLib.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

//--- General Settings
input group "General Settings"
input string             Input_Symbol = "";                            // Symbol (empty = current)
input int                Input_Magic_Number = 20260223;                // Magic Number
input string             Input_Comment = "NN_Pred";                    // Trade Comment
input bool               Input_Enable_EA = true;                       // Master EA Enable

//--- Neural Network Settings
input group "Neural Network Settings"
input string             Input_Model_File = "NNPredictor_Model.nnw";  // Model Weights File
input double             Input_Min_Confidence = 0.65;                  // Minimum Confidence (0.5-1.0)
input double             Input_Target_Move_Pips = 10.0;                // Target Move in Pips
input bool               Input_Auto_Reload_Model = true;               // Auto-Reload Model if Updated
input int                Input_Prediction_Bar_Shift = 1;               // Bar Shift for Prediction
input ENUM_TIMEFRAMES    Input_Prediction_Timeframe = PERIOD_M5;       // Prediction Timeframe

//--- Multi-Timeframe Analysis
input group "Multi-Timeframe Analysis"
input bool               Input_Use_Multi_Timeframe = false;            // Enable Multi-Timeframe Analysis
input ENUM_TIMEFRAMES    Input_Timeframe_2 = PERIOD_M15;               // Timeframe 2 (Higher TF)
input ENUM_TIMEFRAMES    Input_Timeframe_3 = PERIOD_M30;               // Timeframe 3 (Highest TF)

//--- Feature Settings (Indicators for NN Input)
input group "Feature Settings"
input int                Input_RSI_Period = 14;                        // RSI Period
input int                Input_RSI_Fast_Period = 5;                    // RSI Fast Period
input int                Input_MACD_Fast = 12;                         // MACD Fast EMA
input int                Input_MACD_Slow = 26;                         // MACD Slow EMA
input int                Input_MACD_Signal = 9;                        // MACD Signal
input int                Input_ATR_Period = 14;                        // ATR Period
input int                Input_BB_Period = 20;                         // Bollinger Bands Period
input double             Input_BB_Deviation = 2.0;                     // BB Deviation
input int                Input_Lookback_Bars = 15;                     // Lookback Bars for Patterns

//--- Money Management
input group "Money Management"
input double             Input_Fixed_Lot = 0.01;                       // Fixed Lot Size
input bool               Input_Use_Auto_Lot = false;                   // Use Auto Lot (Risk %)
input double             Input_Risk_Percent = 1.0;                     // Risk Percent (if Auto Lot)
input double             Input_Max_Lot = 0.50;                         // Maximum Lot Size
input int                Input_Max_Open_Positions = 3;                 // Max Open Positions

//--- Trade Management
input group "Trade Management"
input bool               Input_Use_Stop_Loss = true;                   // Use Stop Loss
input double             Input_Stop_Loss_Pips = 20.0;                  // Stop Loss in Pips
input bool               Input_Use_Take_Profit = true;                 // Use Take Profit
input double             Input_Take_Profit_Pips = 30.0;                // Take Profit in Pips
input bool               Input_Use_Trailing_Stop = false;              // Use Trailing Stop
input double             Input_Trailing_Start_Pips = 15.0;             // Trailing Start Pips
input double             Input_Trailing_Step_Pips = 5.0;               // Trailing Step Pips
input bool               Input_Close_On_Opposite = true;               // Close on Opposite Signal

//--- Risk Management
input group "Risk Management"
input bool               Input_Use_Daily_Loss_Limit = true;            // Enable Daily Loss Limit
input double             Input_Daily_Loss_Limit = 100.0;               // Daily Loss Limit
input bool               Input_Use_Max_Spread = true;                  // Enable Max Spread Filter
input double             Input_Max_Spread_Pips = 3.0;                  // Max Spread in Pips

//--- Trading Hours
input group "Trading Hours"
input bool               Input_Use_Trading_Hours = false;              // Enable Trading Hours
input int                Input_Start_Hour = 0;                         // Start Hour
input int                Input_End_Hour = 23;                          // End Hour

//--- Debug
input group "Debug"
input bool               Input_Debug_Mode = false;                     // Debug Mode
input bool               Input_Show_Predictions = true;                // Show Predictions on Chart

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade               m_trade;
CNet                *m_network = NULL;
CNNPredictorLib     *m_predictor = NULL;

datetime             m_last_bar_time = 0;
datetime             m_model_last_modified = 0;
double               m_daily_loss = 0.0;
datetime             m_daily_reset_time = 0;
bool                 m_model_loaded = false;

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
   
   //--- Initialize predictor library
   m_predictor = new CNNPredictorLib();
   if(!m_predictor.Initialize(symbol, Input_Prediction_Timeframe, 
                               Input_RSI_Period, Input_RSI_Fast_Period,
                               Input_MACD_Fast, Input_MACD_Slow, Input_MACD_Signal,
                               Input_ATR_Period, Input_BB_Period, Input_BB_Deviation,
                               Input_Use_Multi_Timeframe, Input_Timeframe_2, Input_Timeframe_3))
   {
      Print("ERROR: Failed to initialize predictor indicators");
      delete m_predictor;
      return INIT_FAILED;
   }
   
   if(Input_Use_Multi_Timeframe)
   {
      Print("Multi-timeframe analysis enabled: TF1=", EnumToString(Input_Prediction_Timeframe),
            " TF2=", EnumToString(Input_Timeframe_2), " TF3=", EnumToString(Input_Timeframe_3));
   }
   
   //--- Create neural network
   m_network = new CNet();
   
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
   
   if(Input_Use_Multi_Timeframe)
   {
      Print("Multi-timeframe mode: ", EnumToString(Input_Prediction_Timeframe), " + ",
            EnumToString(Input_Timeframe_2), " + ", EnumToString(Input_Timeframe_3));
      Print("Expected features: 75 (25 per timeframe)");
   }
   else
   {
      Print("Single timeframe mode - Expected features: 25");
   }
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Delete objects (indicator handles are released by CNNPredictorLib destructor)
   if(m_network != NULL) delete m_network;
   if(m_predictor != NULL) delete m_predictor;
   
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
   
   //--- Create input buffer for CNet
   CBufferType *input_buffer = new CBufferType();
   if(!input_buffer)
   {
      Print("ERROR: Failed to allocate input buffer");
      confidence = 0.0;
      return 0;
   }
   
   if(!input_buffer.BufferInit(1, ArraySize(features), 0))
   {
      Print("ERROR: Failed to initialize input buffer");
      delete input_buffer;
      confidence = 0.0;
      return 0;
   }
   
   //--- Copy features to buffer matrix
   for(int i = 0; i < ArraySize(features); i++)
      input_buffer.m_mMatrix[0, i] = features[i];
   
   //--- Feed forward through network
   if(!m_network.FeedForward(input_buffer))
   {
      Print("ERROR: Neural network feed forward failed");
      delete input_buffer;
      confidence = 0.0;
      return 0;
   }
   
   //--- Get output results
   CBufferType *output_buffer = NULL;
   if(!m_network.GetResults(output_buffer))
   {
      Print("ERROR: Failed to get network results");
      delete input_buffer;
      confidence = 0.0;
      return 0;
   }
   
   if(!output_buffer)
   {
      Print("ERROR: Output buffer is NULL");
      delete input_buffer;
      confidence = 0.0;
      return 0;
   }
   
   //--- Extract output value
   if(output_buffer.m_mMatrix.Rows() == 0 || output_buffer.m_mMatrix.Cols() == 0)
   {
      Print("ERROR: Empty output matrix");
      delete input_buffer;
      confidence = 0.0;
      return 0;
   }
   
   double probability = output_buffer.m_mMatrix[0, 0]; // Output should be 0-1 (sigmoid)
   
   //--- Clean up buffers
   delete input_buffer;
   
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
   string common_path = TerminalInfoString(TERMINAL_COMMONDATA_PATH);
   string full_path = common_path + "\\Files\\" + filename;
   
   //--- Check if file exists
   if(!FileIsExist(filename, FILE_COMMON))
   {
      Print("ERROR: Model file not found!");
      Print("  Looking for: ", full_path);
      Print("  Please copy model_weights.nnw to the Common Files folder");
      return false;
   }
   
   Print("Loading Python-trained model from: ", full_path);
   
   //--- Create network architecture manually
   // Architecture: 71 -> 142 -> 71 -> 35 -> 1
   CArrayObj *descriptions = new CArrayObj();
   
   // Input layer (71 inputs)
   CLayerDescription *input_desc = new CLayerDescription();
   input_desc.type = defNeuronBase;
   input_desc.count = 71;  // Number of inputs (features)
   input_desc.window = 0;
   input_desc.activation = AF_NONE;  // Input layer, no activation
   input_desc.optimization = None;
   descriptions.Add(input_desc);
   
   // Hidden layer 1: 142 neurons, Swish activation
   CLayerDescription *hidden1_desc = new CLayerDescription();
   hidden1_desc.type = defNeuronBase;
   hidden1_desc.count = 142;
   hidden1_desc.window = 71;  // Input from previous layer
   hidden1_desc.activation = AF_SWISH;
   hidden1_desc.optimization = Adam;
   descriptions.Add(hidden1_desc);
   
   // Batch Normalization 1
   CLayerDescription *bn1_desc = new CLayerDescription();
   bn1_desc.type = defNeuronBatchNorm;
   bn1_desc.count = 142;
   bn1_desc.window = 142;
   bn1_desc.activation = AF_NONE;
   bn1_desc.optimization = Adam;
   descriptions.Add(bn1_desc);
   
   // Hidden layer 2: 71 neurons, Swish activation
   CLayerDescription *hidden2_desc = new CLayerDescription();
   hidden2_desc.type = defNeuronBase;
   hidden2_desc.count = 71;
   hidden2_desc.window = 142;
   hidden2_desc.activation = AF_SWISH;
   hidden2_desc.optimization = Adam;
   descriptions.Add(hidden2_desc);
   
   // Batch Normalization 2
   CLayerDescription *bn2_desc = new CLayerDescription();
   bn2_desc.type = defNeuronBatchNorm;
   bn2_desc.count = 71;
   bn2_desc.window = 71;
   bn2_desc.activation = AF_NONE;
   bn2_desc.optimization = Adam;
   descriptions.Add(bn2_desc);
   
   // Hidden layer 3: 35 neurons, Swish activation
   CLayerDescription *hidden3_desc = new CLayerDescription();
   hidden3_desc.type = defNeuronBase;
   hidden3_desc.count = 35;
   hidden3_desc.window = 71;
   hidden3_desc.activation = AF_SWISH;
   hidden3_desc.optimization = Adam;
   descriptions.Add(hidden3_desc);
   
   // Batch Normalization 3
   CLayerDescription *bn3_desc = new CLayerDescription();
   bn3_desc.type = defNeuronBatchNorm;
   bn3_desc.count = 35;
   bn3_desc.window = 35;
   bn3_desc.activation = AF_NONE;
   bn3_desc.optimization = Adam;
   descriptions.Add(bn3_desc);
   
   // Output layer: 1 neuron, Sigmoid activation
   CLayerDescription *output_desc = new CLayerDescription();
   output_desc.type = defNeuronBase;
   output_desc.count = 1;
   output_desc.window = 35;
   output_desc.activation = AF_SIGMOID;
   output_desc.optimization = Adam;
   descriptions.Add(output_desc);
   
   //--- Create network
   if(!m_network.Create(descriptions))
   {
      Print("ERROR: Failed to create network architecture");
      delete descriptions;
      return false;
   }
   
   delete descriptions;
   Print("✓ Network architecture created: 71->142->71->35->1");
   
   //--- Load weights from Python binary file
   int file_handle = FileOpen(filename, FILE_READ | FILE_BIN | FILE_SHARE_READ | FILE_COMMON);
   if(file_handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to open weights file: ", full_path);
      return false;
   }
   
   //--- Read header
   uint magic = FileReadInteger(file_handle);
   uint version = FileReadInteger(file_handle);
   uint num_layers = FileReadInteger(file_handle);
   
   Print("Weight file header: Magic=0x", IntegerToString(magic, 16), " Version=", version, " Layers=", num_layers);
   
   if(magic != 0x4E4E5720)  // "NNW "
   {
      Print("ERROR: Invalid magic number in weights file");
      FileClose(file_handle);
      return false;
   }
   
   if(num_layers != 4)  // We expect 4 layers (without batch norm)
   {
      Print("ERROR: Expected 4 layers, got ", num_layers);
      FileClose(file_handle);
      return false;
   }
   
   //--- Load weights from Python binary layers (we skip batch norm layers in weight loading)
   int dense_layer_indices[] = {1, 3, 5, 7};  // Indices of dense layers in CNet
   
   for(uint i = 0; i < num_layers; i++)
   {
      uint input_size = FileReadInteger(file_handle);
      uint output_size = FileReadInteger(file_handle);
      
      Print("Layer ", i, ": ", input_size, " -> ", output_size);
      
      //--- Get weights buffer using GetWeights method
      CBufferType *weights = m_network.GetWeights(dense_layer_indices[i]);
      if(!weights)
      {
         Print("ERROR: No weights buffer for layer ", dense_layer_indices[i]);
         FileClose(file_handle);
         return false;
      }
      
      //--- Read and set weights
      for(uint row = 0; row < input_size; row++)
      {
         for(uint col = 0; col < output_size; col++)
         {
            double w = FileReadDouble(file_handle);
            weights.m_mMatrix[row, col] = w;
         }
      }
      
      //--- Read and set bias
      for(uint col = 0; col < output_size; col++)
      {
         double b = FileReadDouble(file_handle);
         weights.m_mMatrix[input_size, col] = b;  // Bias is stored in last row
      }
      
      Print("✓ Loaded weights for layer ", i);
   }
   
   FileClose(file_handle);
   
   Print("✓ Model loaded successfully from: ", full_path);
   
   //--- Store file modification time
   m_model_last_modified = (datetime)FileGetInteger(filename, FILE_MODIFY_DATE, FILE_COMMON);
   
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
