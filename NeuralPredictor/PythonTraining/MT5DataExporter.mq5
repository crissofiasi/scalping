//+------------------------------------------------------------------+
//|                                              MT5DataExporter.mq5 |
//|                                   Neural Predictor Training Data |
//|                         Exports historical data for Python ML    |
//+------------------------------------------------------------------+
#property copyright "Neural Predictor System"
#property version   "1.00"
#property script_show_inputs

#include "../NNPredictorLib.mqh"

//--- Input parameters
input int      Input_Export_Bars = 10000;           // Bars to export
input double   Input_Target_Move_Pips = 10.0;       // Target move for labeling (pips)
input int      Input_Lookforward_Bars = 15;         // Bars to look ahead for label
input bool     Input_Use_Multi_Timeframe = false;   // Export multi-timeframe data
input ENUM_TIMEFRAMES Input_Timeframe_2 = PERIOD_M15;  // Second timeframe (if MTA)
input ENUM_TIMEFRAMES Input_Timeframe_3 = PERIOD_M30;  // Third timeframe (if MTA)
input string   Input_Output_Filename = "nn_training_data.csv";  // Output filename

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
   
   //--- Initialize indicators for primary timeframe
   g_rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
   g_rsi_fast_handle = iRSI(_Symbol, PERIOD_CURRENT, 5, PRICE_CLOSE);
   g_macd_handle = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   g_atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
   g_bb_handle = iBands(_Symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   
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
      
      // Initialize TF2 indicators
      g_rsi_handle_tf2 = iRSI(_Symbol, Input_Timeframe_2, 14, PRICE_CLOSE);
      g_rsi_fast_handle_tf2 = iRSI(_Symbol, Input_Timeframe_2, 5, PRICE_CLOSE);
      g_macd_handle_tf2 = iMACD(_Symbol, Input_Timeframe_2, 12, 26, 9, PRICE_CLOSE);
      g_atr_handle_tf2 = iATR(_Symbol, Input_Timeframe_2, 14);
      g_bb_handle_tf2 = iBands(_Symbol, Input_Timeframe_2, 20, 0, 2.0, PRICE_CLOSE);
      
      g_lib.SetIndicatorHandlesTF2(g_rsi_handle_tf2, g_rsi_fast_handle_tf2, 
                                    g_macd_handle_tf2, g_atr_handle_tf2, g_bb_handle_tf2);
      
      // Initialize TF3 indicators
      g_rsi_handle_tf3 = iRSI(_Symbol, Input_Timeframe_3, 14, PRICE_CLOSE);
      g_rsi_fast_handle_tf3 = iRSI(_Symbol, Input_Timeframe_3, 5, PRICE_CLOSE);
      g_macd_handle_tf3 = iMACD(_Symbol, Input_Timeframe_3, 12, 26, 9, PRICE_CLOSE);
      g_atr_handle_tf3 = iATR(_Symbol, Input_Timeframe_3, 14);
      g_bb_handle_tf3 = iBands(_Symbol, Input_Timeframe_3, 20, 0, 2.0, PRICE_CLOSE);
      
      g_lib.SetIndicatorHandlesTF3(g_rsi_handle_tf3, g_rsi_fast_handle_tf3, 
                                    g_macd_handle_tf3, g_atr_handle_tf3, g_bb_handle_tf3);
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
