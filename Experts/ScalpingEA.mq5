//+------------------------------------------------------------------+
//|                                                   ScalpingEA.mq5 |
//|                                          Professional Scalping EA |
//|                                                    February 2026 |
//+------------------------------------------------------------------+
#property copyright "Scalping EA"
#property version   "1.00"
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

//=== EMA Settings ===
input group "=== EMA Indicators ==="
input int      InpEMA_Fast = 9;                // Fast EMA Period
input int      InpEMA_Slow = 21;               // Slow EMA Period
input int      InpEMA_Filter = 50;             // Trend Filter EMA Period
input ENUM_TIMEFRAMES InpEntryTimeframe = PERIOD_M5;    // Entry Timeframe
input ENUM_TIMEFRAMES InpFilterTimeframe = PERIOD_M15;  // Filter Timeframe

//=== ATR Settings ===
input group "=== Volatility Filter ==="
input int      InpATR_Period = 5;              // ATR Period
input double   InpATR_MinThreshold = 0.0001;   // Minimum ATR Threshold (in price)
input bool     InpUseATRFilter = true;         // Use ATR Filter

//=== Risk Management ===
input group "=== Risk Management ==="
input double   InpRiskPercent = 1.0;           // Risk Per Trade (%)
input int      InpStopLoss_Min = 3;            // Stop Loss Min (pips)
input int      InpStopLoss_Max = 7;            // Stop Loss Max (pips)
input int      InpTakeProfit_Min = 5;          // Take Profit Min (pips)
input int      InpTakeProfit_Max = 10;         // Take Profit Max (pips)
input double   InpMinRiskReward = 1.5;         // Minimum Risk:Reward Ratio

//=== Trade Limits ===
input group "=== Trade Limits ==="
input int      InpMaxTradesPerSession = 5;     // Max Trades Per Session
input int      InpMagicNumber = 123456;        // Magic Number

//--- Global Variables
CTrade trade;
int handleEMA_Fast;
int handleEMA_Slow;
int handleEMA_Filter;
int handleATR;

double ema_fast_current, ema_fast_previous;
double ema_slow_current, ema_slow_previous;
double ema_filter_current;
double atr_current;

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
   handleEMA_Fast = iMA(_Symbol, InpEntryTimeframe, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(_Symbol, InpEntryTimeframe, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Filter = iMA(_Symbol, InpFilterTimeframe, InpEMA_Filter, 0, MODE_EMA, PRICE_CLOSE);
   handleATR = iATR(_Symbol, InpEntryTimeframe, InpATR_Period);
   
   //--- Check handles
   if(handleEMA_Fast == INVALID_HANDLE || handleEMA_Slow == INVALID_HANDLE || 
      handleEMA_Filter == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return(INIT_FAILED);
   }
   
   Print("ScalpingEA initialized successfully");
   Print("Trading Hours: ", InpStartHour, ":", InpStartMinute, " - ", InpEndHour, ":", InpEndMinute, " GMT");
   Print("Risk per trade: ", InpRiskPercent, "%");
   Print("Max trades per session: ", InpMaxTradesPerSession);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   IndicatorRelease(handleEMA_Fast);
   IndicatorRelease(handleEMA_Slow);
   IndicatorRelease(handleEMA_Filter);
   IndicatorRelease(handleATR);
   
   Print("ScalpingEA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check if new bar formed
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, InpEntryTimeframe, 0);
   
   if(currentBarTime == lastBarTime)
      return;
   
   lastBarTime = currentBarTime;
   
   //--- Reset daily trade counter
   ResetDailyTradeCounter();
   
   //--- Check trading conditions
   if(!IsTradingAllowed())
      return;
   
   //--- Update indicator values
   if(!UpdateIndicators())
      return;
   
   //--- Check for existing positions
   if(PositionSelect(_Symbol))
   {
      ManageOpenPosition();
      return;
   }
   
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
      return false;
   
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
   
   //--- Check ATR filter
   if(InpUseATRFilter && atr_current < InpATR_MinThreshold)
   {
      return false;
   }
   
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
   double ema_fast_array[];
   double ema_slow_array[];
   double ema_filter_array[];
   double atr_array[];
   
   ArraySetAsSeries(ema_fast_array, true);
   ArraySetAsSeries(ema_slow_array, true);
   ArraySetAsSeries(ema_filter_array, true);
   ArraySetAsSeries(atr_array, true);
   
   //--- Copy indicator values
   if(CopyBuffer(handleEMA_Fast, 0, 0, 2, ema_fast_array) < 2)
      return false;
   if(CopyBuffer(handleEMA_Slow, 0, 0, 2, ema_slow_array) < 2)
      return false;
   if(CopyBuffer(handleEMA_Filter, 0, 0, 1, ema_filter_array) < 1)
      return false;
   if(CopyBuffer(handleATR, 0, 0, 1, atr_array) < 1)
      return false;
   
   //--- Store values
   ema_fast_current = ema_fast_array[0];
   ema_fast_previous = ema_fast_array[1];
   ema_slow_current = ema_slow_array[0];
   ema_slow_previous = ema_slow_array[1];
   ema_filter_current = ema_filter_array[0];
   atr_current = atr_array[0];
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Bullish Setup
   bool bullishCrossover = (ema_fast_previous <= ema_slow_previous) && 
                           (ema_fast_current > ema_slow_current);
   bool bullishFilter = price > ema_filter_current;
   
   if(bullishCrossover && bullishFilter)
   {
      OpenTrade(ORDER_TYPE_BUY);
      return;
   }
   
   //--- Bearish Setup
   bool bearishCrossover = (ema_fast_previous >= ema_slow_previous) && 
                           (ema_fast_current < ema_slow_current);
   bool bearishFilter = price < ema_filter_current;
   
   if(bearishCrossover && bearishFilter)
   {
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
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   //--- Use ATR-based stop loss (adaptive within min-max range)
   double atrPips = atr_current / point / 10; // Convert to pips
   int slPips = (int)MathMax(InpStopLoss_Min, MathMin(atrPips, InpStopLoss_Max));
   
   double slDistance = slPips * 10 * point; // Convert pips to price
   
   if(orderType == ORDER_TYPE_BUY)
      return entryPrice - slDistance;
   else
      return entryPrice + slDistance;
}

//+------------------------------------------------------------------+
//| Calculate take profit                                            |
//+------------------------------------------------------------------+
double CalculateTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice)
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
