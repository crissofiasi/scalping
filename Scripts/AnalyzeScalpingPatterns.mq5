//+------------------------------------------------------------------+
//|                                    AnalyzeScalpingPatterns.mq5   |
//|                              Analyze real data for best strategy |
//+------------------------------------------------------------------+
#property copyright "Market Analysis Script"
#property version   "1.00"
#property script_show_inputs

//--- Input Parameters
input int      InpBarsToAnalyze = 5000;        // Bars to Analyze
input int      InpMinProfitPips = 5;           // Min Profit Target (pips)
input int      InpMaxStopPips = 7;             // Max Stop Loss (pips)
input bool     InpLondonNYOnly = true;         // London-NY Session Only

//--- Analysis arrays
struct TradePattern
{
   string pattern_name;
   int total_signals;
   int winning_trades;
   int losing_trades;
   double win_rate;
   double avg_profit;
   double avg_loss;
   double profit_factor;
};

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("========================================");
   Print("SCALPING PATTERN ANALYSIS");
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
   
   //--- Calculate indicators for analysis
   int handleEMA9 = iMA(_Symbol, PERIOD_M5, 9, 0, MODE_EMA, PRICE_CLOSE);
   int handleEMA21 = iMA(_Symbol, PERIOD_M5, 21, 0, MODE_EMA, PRICE_CLOSE);
   int handleEMA50 = iMA(_Symbol, PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE);
   int handleRSI = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
   int handleATR = iATR(_Symbol, PERIOD_M5, 14);
   int handleBB = iBands(_Symbol, PERIOD_M5, 20, 0, 2, PRICE_CLOSE);
   
   double ema9[], ema21[], ema50[], rsi[], atr[], bb_upper[], bb_lower[], bb_middle[];
   ArraySetAsSeries(ema9, true);
   ArraySetAsSeries(ema21, true);
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_lower, true);
   ArraySetAsSeries(bb_middle, true);
   
   CopyBuffer(handleEMA9, 0, 0, copied, ema9);
   CopyBuffer(handleEMA21, 0, 0, copied, ema21);
   CopyBuffer(handleEMA50, 0, 0, copied, ema50);
   CopyBuffer(handleRSI, 0, 0, copied, rsi);
   CopyBuffer(handleATR, 0, 0, copied, atr);
   CopyBuffer(handleBB, 1, 0, copied, bb_upper);
   CopyBuffer(handleBB, 2, 0, copied, bb_lower);
   CopyBuffer(handleBB, 0, 0, copied, bb_middle);
   
   Print("Indicators loaded successfully");
   Print("");
   
   //--- Test different strategies
   TradePattern patterns[];
   ArrayResize(patterns, 8);
   
   //--- Strategy 1: EMA 9/21 Crossover + EMA 50 Filter
   patterns[0] = TestEMACrossover(rates, ema9, ema21, ema50);
   
   //--- Strategy 2: Bollinger Band Bounce
   patterns[1] = TestBollingerBounce(rates, bb_upper, bb_lower, bb_middle, ema50);
   
   //--- Strategy 3: RSI Oversold/Overbought
   patterns[2] = TestRSIReversal(rates, rsi, ema50);
   
   //--- Strategy 4: Price Action - Engulfing Candles
   patterns[3] = TestEngulfingCandles(rates, ema50);
   
   //--- Strategy 5: Breakout from consolidation
   patterns[4] = TestBreakoutStrategy(rates, atr, ema50);
   
   //--- Strategy 6: EMA Bounce (Price touches EMA and bounces)
   patterns[5] = TestEMABounce(rates, ema21, ema50);
   
   //--- Strategy 7: Triple EMA alignment
   patterns[6] = TestTripleEMAAlignment(rates, ema9, ema21, ema50);
   
   //--- Strategy 8: Momentum + Trend
   patterns[7] = TestMomentumTrend(rates, ema9, ema21, ema50, rsi);
   
   //--- Display results
   Print("========================================");
   Print("STRATEGY COMPARISON");
   Print("========================================");
   Print("");
   
   //--- Sort by profit factor
   SortPatternsByProfitFactor(patterns);
   
   //--- Display sorted results
   for(int i = 0; i < ArraySize(patterns); i++)
   {
      if(patterns[i].total_signals > 10) // Only show strategies with enough signals
      {
         Print("--- ", patterns[i].pattern_name, " ---");
         Print("  Signals: ", patterns[i].total_signals);
         Print("  Win Rate: ", DoubleToString(patterns[i].win_rate, 2), "%");
         Print("  Avg Profit: ", DoubleToString(patterns[i].avg_profit, 1), " pips");
         Print("  Avg Loss: ", DoubleToString(patterns[i].avg_loss, 1), " pips");
         Print("  Profit Factor: ", DoubleToString(patterns[i].profit_factor, 2));
         Print("");
      }
   }
   
   //--- Find best strategy
   int bestIdx = 0;
   double bestPF = 0;
   for(int i = 0; i < ArraySize(patterns); i++)
   {
      if(patterns[i].total_signals > 10 && patterns[i].profit_factor > bestPF)
      {
         bestPF = patterns[i].profit_factor;
         bestIdx = i;
      }
   }
   
   Print("========================================");
   Print("RECOMMENDED STRATEGY: ", patterns[bestIdx].pattern_name);
   Print("Win Rate: ", DoubleToString(patterns[bestIdx].win_rate, 2), "%");
   Print("Profit Factor: ", DoubleToString(patterns[bestIdx].profit_factor, 2));
   Print("========================================");
   
   //--- Cleanup
   IndicatorRelease(handleEMA9);
   IndicatorRelease(handleEMA21);
   IndicatorRelease(handleEMA50);
   IndicatorRelease(handleRSI);
   IndicatorRelease(handleATR);
   IndicatorRelease(handleBB);
}

//+------------------------------------------------------------------+
//| Test EMA Crossover Strategy                                      |
//+------------------------------------------------------------------+
TradePattern TestEMACrossover(const MqlRates &rates[], const double &ema9[], const double &ema21[], const double &ema50[])
{
   TradePattern result;
   result.pattern_name = "EMA 9/21 Crossover + EMA50 Filter";
   result.total_signals = 0;
   result.winning_trades = 0;
   result.losing_trades = 0;
   
   double total_profit = 0;
   double total_loss = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   for(int i = 100; i < ArraySize(rates) - 50; i++)
   {
      if(InpLondonNYOnly && !IsLondonNYSession(rates[i].time))
         continue;
      
      //--- Bullish crossover
      if(ema9[i+1] <= ema21[i+1] && ema9[i] > ema21[i] && rates[i].close > ema50[i])
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = entry - InpMaxStopPips * 10 * point;
         double tp = entry + InpMinProfitPips * 10 * point;
         
         if(SimulateTrade(rates, i, true, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
      
      //--- Bearish crossover
      if(ema9[i+1] >= ema21[i+1] && ema9[i] < ema21[i] && rates[i].close < ema50[i])
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = entry + InpMaxStopPips * 10 * point;
         double tp = entry - InpMinProfitPips * 10 * point;
         
         if(SimulateTrade(rates, i, false, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
   }
   
   CalculateMetrics(result, total_profit, total_loss);
   return result;
}

//+------------------------------------------------------------------+
//| Test Bollinger Band Bounce Strategy                             |
//+------------------------------------------------------------------+
TradePattern TestBollingerBounce(const MqlRates &rates[], const double &bb_upper[], const double &bb_lower[], const double &bb_middle[], const double &ema50[])
{
   TradePattern result;
   result.pattern_name = "Bollinger Band Bounce";
   result.total_signals = 0;
   result.winning_trades = 0;
   result.losing_trades = 0;
   
   double total_profit = 0;
   double total_loss = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   for(int i = 100; i < ArraySize(rates) - 50; i++)
   {
      if(InpLondonNYOnly && !IsLondonNYSession(rates[i].time))
         continue;
      
      //--- Buy at lower band (oversold bounce)
      if(rates[i].low <= bb_lower[i] && rates[i].close > bb_lower[i] && rates[i].close > ema50[i])
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = bb_lower[i] - 5 * 10 * point;
         double tp = bb_middle[i];
         
         if(SimulateTrade(rates, i, true, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
      
      //--- Sell at upper band (overbought bounce)
      if(rates[i].high >= bb_upper[i] && rates[i].close < bb_upper[i] && rates[i].close < ema50[i])
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = bb_upper[i] + 5 * 10 * point;
         double tp = bb_middle[i];
         
         if(SimulateTrade(rates, i, false, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
   }
   
   CalculateMetrics(result, total_profit, total_loss);
   return result;
}

//+------------------------------------------------------------------+
//| Test RSI Reversal Strategy                                       |
//+------------------------------------------------------------------+
TradePattern TestRSIReversal(const MqlRates &rates[], const double &rsi[], const double &ema50[])
{
   TradePattern result;
   result.pattern_name = "RSI Oversold/Overbought Reversal";
   result.total_signals = 0;
   result.winning_trades = 0;
   result.losing_trades = 0;
   
   double total_profit = 0;
   double total_loss = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   for(int i = 100; i < ArraySize(rates) - 50; i++)
   {
      if(InpLondonNYOnly && !IsLondonNYSession(rates[i].time))
         continue;
      
      //--- Buy when RSI oversold and turning up
      if(rsi[i+1] < 30 && rsi[i] > 30 && rates[i].close > ema50[i])
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = entry - InpMaxStopPips * 10 * point;
         double tp = entry + InpMinProfitPips * 10 * point;
         
         if(SimulateTrade(rates, i, true, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
      
      //--- Sell when RSI overbought and turning down
      if(rsi[i+1] > 70 && rsi[i] < 70 && rates[i].close < ema50[i])
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = entry + InpMaxStopPips * 10 * point;
         double tp = entry - InpMinProfitPips * 10 * point;
         
         if(SimulateTrade(rates, i, false, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
   }
   
   CalculateMetrics(result, total_profit, total_loss);
   return result;
}

//+------------------------------------------------------------------+
//| Test Engulfing Candle Pattern                                    |
//+------------------------------------------------------------------+
TradePattern TestEngulfingCandles(const MqlRates &rates[], const double &ema50[])
{
   TradePattern result;
   result.pattern_name = "Bullish/Bearish Engulfing Pattern";
   result.total_signals = 0;
   result.winning_trades = 0;
   result.losing_trades = 0;
   
   double total_profit = 0;
   double total_loss = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   for(int i = 100; i < ArraySize(rates) - 50; i++)
   {
      if(InpLondonNYOnly && !IsLondonNYSession(rates[i].time))
         continue;
      
      //--- Bullish engulfing
      bool bullishEngulfing = rates[i+1].close < rates[i+1].open && // Previous bearish
                              rates[i].close > rates[i].open &&     // Current bullish
                              rates[i].open <= rates[i+1].close &&  // Opens at/below prev close
                              rates[i].close > rates[i+1].open;     // Closes above prev open
      
      if(bullishEngulfing && rates[i].close > ema50[i])
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = rates[i].low - 3 * 10 * point;
         double tp = entry + (entry - sl) * 1.5;
         
         if(SimulateTrade(rates, i, true, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
      
      //--- Bearish engulfing
      bool bearishEngulfing = rates[i+1].close > rates[i+1].open && // Previous bullish
                              rates[i].close < rates[i].open &&     // Current bearish
                              rates[i].open >= rates[i+1].close &&  // Opens at/above prev close
                              rates[i].close < rates[i+1].open;     // Closes below prev open
      
      if(bearishEngulfing && rates[i].close < ema50[i])
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = rates[i].high + 3 * 10 * point;
         double tp = entry - (sl - entry) * 1.5;
         
         if(SimulateTrade(rates, i, false, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
   }
   
   CalculateMetrics(result, total_profit, total_loss);
   return result;
}

//+------------------------------------------------------------------+
//| Test Breakout Strategy                                           |
//+------------------------------------------------------------------+
TradePattern TestBreakoutStrategy(const MqlRates &rates[], const double &atr[], const double &ema50[])
{
   TradePattern result;
   result.pattern_name = "Consolidation Breakout";
   result.total_signals = 0;
   result.winning_trades = 0;
   result.losing_trades = 0;
   
   double total_profit = 0;
   double total_loss = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   for(int i = 100; i < ArraySize(rates) - 50; i++)
   {
      if(InpLondonNYOnly && !IsLondonNYSession(rates[i].time))
         continue;
      
      //--- Find consolidation (low ATR for 5+ bars)
      bool consolidating = true;
      double avgATR = 0;
      for(int j = i; j < i + 5; j++)
      {
         avgATR += atr[j];
      }
      avgATR /= 5;
      
      //--- Bullish breakout
      if(rates[i].close > rates[i].open && 
         rates[i].close > MathMax(MathMax(rates[i+1].high, rates[i+2].high), rates[i+3].high) &&
         rates[i].close > ema50[i])
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = rates[i].low;
         double tp = entry + (entry - sl) * 2;
         
         if(SimulateTrade(rates, i, true, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
      
      //--- Bearish breakout
      if(rates[i].close < rates[i].open && 
         rates[i].close < MathMin(MathMin(rates[i+1].low, rates[i+2].low), rates[i+3].low) &&
         rates[i].close < ema50[i])
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = rates[i].high;
         double tp = entry - (sl - entry) * 2;
         
         if(SimulateTrade(rates, i, false, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
   }
   
   CalculateMetrics(result, total_profit, total_loss);
   return result;
}

//+------------------------------------------------------------------+
//| Test EMA Bounce Strategy                                         |
//+------------------------------------------------------------------+
TradePattern TestEMABounce(const MqlRates &rates[], const double &ema21[], const double &ema50[])
{
   TradePattern result;
   result.pattern_name = "EMA21 Bounce in Trend";
   result.total_signals = 0;
   result.winning_trades = 0;
   result.losing_trades = 0;
   
   double total_profit = 0;
   double total_loss = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   for(int i = 100; i < ArraySize(rates) - 50; i++)
   {
      if(InpLondonNYOnly && !IsLondonNYSession(rates[i].time))
         continue;
      
      //--- Bullish bounce (price touches EMA21 from above in uptrend)
      if(rates[i].low <= ema21[i] && rates[i].close > ema21[i] && 
         ema21[i] > ema50[i] && rates[i].close > rates[i].open)
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = ema21[i] - 5 * 10 * point;
         double tp = entry + InpMinProfitPips * 10 * point;
         
         if(SimulateTrade(rates, i, true, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
      
      //--- Bearish bounce (price touches EMA21 from below in downtrend)
      if(rates[i].high >= ema21[i] && rates[i].close < ema21[i] && 
         ema21[i] < ema50[i] && rates[i].close < rates[i].open)
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = ema21[i] + 5 * 10 * point;
         double tp = entry - InpMinProfitPips * 10 * point;
         
         if(SimulateTrade(rates, i, false, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
   }
   
   CalculateMetrics(result, total_profit, total_loss);
   return result;
}

//+------------------------------------------------------------------+
//| Test Triple EMA Alignment                                        |
//+------------------------------------------------------------------+
TradePattern TestTripleEMAAlignment(const MqlRates &rates[], const double &ema9[], const double &ema21[], const double &ema50[])
{
   TradePattern result;
   result.pattern_name = "Triple EMA Perfect Alignment";
   result.total_signals = 0;
   result.winning_trades = 0;
   result.losing_trades = 0;
   
   double total_profit = 0;
   double total_loss = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   for(int i = 100; i < ArraySize(rates) - 50; i++)
   {
      if(InpLondonNYOnly && !IsLondonNYSession(rates[i].time))
         continue;
      
      //--- Bullish alignment (EMA9 > EMA21 > EMA50)
      bool bullishAlign = ema9[i] > ema21[i] && ema21[i] > ema50[i];
      bool bullishAlignFormed = !( ema9[i+1] > ema21[i+1] && ema21[i+1] > ema50[i+1]);
      
      if(bullishAlign && bullishAlignFormed)
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = ema50[i] - 3 * 10 * point;
         double tp = entry + InpMinProfitPips * 10 * point;
         
         if(SimulateTrade(rates, i, true, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
      
      //--- Bearish alignment (EMA9 < EMA21 < EMA50)
      bool bearishAlign = ema9[i] < ema21[i] && ema21[i] < ema50[i];
      bool bearishAlignFormed = !(ema9[i+1] < ema21[i+1] && ema21[i+1] < ema50[i+1]);
      
      if(bearishAlign && bearishAlignFormed)
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = ema50[i] + 3 * 10 * point;
         double tp = entry - InpMinProfitPips * 10 * point;
         
         if(SimulateTrade(rates, i, false, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
   }
   
   CalculateMetrics(result, total_profit, total_loss);
   return result;
}

//+------------------------------------------------------------------+
//| Test Momentum + Trend Strategy                                   |
//+------------------------------------------------------------------+
TradePattern TestMomentumTrend(const MqlRates &rates[], const double &ema9[], const double &ema21[], const double &ema50[], const double &rsi[])
{
   TradePattern result;
   result.pattern_name = "Momentum + Trend Confirmation";
   result.total_signals = 0;
   result.winning_trades = 0;
   result.losing_trades = 0;
   
   double total_profit = 0;
   double total_loss = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   for(int i = 100; i < ArraySize(rates) - 50; i++)
   {
      if(InpLondonNYOnly && !IsLondonNYSession(rates[i].time))
         continue;
      
      //--- Bullish: Strong uptrend + momentum
      if(ema9[i] > ema21[i] && ema21[i] > ema50[i] && 
         rsi[i] > 50 && rsi[i] < 70 &&
         rates[i].close > rates[i].open)
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = ema21[i];
         double tp = entry + (entry - sl) * 2;
         
         if(SimulateTrade(rates, i, true, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
      
      //--- Bearish: Strong downtrend + momentum
      if(ema9[i] < ema21[i] && ema21[i] < ema50[i] && 
         rsi[i] < 50 && rsi[i] > 30 &&
         rates[i].close < rates[i].open)
      {
         result.total_signals++;
         double entry = rates[i].close;
         double sl = ema21[i];
         double tp = entry - (sl - entry) * 2;
         
         if(SimulateTrade(rates, i, false, entry, sl, tp, total_profit, total_loss))
            result.winning_trades++;
         else
            result.losing_trades++;
      }
   }
   
   CalculateMetrics(result, total_profit, total_loss);
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
   total_loss += InpMaxStopPips;
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
//| Calculate metrics for pattern                                    |
//+------------------------------------------------------------------+
void CalculateMetrics(TradePattern &pattern, double total_profit, double total_loss)
{
   if(pattern.total_signals > 0)
   {
      pattern.win_rate = (double)pattern.winning_trades / pattern.total_signals * 100;
      pattern.avg_profit = pattern.winning_trades > 0 ? total_profit / pattern.winning_trades : 0;
      pattern.avg_loss = pattern.losing_trades > 0 ? total_loss / pattern.losing_trades : 0;
      pattern.profit_factor = total_loss > 0 ? total_profit / total_loss : 0;
   }
}

//+------------------------------------------------------------------+
//| Sort patterns by profit factor                                   |
//+------------------------------------------------------------------+
void SortPatternsByProfitFactor(TradePattern &patterns[])
{
   int size = ArraySize(patterns);
   for(int i = 0; i < size - 1; i++)
   {
      for(int j = i + 1; j < size; j++)
      {
         if(patterns[j].profit_factor > patterns[i].profit_factor)
         {
            TradePattern temp = patterns[i];
            patterns[i] = patterns[j];
            patterns[j] = temp;
         }
      }
   }
}
//+------------------------------------------------------------------+
