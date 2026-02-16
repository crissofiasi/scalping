//+------------------------------------------------------------------+
//|                                            NYLunchReversal.mq5   |
//|                                 Copyright 2026, Your Name        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "1.00"
#property description "NY Lunch/Reversal Strategy EA"
#property description "Trades reversals during NY lunch session (11:30-13:30 EST)"

//--- Input Parameters
input group "=== Trading Hours (EST) ==="
input int InpLunchStartHour = 11;        // Lunch Start Hour (EST)
input int InpLunchStartMinute = 30;      // Lunch Start Minute
input int InpLunchEndHour = 13;          // Lunch End Hour (EST)
input int InpLunchEndMinute = 30;        // Lunch End Minute
input int InpReversalWindowMinutes = 60; // Reversal Window After Lunch (minutes)

input group "=== Risk Management ==="
input double InpLotSize = 0.1;           // Lot Size
input double InpStopLossPips = 30.0;     // Stop Loss (pips)
input double InpTakeProfitPips = 50.0;   // Take Profit (pips)
input bool InpUseTrailingStop = true;    // Use Trailing Stop
input double InpTrailingStopPips = 20.0; // Trailing Stop (pips)
input double InpTrailingStepPips = 10.0; // Trailing Step (pips)

input group "=== Strategy Settings ==="
input double InpMinBreakoutPips = 10.0;  // Minimum Breakout (pips)
input int InpMagicNumber = 123456;       // Magic Number
input string InpTradeComment = "NYLunch"; // Trade Comment

//--- Global Variables
double lunchHigh = 0;
double lunchLow = 0;
datetime lunchStartTime = 0;
datetime lunchEndTime = 0;
bool lunchRangeEstablished = false;
bool tradedToday = false;
int currentDay = 0;

//--- Position Management
#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);
   
   Print("NYLunchReversal EA initialized successfully");
   Print("Lunch Session: ", InpLunchStartHour, ":", InpLunchStartMinute, 
         " - ", InpLunchEndHour, ":", InpLunchEndMinute, " EST");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("NYLunchReversal EA stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check for new day
   MqlDateTime time_struct;
   TimeToStruct(TimeCurrent(), time_struct);
   
   if(time_struct.day != currentDay)
   {
      ResetDailyVariables();
      currentDay = time_struct.day;
   }
   
   //--- Update trailing stops for open positions
   if(InpUseTrailingStop)
      ManageTrailingStop();
   
   //--- Get current EST time (assuming broker time needs adjustment)
   datetime currentTimeEST = GetESTTime();
   TimeToStruct(currentTimeEST, time_struct);
   
   //--- Define lunch session times
   datetime todayLunchStart = StringToTime(TimeToString(currentTimeEST, TIME_DATE) + " " + 
                              IntegerToString(InpLunchStartHour) + ":" + 
                              IntegerToString(InpLunchStartMinute));
   
   datetime todayLunchEnd = StringToTime(TimeToString(currentTimeEST, TIME_DATE) + " " + 
                            IntegerToString(InpLunchEndHour) + ":" + 
                            IntegerToString(InpLunchEndMinute));
   
   //--- During lunch session: establish high/low range
   if(currentTimeEST >= todayLunchStart && currentTimeEST <= todayLunchEnd)
   {
      UpdateLunchRange();
   }
   
   //--- After lunch session: look for reversal trade
   if(currentTimeEST > todayLunchEnd && 
      currentTimeEST <= (todayLunchEnd + InpReversalWindowMinutes * 60) &&
      lunchRangeEstablished && 
      !tradedToday)
   {
      CheckForReversalEntry();
   }
}

//+------------------------------------------------------------------+
//| Get EST Time (adjust based on your broker's time zone)          |
//+------------------------------------------------------------------+
datetime GetESTTime()
{
   // Adjust this offset based on your broker's server time
   // Example: if broker is GMT+2 and EST is GMT-5, offset = -7 hours
   int offsetHours = -7; // Modify this based on your broker
   
   return TimeCurrent() + offsetHours * 3600;
}

//+------------------------------------------------------------------+
//| Reset daily variables                                            |
//+------------------------------------------------------------------+
void ResetDailyVariables()
{
   lunchHigh = 0;
   lunchLow = 0;
   lunchStartTime = 0;
   lunchEndTime = 0;
   lunchRangeEstablished = false;
   tradedToday = false;
   
   Print("Daily variables reset for new trading day");
}

//+------------------------------------------------------------------+
//| Update lunch session high/low range                             |
//+------------------------------------------------------------------+
void UpdateLunchRange()
{
   double high = iHigh(_Symbol, PERIOD_CURRENT, 0);
   double low = iLow(_Symbol, PERIOD_CURRENT, 0);
   
   if(lunchHigh == 0 || high > lunchHigh)
      lunchHigh = high;
   
   if(lunchLow == 0 || low < lunchLow)
      lunchLow = low;
   
   lunchRangeEstablished = true;
}

//+------------------------------------------------------------------+
//| Check for reversal entry signal                                 |
//+------------------------------------------------------------------+
void CheckForReversalEntry()
{
   if(PositionSelect(_Symbol))
      return; // Already in a position
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   double minBreakout = InpMinBreakoutPips * point * 10;
   
   //--- Check for bearish reversal (price broke above lunch high, now reversing down)
   if(iHigh(_Symbol, PERIOD_CURRENT, 1) > lunchHigh)
   {
      // Price went above lunch high
      if(currentPrice < lunchHigh - minBreakout)
      {
         // Now reversing back below
         double sl = NormalizeDouble(currentPrice + InpStopLossPips * point * 10, digits);
         double tp = NormalizeDouble(currentPrice - InpTakeProfitPips * point * 10, digits);
         
         if(trade.Sell(InpLotSize, _Symbol, currentPrice, sl, tp, InpTradeComment))
         {
            Print("SELL order opened - Bearish reversal from lunch high");
            tradedToday = true;
         }
      }
   }
   
   //--- Check for bullish reversal (price broke below lunch low, now reversing up)
   if(iLow(_Symbol, PERIOD_CURRENT, 1) < lunchLow)
   {
      // Price went below lunch low
      if(ask > lunchLow + minBreakout)
      {
         // Now reversing back above
         double sl = NormalizeDouble(ask - InpStopLossPips * point * 10, digits);
         double tp = NormalizeDouble(ask + InpTakeProfitPips * point * 10, digits);
         
         if(trade.Buy(InpLotSize, _Symbol, ask, sl, tp, InpTradeComment))
         {
            Print("BUY order opened - Bullish reversal from lunch low");
            tradedToday = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stop for open positions                         |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!PositionSelect(_Symbol))
      return;
   
   if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      return;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   double trailingStop = InpTrailingStopPips * point * 10;
   double trailingStep = InpTrailingStepPips * point * 10;
   
   long posType = PositionGetInteger(POSITION_TYPE);
   double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSL = PositionGetDouble(POSITION_SL);
   double posTP = PositionGetDouble(POSITION_TP);
   
   if(posType == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double newSL = NormalizeDouble(bid - trailingStop, digits);
      
      if(newSL > posSL + trailingStep && newSL > posOpenPrice)
      {
         trade.PositionModify(_Symbol, newSL, posTP);
         Print("Trailing stop updated for BUY position: new SL = ", newSL);
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double newSL = NormalizeDouble(ask + trailingStop, digits);
      
      if((posSL == 0 || newSL < posSL - trailingStep) && newSL < posOpenPrice)
      {
         trade.PositionModify(_Symbol, newSL, posTP);
         Print("Trailing stop updated for SELL position: new SL = ", newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Trade transaction event handler                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // Handle trade events if needed
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      // Deal executed
   }
}
//+------------------------------------------------------------------+
