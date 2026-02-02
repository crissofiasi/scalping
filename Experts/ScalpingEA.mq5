//+------------------------------------------------------------------+
//|                                                   ScalpingEA.mq5 |
//|                              Bollinger Band Bounce Scalping EA   |
//|                                                    February 2026 |
//+------------------------------------------------------------------+
#property copyright "Scalping EA - Bollinger Bounce"
#property version   "2.00"
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
input int      InpBB_Period = 20;              // BB Period
input double   InpBB_Deviation = 2.0;          // BB Standard Deviation
input ENUM_APPLIED_PRICE InpBB_Price = PRICE_CLOSE;  // BB Applied Price

//=== Trend Filter ===
input group "=== Trend Filter ==="
input int      InpEMA_Filter = 50;             // Trend Filter EMA Period
input bool     InpUseTrendFilter = true;       // Use EMA Trend Filter
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5; // Timeframe

//=== Entry Settings ===
input group "=== Entry Confirmation ==="
input bool     InpRequireCandleClose = true;   // Require Candle Close Above/Below Band
input double   InpMinBandDistance = 0.0;       // Min Distance to Band (0=disable, pips)

//=== Risk Management ===
input group "=== Risk Management ==="
input double   InpRiskPercent = 1.0;           // Risk Per Trade (%)
input int      InpStopLossPips = 5;            // Stop Loss Beyond Band (pips)
input bool     InpUseBBMiddleTP = true;        // Use BB Middle as Take Profit
input int      InpFixedTPPips = 10;            // Fixed TP if not using BB Middle (pips)
input double   InpMinRiskReward = 1.5;         // Minimum Risk:Reward Ratio

//=== Trade Limits ===
input group "=== Trade Limits ==="
input int      InpMaxTradesPerSession = 5;     // Max Trades Per Session
input int      InpMagicNumber = 123456;        // Magic Number
input bool     InpDebugMode = true;            // Debug Mode (verbose logging)

//--- Global Variables
CTrade trade;
int handleBB;
int handleEMA_Filter;

double bb_upper, bb_middle, bb_lower;
double ema_filter_current;

int tradesCountToday = 0;
int tradesCountToday = 0;
datetime lastTradeDate = 0;

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
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   IndicatorRelease(handleBB);
   IndicatorRelease(handleEMA_Filter);
   
   Print("Bollinger Band Bounce EA deinitialized");
}  IndicatorRelease(handleEMA_Slow);
   IndicatorRelease(handleEMA_Filter);
   IndicatorRelease(handleATR);
   
   Print("ScalpingEA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Reset daily trade counter
   ResetDailyTradeCounter();
   
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
      static bool printedMessage = false;
      if(!printedMessage)
      {
         Print("Max trades per session reached: ", tradesCountToday);
         printedMessage = true;
      }
      return false;
   }
   
   return true;
}/+------------------------------------------------------------------+
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
   double ema_fast_array[];
   double ema_slow_array[];
   double ema_filter_array[];
   double atr_array[];
   
   ArraySetAsSeries(ema_fast_array, true);
   ArraySetAsSeries(ema_slow_array, true);
   ArraySetAsSeries(ema_filter_array, true);
   ArraySetAsSeries(atr_array, true);
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
}     Print("=== Signal Check ===");
      Print("EMA Fast: ", ema_fast_current, " (prev: ", ema_fast_previous, ")");
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
      Print("Band Width: ", DoubleToString((bb_upper - bb_lower) / point / 10, 1), " pips");
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
   //--- Validate risk:reward ratio
   double slDistance = MathAbs(price - sl);
   double tpDistance = MathAbs(tp - price);
   
   if(tpDistance / slDistance < InpMinRiskReward)
   {
      Print("Trade rejected: Risk:Reward ratio too low");
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
   string comment = StringFormat("Scalp_%s", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL");
   
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
//+------------------------------------------------------------------+
//| Calculate stop loss                                              |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slDistance = InpStopLossPips * 10 * point;
   
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
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
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
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double tpDistance = InpFixedTPPips * 10 * point;
      
      if(orderType == ORDER_TYPE_BUY)
         return entryPrice + tpDistance;
      else
         return entryPrice - tpDistance;
   }
}ouble CalculateTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   //--- Use ATR-based take profit (adaptive within min-max range)
   double atrPips = atr_current / point / 10; // Convert to pips
   int tpPips = (int)MathMax(InpTakeProfit_Min, MathMin(atrPips * 1.5, InpTakeProfit_Max));
   
   double tpDistance = tpPips * 10 * point; // Convert pips to price
   
   if(orderType == ORDER_TYPE_BUY)
      return entryPrice + tpDistance;
   else
      return entryPrice - tpDistance;
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
//| Manage open position                                             |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   //--- Get position info
   ulong ticket = PositionGetTicket(0);
   if(ticket == 0)
      return;
   
   //--- Could add trailing stop or breakeven logic here
   //--- For now, let SL/TP handle exits
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
      lastTradeDate = currentDate;
   }
}

//+------------------------------------------------------------------+
