//+------------------------------------------------------------------+
//|                                    AnalyzeScalpingPatterns.mq5   |
//|                   Analyze Bollinger Band settings on real data   |
//+------------------------------------------------------------------+
#property copyright "Market Analysis Script"
#property version   "2.00"
#property script_show_inputs

//--- Input Parameters
input int      InpBarsToAnalyze = 5000;        // Bars to Analyze
input bool     InpLondonNYOnly = true;         // London-NY Session Only

//--- Analysis arrays
struct BBSettings
{
   int period;
   double deviation;
   string name;
   int total_signals;
   int winning_trades;
   int losing_trades;
   double win_rate;
   double avg_profit;
   double avg_loss;
   double profit_factor;
   double avg_rr_ratio;
};

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("========================================");
   Print("BOLLINGER BAND OPTIMIZATION");
   Print("Analyzing ", InpBarsToAnalyze, " bars on ", _Symbol);
   Print("========================================");
   Print("");
   
   //--- Get historical data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   int copied = CopyRates(_Symbol, PERIOD_M5, 0, InpBarsToAnalyze, rates);
   if(copied < InpBarsToAnalyze)
   {
      Print("Error: Could not copy enough data. Got ", copied, " bars");
      return;
   }
   
   Print("Successfully loaded ", copied, " M5 bars");
   Print("");
   
   //--- Test different BB configurations
   BBSettings settings[];
   int idx = 0;
   
   //--- Period variations with standard 2.0 deviation
   ArrayResize(settings, 30);
   settings[idx++] = TestBBConfiguration(rates, 10, 2.0);
   settings[idx++] = TestBBConfiguration(rates, 15, 2.0);
   settings[idx++] = TestBBConfiguration(rates, 20, 2.0);  // Standard
   settings[idx++] = TestBBConfiguration(rates, 25, 2.0);
   settings[idx++] = TestBBConfiguration(rates, 30, 2.0);
   
   //--- Deviation variations with standard 20 period
   settings[idx++] = TestBBConfiguration(rates, 20, 1.5);
   settings[idx++] = TestBBConfiguration(rates, 20, 2.5);
   settings[idx++] = TestBBConfiguration(rates, 20, 3.0);
   
   //--- Aggressive scalping settings (tighter bands)
   settings[idx++] = TestBBConfiguration(rates, 10, 1.5);
   settings[idx++] = TestBBConfiguration(rates, 12, 1.5);
   settings[idx++] = TestBBConfiguration(rates, 15, 1.5);
   settings[idx++] = TestBBConfiguration(rates, 15, 1.8);
   
   //--- Conservative settings (wider bands)
   settings[idx++] = TestBBConfiguration(rates, 25, 2.5);
   settings[idx++] = TestBBConfiguration(rates, 30, 2.5);
   settings[idx++] = TestBBConfiguration(rates, 20, 2.8);
   
   //--- Fast scalping settings
   settings[idx++] = TestBBConfiguration(rates, 8, 2.0);
   settings[idx++] = TestBBConfiguration(rates, 10, 1.8);
   settings[idx++] = TestBBConfiguration(rates, 12, 2.0);
   
   //--- Optimal combinations found in practice
   settings[idx++] = TestBBConfiguration(rates, 14, 2.0);
   settings[idx++] = TestBBConfiguration(rates, 16, 2.0);
   settings[idx++] = TestBBConfiguration(rates, 18, 2.0);
   settings[idx++] = TestBBConfiguration(rates, 18, 1.8);
   settings[idx++] = TestBBConfiguration(rates, 22, 2.0);
   
   //--- Mixed settings
   settings[idx++] = TestBBConfiguration(rates, 12, 1.8);
   settings[idx++] = TestBBConfiguration(rates, 14, 1.8);
   settings[idx++] = TestBBConfiguration(rates, 16, 1.8);
   settings[idx++] = TestBBConfiguration(rates, 25, 2.2);
   settings[idx++] = TestBBConfiguration(rates, 20, 2.2);
   settings[idx++] = TestBBConfiguration(rates, 15, 2.2);
   
   //--- Resize to actual count
   ArrayResize(settings, idx);
   
   //--- Sort by profit factor
   SortByProfitFactor(settings);
   
   //--- Display results
   Print("========================================");
   Print("TOP BOLLINGER BAND CONFIGURATIONS");
   Print("========================================");
   Print("");
   
   //--- Show top 10
   int displayCount = MathMin(10, ArraySize(settings));
   for(int i = 0; i < displayCount; i++)
   {
      if(settings[i].total_signals > 5) // Min signals filter
      {
         Print("--- #", (i+1), ": ", settings[i].name, " ---");
         Print("  Signals: ", settings[i].total_signals);
         Print("  Win Rate: ", DoubleToString(settings[i].win_rate, 2), "%");
         Print("  Avg Profit: ", DoubleToString(settings[i].avg_profit, 1), " pips");
         Print("  Avg Loss: ", DoubleToString(settings[i].avg_loss, 1), " pips");
         Print("  Avg R:R: ", DoubleToString(settings[i].avg_rr_ratio, 2));
         Print("  Profit Factor: ", DoubleToString(settings[i].profit_factor, 2));
         Print("");
      }
   }
   
   //--- Find best overall
   int bestIdx = 0;
   double bestScore = 0;
   for(int i = 0; i < ArraySize(settings); i++)
   {
      if(settings[i].total_signals > 10)
      {
         //--- Score = PF * WinRate * AvgRR (composite metric)
         double score = settings[i].profit_factor * settings[i].win_rate * settings[i].avg_rr_ratio;
         if(score > bestScore)
         {
            bestScore = score;
            bestIdx = i;
         }
      }
   }
   
   Print("========================================");
   Print("RECOMMENDED SETTINGS: ", settings[bestIdx].name);
   Print("Period: ", settings[bestIdx].period);
   Print("Deviation: ", DoubleToString(settings[bestIdx].deviation, 1));
   Print("Win Rate: ", DoubleToString(settings[bestIdx].win_rate, 2), "%");
   Print("Profit Factor: ", DoubleToString(settings[bestIdx].profit_factor, 2));
   Print("Avg R:R: ", DoubleToString(settings[bestIdx].avg_rr_ratio, 2));
   Print("========================================");
   
   //--- Show all results in table format
   Print("");
   Print("COMPLETE RESULTS TABLE:");
   Print("Period | Dev  | Signals | Win%  | AvgProfit | AvgLoss | R:R  | PF");
   Print("-------|------|---------|-------|-----------|---------|------|-----");
   for(int i = 0; i < ArraySize(settings); i++)
   {
      if(settings[i].total_signals > 0)
      {
         Print(StringFormat("%6d | %4.1f | %7d | %5.1f | %9.1f | %7.1f | %4.2f | %4.2f",
               settings[i].period,
               settings[i].deviation,
               settings[i].total_signals,
               settings[i].win_rate,
               settings[i].avg_profit,
               settings[i].avg_loss,
               settings[i].avg_rr_ratio,
               settings[i].profit_factor));
      }
   }
}

//+------------------------------------------------------------------+
//| Test BB Configuration                                            |
//+------------------------------------------------------------------+
BBSettings TestBBConfiguration(const MqlRates &rates[], int period, double deviation)
{
   BBSettings result;
   result.period = period;
   result.deviation = deviation;
   result.name = StringFormat("BB(%d, %.1f)", period, deviation);
   result.total_signals = 0;
   result.winning_trades = 0;
   result.losing_trades = 0;
   
   double total_profit = 0;
   double total_loss = 0;
   double total_rr = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   //--- Create BB and EMA50 for this test
   int handleBB = iBands(_Symbol, PERIOD_M5, period, 0, deviation, PRICE_CLOSE);
   int handleEMA50 = iMA(_Symbol, PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handleBB == INVALID_HANDLE || handleEMA50 == INVALID_HANDLE)
   {
      Print("Error creating handles for ", result.name);
      return result;
   }
   
   double bb_upper[], bb_middle[], bb_lower[], ema50[];
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_middle, true);
   ArraySetAsSeries(bb_lower, true);
   ArraySetAsSeries(ema50, true);
   
   int copied = ArraySize(rates);
   CopyBuffer(handleBB, 1, 0, copied, bb_upper);
   CopyBuffer(handleBB, 0, 0, copied, bb_middle);
   CopyBuffer(handleBB, 2, 0, copied, bb_lower);
   CopyBuffer(handleEMA50, 0, 0, copied, ema50);
   
   //--- Test strategy
   for(int i = 100; i < ArraySize(rates) - 50; i++)
   {
      if(InpLondonNYOnly && !IsLondonNYSession(rates[i].time))
         continue;
      
      //--- Bullish bounce (buy at lower band)
      bool touchedLower = rates[i].low <= bb_lower[i];
      bool closedAboveLower = rates[i].close > bb_lower[i];
      bool uptrend = rates[i].close > ema50[i];
      
      if(touchedLower && closedAboveLower && uptrend)
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = bb_lower[i] - 5 * 10 * point;
         double tp = bb_middle[i];
         
         double rr = MathAbs(tp - entry) / MathAbs(entry - sl);
         total_rr += rr;
         
         if(SimulateTrade(rates, i, true, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
      
      //--- Bearish bounce (sell at upper band)
      bool touchedUpper = rates[i].high >= bb_upper[i];
      bool closedBelowUpper = rates[i].close < bb_upper[i];
      bool downtrend = rates[i].close < ema50[i];
      
      if(touchedUpper && closedBelowUpper && downtrend)
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = bb_upper[i] + 5 * 10 * point;
         double tp = bb_middle[i];
         
         double rr = MathAbs(entry - tp) / MathAbs(sl - entry);
         total_rr += rr;
         
         if(SimulateTrade(rates, i, false, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
   }
   
   //--- Calculate metrics
   if(result.total_signals > 0)
   {
      result.win_rate = (double)result.winning_trades / result.total_signals * 100;
      result.avg_profit = result.winning_trades > 0 ? total_profit / result.winning_trades : 0;
      result.avg_loss = result.losing_trades > 0 ? total_loss / result.losing_trades : 0;
      result.profit_factor = total_loss > 0 ? total_profit / total_loss : 0;
      result.avg_rr_ratio = total_rr / result.total_signals;
   }
   
   //--- Cleanup
   IndicatorRelease(handleBB);
   IndicatorRelease(handleEMA50);
   
   return result;
}

//+------------------------------------------------------------------+
//| Simulate trade outcome                                           |
//+------------------------------------------------------------------+
bool SimulateTrade(const MqlRates &rates[], int entry_idx, bool is_buy, double entry, double sl, double tp, double &total_profit, double &total_loss)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   //--- Look forward up to 50 bars
   for(int i = entry_idx - 1; i >= MathMax(0, entry_idx - 50); i--)
   {
      if(is_buy)
      {
         if(rates[i].low <= sl)
         {
            total_loss += MathAbs(entry - sl) / point / 10;
            return false;
         }
         if(rates[i].high >= tp)
         {
            total_profit += MathAbs(tp - entry) / point / 10;
            return true;
         }
      }
      else
      {
         if(rates[i].high >= sl)
         {
            total_loss += MathAbs(sl - entry) / point / 10;
            return false;
         }
         if(rates[i].low <= tp)
         {
            total_profit += MathAbs(entry - tp) / point / 10;
            return true;
         }
      }
   }
   
   //--- Timeout - consider as loss
   total_loss += 5;
   return false;
}

//+------------------------------------------------------------------+
//| Check if London-NY session                                       |
//+------------------------------------------------------------------+
bool IsLondonNYSession(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   int hour = dt.hour;
   return (hour >= 12 && hour < 16); // 12:00-16:00 GMT
}

//+------------------------------------------------------------------+
//| Sort by profit factor                                            |
//+------------------------------------------------------------------+
void SortByProfitFactor(BBSettings &settings[])
{
   int size = ArraySize(settings);
   for(int i = 0; i < size - 1; i++)
   {
      for(int j = i + 1; j < size; j++)
      {
         if(settings[j].profit_factor > settings[i].profit_factor)
         {
            BBSettings temp = settings[i];
            settings[i] = settings[j];
            settings[j] = temp;
         }
      }
   }
}
//+------------------------------------------------------------------+
