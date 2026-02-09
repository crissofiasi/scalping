//+------------------------------------------------------------------+
//|                                                ScalpingEA_V2.mq5 |
//|                              Bollinger Band Bounce Scalping EA   |
//|                                                    February 2026 |
//+------------------------------------------------------------------+
#property copyright "Scalping EA - Bollinger Bounce"
#property version   "2.10"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
//=== Trading Hours ===
input group "=== Trading Hours (GMT) ==="
input int      InpStartHour = 12;              // Start Hour (GMT)
input int      InpStartMinute = 0;             // Start Minute
input int      InpEndHour = 16;                // End Hour (GMT)
input int      InpEndMinute = 0;               // End Minute
input bool     InpAvoidAsianSession = true;    // Avoid Asian Session

//=== Bollinger Bands Settings ===
input group "=== Bollinger Bands ==="
input int      InpBB_Period = 8;               // BB Period
input double   InpBB_Deviation = 2.0;          // BB Standard Deviation
input ENUM_APPLIED_PRICE InpBB_Price = PRICE_CLOSE;  // BB Applied Price

//=== Trend Filter ===
input group "=== Trend Filter ==="
input int      InpEMA_Filter = 5;              // Trend Filter EMA Period
input bool     InpUseTrendFilter = false;      // Use EMA Trend Filter
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M1; // Timeframe

//=== Entry Settings ===
input group "=== Entry Confirmation ==="
input bool     InpRequireCandleClose = true;   // Require Candle Close Above/Below Band
input double   InpMinBandDistance = 0.0;       // Min Distance to Band (0=disable, pips)

//=== Risk Management ===
input group "=== Risk Management ==="
input double   InpRiskPercent = 0.8;           // Risk Per Trade (%)
input double   InpStopLossPips = 5.0;          // Stop Loss Beyond Band (pips)
input bool     InpUseBBMiddleTP = true;        // Use BB Middle as Take Profit
input double   InpFixedTPPips = 10.0;          // Fixed TP if not using BB Middle (pips)
input double   InpMinRiskReward = 1.5;         // Minimum Risk:Reward Ratio

//=== Commission Settings ===
input group "=== Commission Settings ==="
input double   InpCommissionPerLot = 7.0;      // Commission per Lot (in account currency)
input double   InpTPPercentForSLAdjust = 50.0; // TP % Reached to Adjust SL (0=disable)

//=== Trade Limits ===
input group "=== Trade Limits ==="
input int      InpMaxTradesPerSession = 100;   // Max Trades Per Session
input int      InpMaxLossesPerSession = 2;     // Max Losing Trades Per Session
input double   InpMaxWeeklyDrawdownPercent = 5.0;  // Max Weekly Drawdown (%)
input double   InpMaxMonthlyDrawdownPercent = 10.0; // Max Monthly Drawdown (%)
input int      InpMagicNumber = 123456;        // Magic Number
input bool     InpDebugMode = true;            // Debug Mode (verbose logging)

//--- Global Variables
CTrade trade;
int handleBB;
int handleEMA_Filter;
double bb_upper, bb_middle, bb_lower;
double ema_filter_current;

int tradesCountToday = 0;
int lossesCountToday = 0;
datetime lastTradeDate = 0;
datetime lastCheckTime = 0;

// Drawdown tracking
double weeklyPeakBalance = 0;
double monthlyPeakBalance = 0;
datetime lastWeekReset = 0;
datetime lastMonthReset = 0;

// Position tracking for SL adjustment
ulong lastPositionTicket = 0;
bool slAdjustedForPosition = false;

//+------------------------------------------------------------------+
//| Helper function to convert pips to price distance                |
//+------------------------------------------------------------------+
double PipsToPrice(double pips)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   //--- Determine pip size based on digits
   //--- For 3 or 5 digit quotes: 1 pip = 10 points
   //--- For 2 or 4 digit quotes: 1 pip = 1 point
   double pipValue = (digits == 3 || digits == 5) ? 10 * point : point;
   
   return pips * pipValue;
}

//+------------------------------------------------------------------+
//| Helper function to convert price distance to pips                |
//+------------------------------------------------------------------+
double PriceToPips(double priceDistance)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   //--- Determine pip size based on digits
   double pipValue = (digits == 3 || digits == 5) ? 10 * point : point;
   
   return priceDistance / pipValue;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Initialize trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   //--- Create indicator handles
   handleBB = iBands(_Symbol, InpTimeframe, InpBB_Period, 0, InpBB_Deviation, InpBB_Price);
   handleEMA_Filter = iMA(_Symbol, InpTimeframe, InpEMA_Filter, 0, MODE_EMA, PRICE_CLOSE);
   
   //--- Check handles
   if(handleBB == INVALID_HANDLE || handleEMA_Filter == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return(INIT_FAILED);
   }
   
   Print("========================================");
   Print("Bollinger Band Bounce EA Initialized");
   Print("========================================");
   Print("Strategy: Mean Reversion Scalping");
   Print("Bollinger Bands: ", InpBB_Period, " period, ", InpBB_Deviation, " deviation");
   Print("Trend Filter: EMA", InpEMA_Filter);
   Print("Trading Hours: ", InpStartHour, ":", StringFormat("%02d", InpStartMinute), 
         " - ", InpEndHour, ":", StringFormat("%02d", InpEndMinute), " GMT");
   Print("Risk per trade: ", InpRiskPercent, "%");
   Print("Max trades per session: ", InpMaxTradesPerSession);
   Print("Take Profit: ", InpUseBBMiddleTP ? "BB Middle Band" : IntegerToString(InpFixedTPPips) + " pips");
   Print("Commission: ", InpCommissionPerLot, " per lot");
   Print("SL Adjustment: Triggered at ", InpTPPercentForSLAdjust, "% of TP (0=disabled)");
   Print("Max Weekly Drawdown: ", InpMaxWeeklyDrawdownPercent, "%");
   Print("Max Monthly Drawdown: ", InpMaxMonthlyDrawdownPercent, "%");
   Print("========================================");
   
   //--- Initialize drawdown tracking
   weeklyPeakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   monthlyPeakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastWeekReset = TimeCurrent();
   lastMonthReset = TimeCurrent();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   IndicatorRelease(handleBB);
   IndicatorRelease(handleEMA_Filter);
   
   Print("Bollinger Band Bounce EA deinitialized");
}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- Reset daily trade counter
   ResetDailyTradeCounter();
   
   //--- Check for closed positions and update loss counter
   CheckClosedPositions();
   
   //--- Update indicator values on every tick
   if(!UpdateIndicators())
      return;
   
   //--- Check for existing positions
   if(PositionSelect(_Symbol))
   {
      ManageOpenPosition();
      return;
   }
   
   //--- Check trading conditions
   if(!IsTradingAllowed())
      return;
   
   //--- Check for entry signals
   CheckForEntry();
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
   //--- Check trading hours
   if(!IsWithinTradingHours())
   {
      static datetime lastPrintTime = 0;
      if(InpDebugMode && TimeCurrent() - lastPrintTime > 3600) // Print once per hour
      {
         MqlDateTime dt;
         TimeGMT(dt);
         Print("Outside trading hours. Current GMT: ", dt.hour, ":", dt.min);
         lastPrintTime = TimeCurrent();
      }
      return false;
   }
   
   //--- Check max trades limit
   if(tradesCountToday >= InpMaxTradesPerSession)
   {
      static bool printedTradesMessage = false;
      if(!printedTradesMessage)
      {
         Print("Max trades per session reached: ", tradesCountToday);
         printedTradesMessage = true;
      }
      return false;
   }
   
   //--- Check max losses limit
   if(lossesCountToday >= InpMaxLossesPerSession)
   {
      static bool printedLossesMessage = false;
      if(!printedLossesMessage)
      {
         Print("Max losses per session reached: ", lossesCountToday, " - Trading stopped for today");
         printedLossesMessage = true;
      }
      return false;
   }
   
   //--- Check weekly drawdown limit
   if(!CheckDrawdownLimits())
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeGMT(dt);
   
   int currentMinutes = dt.hour * 60 + dt.min;
   int startMinutes = InpStartHour * 60 + InpStartMinute;
   int endMinutes = InpEndHour * 60 + InpEndMinute;
   
   //--- Check if within allowed hours
   if(currentMinutes < startMinutes || currentMinutes >= endMinutes)
      return false;
   
   //--- Avoid Asian session (approximately 0:00 - 8:00 GMT)
   if(InpAvoidAsianSession && dt.hour >= 0 && dt.hour < 8)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Update indicator values                                          |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   double bb_upper_array[];
   double bb_middle_array[];
   double bb_lower_array[];
   double ema_filter_array[];
   
   ArraySetAsSeries(bb_upper_array, true);
   ArraySetAsSeries(bb_middle_array, true);
   ArraySetAsSeries(bb_lower_array, true);
   ArraySetAsSeries(ema_filter_array, true);
   
   //--- Copy indicator values
   if(CopyBuffer(handleBB, 1, 0, 1, bb_upper_array) < 1)  // Upper band
      return false;
   if(CopyBuffer(handleBB, 0, 0, 1, bb_middle_array) < 1) // Middle band
      return false;
   if(CopyBuffer(handleBB, 2, 0, 1, bb_lower_array) < 1)  // Lower band
      return false;
   if(CopyBuffer(handleEMA_Filter, 0, 0, 1, ema_filter_array) < 1)
      return false;
   
   //--- Store values
   bb_upper = bb_upper_array[0];
   bb_middle = bb_middle_array[0];
   bb_lower = bb_lower_array[0];
   ema_filter_current = ema_filter_array[0];
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpTimeframe, 0, 2, rates) < 2)
      return;
   
   double price_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   //--- Debug logging
   static datetime lastDebugTime = 0;
   if(InpDebugMode && TimeCurrent() - lastDebugTime > 60) // Print every minute
   {
      Print("=== BB Signal Check ===");
      Print("Price: ", price_bid);
      Print("BB Upper: ", bb_upper);
      Print("BB Middle: ", bb_middle);
      Print("BB Lower: ", bb_lower);
      Print("EMA Filter: ", ema_filter_current);
      Print("Band Width: ", DoubleToString(PriceToPips(bb_upper - bb_lower), 2), " pips");
      lastDebugTime = TimeCurrent();
   }
   
   //--- Bullish Bounce (Buy at Lower Band)
   bool touchedLowerBand = rates[0].low <= bb_lower;
   bool closedAboveLowerBand = rates[0].close > bb_lower;
   bool bullishTrend = !InpUseTrendFilter || (price_bid > ema_filter_current);
   
   if(touchedLowerBand && closedAboveLowerBand && bullishTrend)
   {
      if(InpDebugMode)
      {
         Print("*** BULLISH BB BOUNCE DETECTED ***");
         Print("Low: ", rates[0].low, " touched band: ", bb_lower);
         Print("Close: ", rates[0].close, " above band");
         Print("Trend OK: Price ", price_bid, " > EMA50 ", ema_filter_current);
      }
      OpenTrade(ORDER_TYPE_BUY);
      return;
   }
   
   //--- Bearish Bounce (Sell at Upper Band)
   bool touchedUpperBand = rates[0].high >= bb_upper;
   bool closedBelowUpperBand = rates[0].close < bb_upper;
   bool bearishTrend = !InpUseTrendFilter || (price_bid < ema_filter_current);
   
   if(touchedUpperBand && closedBelowUpperBand && bearishTrend)
   {
      if(InpDebugMode)
      {
         Print("*** BEARISH BB BOUNCE DETECTED ***");
         Print("High: ", rates[0].high, " touched band: ", bb_upper);
         Print("Close: ", rates[0].close, " below band");
         Print("Trend OK: Price ", price_bid, " < EMA50 ", ema_filter_current);
      }
      OpenTrade(ORDER_TYPE_SELL);
      return;
   }
}

//+------------------------------------------------------------------+
//| Open a trade                                                      |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double price = (orderType == ORDER_TYPE_BUY) ? 
                  SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                  SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Calculate stop loss and take profit
   double sl = CalculateStopLoss(orderType, price);
   double tp = CalculateTakeProfit(orderType, price);
   
   //--- Validate risk:reward ratio
   double slDistance = MathAbs(price - sl);
   double tpDistance = MathAbs(tp - price);
   
   double profitFactor = (slDistance > 0.0) ? (tpDistance / slDistance) : 0.0;
   if(profitFactor < InpMinRiskReward)
   {
      Print("Trade rejected: Risk:Reward ratio too low. Profit factor: ", DoubleToString(profitFactor, 2));
      return;
   }
   
   //--- Calculate lot size based on risk
   double lotSize = CalculateLotSize(sl, price);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("Calculated lot size too small: ", lotSize);
      return;
   }
   
   //--- Normalize values
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   lotSize = NormalizeDouble(lotSize, 2);
   
   //--- Execute trade
   string comment = StringFormat("BB_Bounce_%s", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL");
   
   if(orderType == ORDER_TYPE_BUY)
   {
      if(trade.Buy(lotSize, _Symbol, price, sl, tp, comment))
      {
         Print("BUY order opened: Lot=", lotSize, " SL=", sl, " TP=", tp);
         tradesCountToday++;
      }
      else
      {
         Print("BUY order failed: ", trade.ResultRetcodeDescription());
      }
   }
   else
   {
      if(trade.Sell(lotSize, _Symbol, price, sl, tp, comment))
      {
         Print("SELL order opened: Lot=", lotSize, " SL=", sl, " TP=", tp);
         tradesCountToday++;
      }
      else
      {
         Print("SELL order failed: ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate stop loss                                              |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice)
{
   double slDistance = PipsToPrice(InpStopLossPips);
   
   if(orderType == ORDER_TYPE_BUY)
   {
      //--- Place SL below lower band
      return bb_lower - slDistance;
   }
   else
   {
      //--- Place SL above upper band
      return bb_upper + slDistance;
   }
}

//+------------------------------------------------------------------+
//| Calculate take profit                                            |
//+------------------------------------------------------------------+
double CalculateTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice)
{
   if(InpUseBBMiddleTP)
   {
      //--- Use BB middle band as target (mean reversion)
      return bb_middle;
   }
   else
   {
      //--- Use fixed pip target
      double tpDistance = PipsToPrice(InpFixedTPPips);
      
      if(orderType == ORDER_TYPE_BUY)
         return entryPrice + tpDistance;
      else
         return entryPrice - tpDistance;
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLoss, double entryPrice)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * InpRiskPercent / 100.0;
   
   double slDistance = MathAbs(entryPrice - stopLoss);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lotSize = riskAmount / (slDistance / tickSize * tickValue);
   
   //--- Apply broker limits
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
}
//+------------------------------------------------------------------+
//| Reset daily trade counter                                        |
//+------------------------------------------------------------------+
void ResetDailyTradeCounter()
{
   datetime currentDate = iTime(_Symbol, PERIOD_D1, 0);
   
   if(currentDate != lastTradeDate)
   {
      tradesCountToday = 0;
      lossesCountToday = 0;
      lastTradeDate = currentDate;
      
      if(InpDebugMode)
         Print("New trading day - Counters reset");
   }
}

//+------------------------------------------------------------------+
//| Check closed positions to count losses                           |
//+------------------------------------------------------------------+
void CheckClosedPositions()
{
   //--- Only check once per second to avoid performance issues
   if(TimeCurrent() == lastCheckTime)
      return;
   
   lastCheckTime = TimeCurrent();
   
   //--- Get deals from today
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   HistorySelect(today, TimeCurrent());
   
   int totalDeals = HistoryDealsTotal();
   static int lastProcessedDeals = 0;
   
   //--- Only process new deals
   if(totalDeals <= lastProcessedDeals)
      return;
   
   //--- Check new deals for losses
   for(int i = lastProcessedDeals; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;
      
      //--- Check if it's our EA's deal
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber)
         continue;
      
      //--- Check if it's an exit deal
      if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;
      
      //--- Check if it's for our symbol
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
         continue;
      
      //--- Get profit
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      
      if(profit < 0)
      {
         lossesCountToday++;
         if(InpDebugMode)
            Print("Loss detected. Total losses today: ", lossesCountToday);
      }
   }
   
   lastProcessedDeals = totalDeals;
}

//+------------------------------------------------------------------+
//| Check weekly and monthly drawdown limits                         |
//+------------------------------------------------------------------+
bool CheckDrawdownLimits()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   //--- Reset weekly tracking on new week (Monday)
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime currentWeekStart = iTime(_Symbol, PERIOD_W1, 0);
   
   if(currentWeekStart != lastWeekReset)
   {
      weeklyPeakBalance = currentBalance;
      lastWeekReset = currentWeekStart;
      if(InpDebugMode)
         Print("New week started - Weekly peak balance reset to: ", weeklyPeakBalance);
   }
   
   //--- Reset monthly tracking on new month
   datetime currentMonthStart = iTime(_Symbol, PERIOD_MN1, 0);
   
   if(currentMonthStart != lastMonthReset)
   {
      monthlyPeakBalance = currentBalance;
      lastMonthReset = currentMonthStart;
      if(InpDebugMode)
         Print("New month started - Monthly peak balance reset to: ", monthlyPeakBalance);
   }
   
   //--- Update peak balances if current balance is higher
   if(currentBalance > weeklyPeakBalance)
   {
      weeklyPeakBalance = currentBalance;
      if(InpDebugMode)
         Print("New weekly peak balance: ", weeklyPeakBalance);
   }
   
   if(currentBalance > monthlyPeakBalance)
   {
      monthlyPeakBalance = currentBalance;
      if(InpDebugMode)
         Print("New monthly peak balance: ", monthlyPeakBalance);
   }
   
   //--- Calculate drawdowns from peak
   double weeklyDrawdown = ((weeklyPeakBalance - currentBalance) / weeklyPeakBalance) * 100.0;
   double monthlyDrawdown = ((monthlyPeakBalance - currentBalance) / monthlyPeakBalance) * 100.0;
   
   //--- Check weekly drawdown limit
   if(weeklyDrawdown >= InpMaxWeeklyDrawdownPercent)
   {
      static bool printedWeeklyDD = false;
      if(!printedWeeklyDD)
      {
         Print("*** WEEKLY DRAWDOWN LIMIT REACHED ***");
         Print("Weekly DD: ", DoubleToString(weeklyDrawdown, 2), "% (Max: ", InpMaxWeeklyDrawdownPercent, "%)");
         Print("Peak Balance: ", weeklyPeakBalance, " Current: ", currentBalance);
         Print("Trading stopped for this week");
         printedWeeklyDD = true;
      }
      return false;
   }
   
   //--- Check monthly drawdown limit
   if(monthlyDrawdown >= InpMaxMonthlyDrawdownPercent)
   {
      static bool printedMonthlyDD = false;
      if(!printedMonthlyDD)
      {
         Print("*** MONTHLY DRAWDOWN LIMIT REACHED ***");
         Print("Monthly DD: ", DoubleToString(monthlyDrawdown, 2), "% (Max: ", InpMaxMonthlyDrawdownPercent, "%)");
         Print("Peak Balance: ", monthlyPeakBalance, " Current: ", currentBalance);
         Print("Trading stopped for this month");
         printedMonthlyDD = true;
      }
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Manage open position                                             |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   //--- Get current position
   if(!PositionSelect(_Symbol))
      return;
   
   ulong positionTicket = PositionGetTicket(0);
   
   //--- Reset SL adjustment flag for new position
   if(positionTicket != lastPositionTicket)
   {
      lastPositionTicket = positionTicket;
      slAdjustedForPosition = false;
   }
   
   //--- Check if we should adjust stoploss based on TP progress
   if(InpTPPercentForSLAdjust > 0 && !slAdjustedForPosition)
   {
      AdjustStopLossForCommission();
   }
}

//+------------------------------------------------------------------+
//| Adjust stop loss to cover commission when TP% is reached         |
//+------------------------------------------------------------------+
void AdjustStopLossForCommission()
{
   if(!PositionSelect(_Symbol))
      return;
   
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   //--- Calculate distance and progress
   double tpDistance, priceDistance, tpProgress;
   double newSL = currentSL;
   bool shouldAdjust = false;
   
   if(posType == POSITION_TYPE_BUY)
   {
      tpDistance = currentTP - entryPrice;
      priceDistance = currentPrice - entryPrice;
      tpProgress = (tpDistance > 0) ? (priceDistance / tpDistance) * 100 : 0;
      
      //--- Check if price has reached the TP percentage
      if(tpProgress >= InpTPPercentForSLAdjust)
      {
         //--- Calculate commission in pips
         double commissionPips = CalculateCommissionInPips(posType);
         
         //--- Move SL above entry to cover commission
         newSL = entryPrice + PipsToPrice(commissionPips);
         
         //--- Only adjust if new SL is higher than current SL
         if(newSL > currentSL)
         {
            shouldAdjust = true;
            
            if(InpDebugMode)
            {
               Print("TP Progress: ", DoubleToString(tpProgress, 1), "% - Adjusting SL");
               Print("Old SL: ", currentSL, " New SL: ", newSL);
               Print("Commission pips to cover: ", DoubleToString(commissionPips, 2));
            }
         }
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      tpDistance = entryPrice - currentTP;
      priceDistance = entryPrice - currentPrice;
      tpProgress = (tpDistance > 0) ? (priceDistance / tpDistance) * 100 : 0;
      
      //--- Check if price has reached the TP percentage
      if(tpProgress >= InpTPPercentForSLAdjust)
      {
         //--- Calculate commission in pips
         double commissionPips = CalculateCommissionInPips(posType);
         
         //--- Move SL below entry to cover commission
         newSL = entryPrice - PipsToPrice(commissionPips);
         
         //--- Only adjust if new SL is lower than current SL
         if(newSL < currentSL)
         {
            shouldAdjust = true;
            
            if(InpDebugMode)
            {
               Print("TP Progress: ", DoubleToString(tpProgress, 1), "% - Adjusting SL");
               Print("Old SL: ", currentSL, " New SL: ", newSL);
               Print("Commission pips to cover: ", DoubleToString(commissionPips, 2));
            }
         }
      }
   }
   
   //--- If we should adjust, attempt the modification
   if(shouldAdjust)
   {
      newSL = NormalizeDouble(newSL, _Digits);
      
      if(trade.PositionModify(_Symbol, newSL, currentTP))
      {
         Print("SL adjusted successfully to cover commission: ", newSL);
         slAdjustedForPosition = true;
      }
      else
      {
         Print("Failed to adjust SL: ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate commission in pips based on position size              |
//+------------------------------------------------------------------+
double CalculateCommissionInPips(ENUM_POSITION_TYPE posType)
{
   double volume = PositionGetDouble(POSITION_VOLUME);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   //--- Calculate total commission for the position (commission per lot * number of lots)
   double totalCommission = InpCommissionPerLot * volume;
   
   //--- Convert commission to pips
   //--- Commission in currency / (value per pip) = distance in pips
   double pipDistance = PipsToPrice(1.0); // Get the price value of 1 pip
   double valuePerPip = (pipDistance / tickSize) * tickValue * volume;
   double commissionInPips = totalCommission / valuePerPip;
   
   return commissionInPips;
}

//+------------------------------------------------------------------+
