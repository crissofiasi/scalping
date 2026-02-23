//+------------------------------------------------------------------+
//|                                              NNTrainer.mq5        |
//|                        Neural Network Trainer Script             |
//|                    Trains model to predict market moves          |
//+------------------------------------------------------------------+
#property copyright "Neural Network Trainer"
#property version   "1.00"
#property script_show_inputs

#include "../mql5/Include/NeuroNetworksBook/realization/neuronnet.mqh"
#include "NNPredictorLib.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "═══════════ Training Data Settings ═══════════"
input string             Input_Symbol = "";                            // Symbol (empty = current)
input ENUM_TIMEFRAMES    Input_Timeframe = PERIOD_M5;                  // Training Timeframe
input int                Input_Training_Bars = 5000;                   // Number of Bars for Training
input double             Input_Train_Test_Split = 0.80;                // Train/Test Split (0.80 = 80% train)
input datetime           Input_Start_Date = D'2024.01.01';             // Start Date for Data

input group "═══════════ Multi-Timeframe Analysis ═══════════"
input bool               Input_Use_Multi_Timeframe = false;            // Enable Multi-Timeframe Analysis
input ENUM_TIMEFRAMES    Input_Timeframe_2 = PERIOD_M15;               // Timeframe 2 (Higher TF)
input ENUM_TIMEFRAMES    Input_Timeframe_3 = PERIOD_M30;               // Timeframe 3 (Highest TF)

input group "═══════════ Labeling Settings ═══════════"
input double             Input_Target_Move_Pips = 10.0;                // Target Move in Pips (for labeling)
input int                Input_Lookforward_Bars = 20;                  // Lookforward Bars for Labeling
input double             Input_Min_Move_Ratio = 0.7;                   // Min Move Ratio (0.7 = 70% of target)

input group "═══════════ Network Architecture ═══════════"
input int                Input_Hidden_Layer1 = 50;                     // Hidden Layer 1 Neurons
input int                Input_Hidden_Layer2 = 30;                     // Hidden Layer 2 Neurons
input int                Input_Hidden_Layer3 = 15;                     // Hidden Layer 3 (0=disabled)

input group "═══════════ Training Parameters ═══════════"
input int                Input_Epochs = 800;                           // Training Epochs
input double             Input_Learning_Rate = 0.001;                  // Learning Rate
input int                Input_Batch_Size = 32;                        // Batch Size
input double             Input_Validation_Split = 0.15;                // Validation Split
input bool               Input_Use_OpenCL = false;                     // Use OpenCL Acceleration

input group "═══════════ Feature Settings ═══════════"
input int                Input_RSI_Period = 14;                        // RSI Period
input int                Input_RSI_Fast_Period = 5;                    // RSI Fast Period
input int                Input_MACD_Fast = 12;                         // MACD Fast
input int                Input_MACD_Slow = 26;                         // MACD Slow
input int                Input_MACD_Signal = 9;                        // MACD Signal
input int                Input_ATR_Period = 14;                        // ATR Period
input int                Input_BB_Period = 20;                         // BB Period
input double             Input_BB_Deviation = 2.0;                     // BB Deviation
input int                Input_Lookback_Bars = 15;                     // Lookback Bars for Patterns

input group "═══════════ Output Settings ═══════════"
input string             Input_Model_File = "NNPredictor_Model.nnw";  // Output Model File
input bool               Input_Save_Training_Log = true;               // Save Training Log

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CNeuronNet          *m_network = NULL;
CNNPredictorLib     *m_predictor = NULL;

int                  m_rsi_handle = INVALID_HANDLE;
int                  m_rsi_fast_handle = INVALID_HANDLE;
int                  m_macd_handle = INVALID_HANDLE;
int                  m_atr_handle = INVALID_HANDLE;
int                  m_bb_handle = INVALID_HANDLE;

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

struct TrainingData
{
   double features[];
   double label;
};

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("═══════════════════════════════════════════════════");
   Print("       Neural Network Trainer Starting...          ");
   Print("═══════════════════════════════════════════════════");
   
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   //--- Initialize indicators
   Print("Initializing indicators...");
   m_rsi_handle = iRSI(symbol, Input_Timeframe, Input_RSI_Period, PRICE_CLOSE);
   m_rsi_fast_handle = iRSI(symbol, Input_Timeframe, Input_RSI_Fast_Period, PRICE_CLOSE);
   m_macd_handle = iMACD(symbol, Input_Timeframe, Input_MACD_Fast, Input_MACD_Slow, Input_MACD_Signal, PRICE_CLOSE);
   m_atr_handle = iATR(symbol, Input_Timeframe, Input_ATR_Period);
   m_bb_handle = iBands(symbol, Input_Timeframe, Input_BB_Period, 0, Input_BB_Deviation, PRICE_CLOSE);
   
   if(m_rsi_handle == INVALID_HANDLE || m_rsi_fast_handle == INVALID_HANDLE ||
      m_macd_handle == INVALID_HANDLE || m_atr_handle == INVALID_HANDLE ||
      m_bb_handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicators");
      return;
   }
   
   //--- Initialize multi-timeframe indicators if enabled
   if(Input_Use_Multi_Timeframe)
   {
      Print("Initializing multi-timeframe indicators...");
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
      
      if(m_rsi_handle_tf2 == INVALID_HANDLE || m_rsi_handle_tf3 == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create multi-timeframe indicators");
         return;
      }
      
      Print("Multi-timeframe enabled: TF1=", EnumToString(Input_Timeframe),
            " TF2=", EnumToString(Input_Timeframe_2), " TF3=", EnumToString(Input_Timeframe_3));
   }
   
   //--- Initialize predictor
   m_predictor = new CNNPredictorLib();
   m_predictor.SetSymbol(symbol);
   m_predictor.SetTimeframe(Input_Timeframe);
   m_predictor.SetIndicatorHandles(m_rsi_handle, m_rsi_fast_handle, m_macd_handle, m_atr_handle, m_bb_handle);
   
   //--- Set multi-timeframe if enabled
   if(Input_Use_Multi_Timeframe)
   {
      m_predictor.EnableMultiTimeframe(true, Input_Timeframe_2, Input_Timeframe_3);
      m_predictor.SetIndicatorHandlesTF2(m_rsi_handle_tf2, m_rsi_fast_handle_tf2, m_macd_handle_tf2, m_atr_handle_tf2, m_bb_handle_tf2);
      m_predictor.SetIndicatorHandlesTF3(m_rsi_handle_tf3, m_rsi_fast_handle_tf3, m_macd_handle_tf3, m_atr_handle_tf3, m_bb_handle_tf3);
   }
   
   //--- Step 1: Collect and label training data
   Print("Step 1: Collecting and labeling training data...");
   TrainingData training_data[];
   
   if(!CollectTrainingData(training_data))
   {
      Print("ERROR: Failed to collect training data");
      Cleanup();
      return;
   }
   
   Print("Collected ", ArraySize(training_data), " training samples");
   
   if(ArraySize(training_data) > 0)
   {
      int num_features = ArraySize(training_data[0].features);
      Print("Features per sample: ", num_features);
      
      if(Input_Use_Multi_Timeframe)
      {
         Print("Multi-timeframe mode active - Features breakdown:");
         Print("  TF1 (", EnumToString(Input_Timeframe), "): ~25 features");
         Print("  TF2 (", EnumToString(Input_Timeframe_2), "): ~25 features");  
         Print("  TF3 (", EnumToString(Input_Timeframe_3), "): ~25 features");
         Print("  Total: ", num_features, " features");
      }
   }
   
   //--- Step 2: Split data into train/test sets
   Print("Step 2: Splitting data into train/test sets...");
   TrainingData train_set[], test_set[];
   SplitTrainTest(training_data, train_set, test_set);
   
   Print("Train set: ", ArraySize(train_set), " samples");
   Print("Test set: ", ArraySize(test_set), " samples");
   
   //--- Create neural network
   Print("Step 3: Creating neural network...");
   
   //--- Adjust network size if multi-timeframe is enabled
   int layer1_size = Input_Hidden_Layer1;
   int layer2_size = Input_Hidden_Layer2;
   int layer3_size = Input_Hidden_Layer3;
   
   if(Input_Use_Multi_Timeframe)
   {
      //--- Recommend larger network for multi-timeframe
      if(layer1_size < 70)
      {
         Print("INFO: Multi-timeframe enabled with small network. Consider increasing Hidden_Layer1 to 70-80 neurons.");
      }
   }
   
   if(!CreateNeuralNetwork(ArraySize(training_data[0].features)))
   {
      Print("ERROR: Failed to create neural network");
      Cleanup();
      return;
   }
   
   //--- Step 4: Train the network
   Print("Step 4: Training neural network...");
   Print("This may take several minutes...");
   
   if(!TrainNetwork(train_set, test_set))
   {
      Print("ERROR: Training failed");
      Cleanup();
      return;
   }
   
   //--- Step 5: Evaluate on test set
   Print("Step 5: Evaluating model on test set...");
   EvaluateModel(test_set);
   
   //--- Step 6: Save model
   Print("Step 6: Saving model...");
   if(!SaveModel())
   {
      Print("ERROR: Failed to save model");
      Cleanup();
      return;
   }
   
   Print("═══════════════════════════════════════════════════");
   Print("       Training Completed Successfully!            ");
   Print("       Model saved to: ", Input_Model_File);
   Print("═══════════════════════════════════════════════════");
   
   Cleanup();
}

//+------------------------------------------------------------------+
//| Collect and label training data                                  |
//+------------------------------------------------------------------+
bool CollectTrainingData(TrainingData &data[])
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   //--- Get available bars
   int available_bars = Bars(symbol, Input_Timeframe);
   int bars_to_process = MathMin(Input_Training_Bars, available_bars - Input_Lookforward_Bars - 100);
   
   if(bars_to_process < 100)
   {
      Print("ERROR: Not enough historical data");
      return false;
   }
   
   Print("Processing ", bars_to_process, " bars...");
   
   ArrayResize(data, 0);
   
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double target_move_price = Input_Target_Move_Pips * 10 * point;
   
   int labeled_count = 0;
   int buy_signals = 0;
   int sell_signals = 0;
   
   //--- Process each bar
   for(int i = Input_Lookforward_Bars + 50; i < bars_to_process; i++)
   {
      //--- Show progress every 500 bars
      if(i % 500 == 0)
         Print("Processing bar ", i, " of ", bars_to_process);
      
      //--- Prepare features
      double features[];
      if(!m_predictor.PrepareFeatures(features, i, Input_Lookback_Bars))
         continue;
      
      //--- Label data: Look forward to see if price moves up or down
      double label = LabelBar(i, target_move_price);
      
      if(label < 0) // No clear move
         continue;
      
      //--- Add to training data
      int idx = ArraySize(data);
      ArrayResize(data, idx + 1);
      ArrayCopy(data[idx].features, features);
      data[idx].label = label;
      
      labeled_count++;
      if(label > 0.5) buy_signals++;
      else sell_signals++;
   }
   
   Print("Successfully labeled ", labeled_count, " samples");
   Print("BUY signals: ", buy_signals, " (", DoubleToString(buy_signals * 100.0 / labeled_count, 1), "%)");
   Print("SELL signals: ", sell_signals, " (", DoubleToString(sell_signals * 100.0 / labeled_count, 1), "%)");
   
   return (labeled_count > 100);
}

//+------------------------------------------------------------------+
//| Label a bar based on future price movement                       |
//+------------------------------------------------------------------+
double LabelBar(int bar_index, double target_move)
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   double current_price = iClose(symbol, Input_Timeframe, bar_index);
   
   double max_price = current_price;
   double min_price = current_price;
   
   //--- Look forward
   for(int i = 1; i <= Input_Lookforward_Bars; i++)
   {
      double high = iHigh(symbol, Input_Timeframe, bar_index - i);
      double low = iLow(symbol, Input_Timeframe, bar_index - i);
      
      if(high > max_price) max_price = high;
      if(low < min_price) min_price = low;
   }
   
   double upward_move = max_price - current_price;
   double downward_move = current_price - min_price;
   
   //--- Determine if there was a clear directional move
   double min_move = target_move * Input_Min_Move_Ratio;
   
   if(upward_move >= min_move && upward_move > downward_move * 1.5)
   {
      return 1.0; // Clear upward move (BUY label)
   }
   else if(downward_move >= min_move && downward_move > upward_move * 1.5)
   {
      return 0.0; // Clear downward move (SELL label)
   }
   
   return -1.0; // No clear move (exclude from training)
}

//+------------------------------------------------------------------+
//| Split data into training and test sets                           |
//+------------------------------------------------------------------+
void SplitTrainTest(TrainingData &all_data[], TrainingData &train[], TrainingData &test[])
{
   int total_samples = ArraySize(all_data);
   int train_size = (int)(total_samples * Input_Train_Test_Split);
   
   ArrayResize(train, train_size);
   ArrayResize(test, total_samples - train_size);
   
   //--- Copy to train set
   for(int i = 0; i < train_size; i++)
   {
      ArrayCopy(train[i].features, all_data[i].features);
      train[i].label = all_data[i].label;
   }
   
   //--- Copy to test set
   for(int i = train_size; i < total_samples; i++)
   {
      ArrayCopy(test[i - train_size].features, all_data[i].features);
      test[i - train_size].label = all_data[i].label;
   }
}

//+------------------------------------------------------------------+
//| Create neural network                                             |
//+------------------------------------------------------------------+
bool CreateNeuralNetwork(int input_size)
{
   m_network = new CNeuronNet();
   
   if(m_network == NULL)
      return false;
   
   //--- Create layer structure
   CArrayObj *layers = new CArrayObj();
   
   //--- Input layer
   CLayerDescription *input_layer = new CLayerDescription();
   input_layer.type = defNeuronBase;
   input_layer.count = input_size;
   input_layer.optimization = ADAM;
   input_layer.activation = AF_SWISH;
   layers.Add(input_layer);
   
   //--- Hidden layer 1
   if(Input_Hidden_Layer1 > 0)
   {
      CLayerDescription *hidden1 = new CLayerDescription();
      hidden1.type = defNeuronBase;
      hidden1.count = Input_Hidden_Layer1;
      hidden1.optimization = ADAM;
      hidden1.activation = AF_SWISH;
      layers.Add(hidden1);
   }
   
   //--- Hidden layer 2
   if(Input_Hidden_Layer2 > 0)
   {
      CLayerDescription *hidden2 = new CLayerDescription();
      hidden2.type = defNeuronBase;
      hidden2.count = Input_Hidden_Layer2;
      hidden2.optimization = ADAM;
      hidden2.activation = AF_SWISH;
      layers.Add(hidden2);
   }
   
   //--- Hidden layer 3 (optional)
   if(Input_Hidden_Layer3 > 0)
   {
      CLayerDescription *hidden3 = new CLayerDescription();
      hidden3.type = defNeuronBase;
      hidden3.count = Input_Hidden_Layer3;
      hidden3.optimization = ADAM;
      hidden3.activation = AF_SWISH;
      layers.Add(hidden3);
   }
   
   //--- Output layer (sigmoid for binary classification)
   CLayerDescription *output_layer = new CLayerDescription();
   output_layer.type = defNeuronBase;
   output_layer.count = 1;
   output_layer.optimization = ADAM;
   output_layer.activation = AF_SIGMOID;
   layers.Add(output_layer);
   
   //--- Initialize network
   if(!m_network.Create(layers))
   {
      Print("ERROR: Failed to create network layers");
      delete layers;
      return false;
   }
   
   //--- Set learning rate
   m_network.SetLearningRates(Input_Learning_Rate);
   
   //--- Enable OpenCL if requested
   if(Input_Use_OpenCL)
   {
      m_network.OpenCL_Enable(true);
      Print("OpenCL acceleration enabled");
   }
   
   Print("Network created: ", input_size, " inputs, ", 
         Input_Hidden_Layer1, "/", Input_Hidden_Layer2, 
         (Input_Hidden_Layer3 > 0 ? "/" + IntegerToString(Input_Hidden_Layer3) : ""),
         " hidden, 1 output");
   
   delete layers;
   return true;
}

//+------------------------------------------------------------------+
//| Train the neural network                                          |
//+------------------------------------------------------------------+
bool TrainNetwork(TrainingData &train_data[], TrainingData &validation_data[])
{
   int train_size = ArraySize(train_data);
   if(train_size == 0)
      return false;
   
   Print("Starting training with ", Input_Epochs, " epochs...");
   
   int log_handle = -1;
   if(Input_Save_Training_Log)
   {
      string log_file = "NNTrainer_Log_" + TimeToString(TimeCurrent(), TIME_DATE) + ".txt";
      log_handle = FileOpen(log_file, FILE_WRITE|FILE_TXT|FILE_COMMON);
      if(log_handle != INVALID_HANDLE)
      {
         FileWriteString(log_handle, "Neural Network Training Log\n");
         FileWriteString(log_handle, "============================\n");
         FileWriteString(log_handle, "Date: " + TimeToString(TimeCurrent()) + "\n");
         FileWriteString(log_handle, "Training samples: " + IntegerToString(train_size) + "\n");
         FileWriteString(log_handle, "Validation samples: " + IntegerToString(ArraySize(validation_data)) + "\n\n");
      }
   }
   
   double best_val_accuracy = 0.0;
   
   for(int epoch = 0; epoch < Input_Epochs; epoch++)
   {
      double epoch_loss = 0.0;
      int correct = 0;
      
      //--- Training loop (mini-batches)
      for(int i = 0; i < train_size; i++)
      {
         //--- Feed forward
         if(!m_network.FeedForward(train_data[i].features))
            continue;
         
         //--- Get prediction
         double outputs[];
         m_network.GetOutputs(outputs);
         double prediction = outputs[0];
         
         //--- Calculate loss (Binary Cross-Entropy)
         double target = train_data[i].label;
         double loss = -target * MathLog(prediction + 1e-7) - (1 - target) * MathLog(1 - prediction + 1e-7);
         epoch_loss += loss;
         
         //--- Check accuracy
         if((prediction > 0.5 && target > 0.5) || (prediction <= 0.5 && target <= 0.5))
            correct++;
         
         //--- Backpropagation
         double target_array[1];
         target_array[0] = target;
         m_network.Backpropagation(target_array);
         
         //--- Update weights every batch
         if((i + 1) % Input_Batch_Size == 0 || i == train_size - 1)
         {
            m_network.UpdateWeights();
         }
      }
      
      double train_accuracy = (double)correct / train_size * 100.0;
      double avg_loss = epoch_loss / train_size;
      
      //--- Validation every 10 epochs
      if(epoch % 10 == 0 || epoch == Input_Epochs - 1)
      {
         double val_accuracy = ValidateNetwork(validation_data);
         
         Print("Epoch ", epoch + 1, "/", Input_Epochs, 
               " - Loss: ", DoubleToString(avg_loss, 4),
               " - Train Acc: ", DoubleToString(train_accuracy, 2), "%",
               " - Val Acc: ", DoubleToString(val_accuracy, 2), "%");
         
         if(log_handle != INVALID_HANDLE)
         {
            FileWriteString(log_handle, "Epoch " + IntegerToString(epoch + 1) + 
                          " - Loss: " + DoubleToString(avg_loss, 4) +
                          " - Train: " + DoubleToString(train_accuracy, 2) + "%" +
                          " - Val: " + DoubleToString(val_accuracy, 2) + "%\n");
         }
         
         if(val_accuracy > best_val_accuracy)
            best_val_accuracy = val_accuracy;
      }
   }
   
   if(log_handle != INVALID_HANDLE)
   {
      FileWriteString(log_handle, "\nBest Validation Accuracy: " + DoubleToString(best_val_accuracy, 2) + "%\n");
      FileClose(log_handle);
   }
   
   Print("Training completed. Best validation accuracy: ", DoubleToString(best_val_accuracy, 2), "%");
   
   return true;
}

//+------------------------------------------------------------------+
//| Validate network                                                  |
//+------------------------------------------------------------------+
double ValidateNetwork(TrainingData &data[])
{
   int total = ArraySize(data);
   if(total == 0) return 0.0;
   
   int correct = 0;
   
   for(int i = 0; i < total; i++)
   {
      if(!m_network.FeedForward(data[i].features))
         continue;
      
      double outputs[];
      m_network.GetOutputs(outputs);
      double prediction = outputs[0];
      double target = data[i].label;
      
      if((prediction > 0.5 && target > 0.5) || (prediction <= 0.5 && target <= 0.5))
         correct++;
   }
   
   return (double)correct / total * 100.0;
}

//+------------------------------------------------------------------+
//| Evaluate model on test set                                        |
//+------------------------------------------------------------------+
void EvaluateModel(TrainingData &test_data[])
{
   int total = ArraySize(test_data);
   int correct = 0;
   int true_positives = 0;
   int false_positives = 0;
   int true_negatives = 0;
   int false_negatives = 0;
   
   for(int i = 0; i < total; i++)
   {
      if(!m_network.FeedForward(test_data[i].features))
         continue;
      
      double outputs[];
      m_network.GetOutputs(outputs);
      double prediction = outputs[0];
      double target = test_data[i].label;
      
      bool predicted_buy = (prediction > 0.5);
      bool actual_buy = (target > 0.5);
      
      if(predicted_buy && actual_buy) true_positives++;
      else if(predicted_buy && !actual_buy) false_positives++;
      else if(!predicted_buy && !actual_buy) true_negatives++;
      else if(!predicted_buy && actual_buy) false_negatives++;
      
      if((predicted_buy && actual_buy) || (!predicted_buy && !actual_buy))
         correct++;
   }
   
   double accuracy = (double)correct / total * 100.0;
   double precision = (true_positives + false_positives > 0) ? 
                      (double)true_positives / (true_positives + false_positives) * 100.0 : 0.0;
   double recall = (true_positives + false_negatives > 0) ? 
                   (double)true_positives / (true_positives + false_negatives) * 100.0 : 0.0;
   
   Print("═══════════════════════════════════════════════════");
   Print("Test Set Evaluation:");
   Print("  Accuracy:  ", DoubleToString(accuracy, 2), "%");
   Print("  Precision: ", DoubleToString(precision, 2), "%");
   Print("  Recall:    ", DoubleToString(recall, 2), "%");
   Print("  True Positives:  ", true_positives);
   Print("  False Positives: ", false_positives);
   Print("  True Negatives:  ", true_negatives);
   Print("  False Negatives: ", false_negatives);
   Print("═══════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Save model to file                                                |
//+------------------------------------------------------------------+
bool SaveModel()
{
   if(!m_network.Save(Input_Model_File, FILE_COMMON, false, 0.0, 0.0, 0.0))
   {
      Print("ERROR: Failed to save model");
      return false;
   }
   
   Print("Model saved successfully to: ", Input_Model_File);
   return true;
}

//+------------------------------------------------------------------+
//| Cleanup                                                           |
//+------------------------------------------------------------------+
void Cleanup()
{
   if(m_rsi_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_handle);
   if(m_rsi_fast_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_fast_handle);
   if(m_macd_handle != INVALID_HANDLE) IndicatorRelease(m_macd_handle);
   if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
   if(m_bb_handle != INVALID_HANDLE) IndicatorRelease(m_bb_handle);
   
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
   
   if(m_network != NULL) delete m_network;
   if(m_predictor != NULL) delete m_predictor;
}
//+------------------------------------------------------------------+
