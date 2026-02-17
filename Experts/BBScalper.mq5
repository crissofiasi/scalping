//+------------------------------------------------------------------+
//|                                                   BBScalper.mq5   |
//|                              BB Breakout Scalper                  |
//|                                                    February 2026 |
//+------------------------------------------------------------------+
#property copyright "BB Scalper EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
//=== Bollinger Bands Settings ===
input group "=== Bollinger Bands ==="
input int      InpBB_Period = 20;              // BB Period
input double   InpBB_Deviation = 2.0;          // BB Standard Deviation
input ENUM_APPLIED_PRICE InpBB_Price = PRICE_CLOSE;  // BB Applied Price
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5; // Timeframe

//=== Position Management ===
input group "=== Position Management ==="
input int      InpMaxPositionsPerSide = 5;     // Max Positions Per Side
input double   InpMinDistancePips = 10.0;      // Min Distance for Additional Position (pips)
input double   InpBaseLotSize = 0.01;          // Lot Size Per Position
input bool     InpCloseOnOppositeSignal = true; // Close Positions on Opposite Signal

//=== Take Profit / Stop Loss ===
input group "=== TP/SL Settings ==="
input bool     InpUseMiddleBB_TP = true;       // Use Middle BB as Take Profit
input double   InpFixedTP_Pips = 20.0;         // Fixed TP (pips) if not using Middle BB
input double   InpStopLoss_Pips = 30.0;        // Stop Loss (pips, 0=disabled)

//=== Spike Protection ===
input group "=== Spike Protection ==="
input bool     InpEnableSpikeTrailing = true;  // Enable Trailing Stop on Spikes
input double   InpSpikeTriggerPips = 15.0;     // Spike Distance Beyond BB (pips)

//=== General Settings ===
input group "=== General Settings ==="
input int      InpMagicNumber = 888777;        // Magic Number
input bool     InpDebugMode = true;            // Debug Mode (verbose logging)

//--- Global Variables
CTrade trade;
int handleBB;
double bb_upper, bb_middle, bb_lower;

// Position tracking
struct PositionInfo
{
   ulong ticket;
   double openPrice;
   double lotSize;
   datetime openTime;
};

PositionInfo buyPositions[];
PositionInfo sellPositions[];
int buyPositionCount = 0;
int sellPositionCount = 0;

// Signal tracking to avoid repeated entries
datetime lastBuySignalTime = 0;
datetime lastSellSignalTime = 0;

// Track if price was outside BB (for detecting return inside)
bool priceWasBelowLowerBB = false;
bool priceWasAboveUpperBB = false;

//+------------------------------------------------------------------+
//| Helper function to convert pips to price distance                |
//+------------------------------------------------------------------+
double PipsToPrice(double pips)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
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
   
   double pipValue = (digits == 3 || digits == 5) ? 10 * point : point;
   
   return priceDistance / pipValue;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   handleBB = iBands(_Symbol, InpTimeframe, InpBB_Period, 0, InpBB_Deviation, InpBB_Price);
   
   if(handleBB == INVALID_HANDLE)
   {
      Print("Error creating Bollinger Bands handle!");
      return(INIT_FAILED);
   }
   
   Print("========================================");
   Print("BB Scalper EA Initialized");
   Print("========================================");
   Print("Bollinger Bands: ", InpBB_Period, " period, ", InpBB_Deviation, " deviation");
   Print("Max Positions Per Side: ", InpMaxPositionsPerSide);
   Print("Min Distance for Add: ", InpMinDistancePips, " pips");
   Print("Lot Size: ", InpBaseLotSize);
   Print("Take Profit: ", InpUseMiddleBB_TP ? "Middle BB" : DoubleToString(InpFixedTP_Pips, 1) + " pips");
   Print("Stop Loss: ", InpStopLoss_Pips > 0 ? DoubleToString(InpStopLoss_Pips, 1) + " pips" : "Disabled");
   Print("Close on Opposite Signal: ", InpCloseOnOppositeSignal ? "Yes" : "No");
   Print("Spike Trailing: ", InpEnableSpikeTrailing ? "Enabled at " + DoubleToString(InpSpikeTriggerPips, 1) + " pips beyond BB" : "Disabled");
   Print("========================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleBB);
   Print("BB Scalper EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!UpdateIndicators())
      return;
   
   UpdatePositionTracking();
   
   CheckForSignals();
   
   if(InpUseMiddleBB_TP)
      UpdateDynamicTPs();
   
   if(InpEnableSpikeTrailing)
      CheckForSpikes();
}

//+------------------------------------------------------------------+
//| Update indicator values                                          |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   double bb_upper_array[];
   double bb_middle_array[];
   double bb_lower_array[];
   
   ArraySetAsSeries(bb_upper_array, true);
   ArraySetAsSeries(bb_middle_array, true);
   ArraySetAsSeries(bb_lower_array, true);
   
   if(CopyBuffer(handleBB, 1, 0, 1, bb_upper_array) < 1)
      return false;
   if(CopyBuffer(handleBB, 0, 0, 1, bb_middle_array) < 1)
      return false;
   if(CopyBuffer(handleBB, 2, 0, 1, bb_lower_array) < 1)
      return false;
   
   bb_upper = bb_upper_array[0];
   bb_middle = bb_middle_array[0];
   bb_lower = bb_lower_array[0];
   
   return true;
}

//+------------------------------------------------------------------+
//| Update position tracking                                         |
//+------------------------------------------------------------------+
void UpdatePositionTracking()
{
   buyPositionCount = 0;
   sellPositionCount = 0;
   ArrayResize(buyPositions, InpMaxPositionsPerSide);
   ArrayResize(sellPositions, InpMaxPositionsPerSide);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double lots = PositionGetDouble(POSITION_VOLUME);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      
      if(isBuy && buyPositionCount < InpMaxPositionsPerSide)
      {
         buyPositions[buyPositionCount].ticket = ticket;
         buyPositions[buyPositionCount].openPrice = openPrice;
         buyPositions[buyPositionCount].lotSize = lots;
         buyPositions[buyPositionCount].openTime = openTime;
         buyPositionCount++;
      }
      else if(!isBuy && sellPositionCount < InpMaxPositionsPerSide)
      {
         sellPositions[sellPositionCount].ticket = ticket;
         sellPositions[sellPositionCount].openPrice = openPrice;
         sellPositions[sellPositionCount].lotSize = lots;
         sellPositions[sellPositionCount].openTime = openTime;
         sellPositionCount++;
      }
   }
}

//+------------------------------------------------------------------+
//| Check for entry/exit signals                                     |
//+------------------------------------------------------------------+
void CheckForSignals()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Track when price goes outside bands
   bool currentlyBelowLower = (currentPrice < bb_lower);
   bool currentlyAboveUpper = (currentPrice > bb_upper);
   
   // BUY Signal: Price was below lower BB, now returned inside
   bool buySignal = (priceWasBelowLowerBB && !currentlyBelowLower && currentPrice >= bb_lower);
   
   // SELL Signal: Price was above upper BB, now returned inside
   bool sellSignal = (priceWasAboveUpperBB && !currentlyAboveUpper && currentPrice <= bb_upper);
   
   // Update tracking
   if(currentlyBelowLower)
      priceWasBelowLowerBB = true;
   else if(currentPrice > bb_middle)
      priceWasBelowLowerBB = false;  // Reset when price moves away
   
   if(currentlyAboveUpper)
      priceWasAboveUpperBB = true;
   else if(currentPrice < bb_middle)
      priceWasAboveUpperBB = false;  // Reset when price moves away
   
   // Handle BUY Signal
   if(buySignal)
   {
      // Check if opposite signal - close SELL positions
      if(InpCloseOnOppositeSignal && sellPositionCount > 0)
      {
         CloseAllPositions(false);
         if(InpDebugMode)
            Print("BUY signal detected - closing all SELL positions");
      }
      
      // Check if we should open/add BUY position
      if(ShouldOpenPosition(true))
      {
         OpenPosition(ORDER_TYPE_BUY, ask);
         lastBuySignalTime = TimeCurrent();
      }
   }
   
   // Handle SELL Signal
   if(sellSignal)
   {
      // Check if opposite signal - close BUY positions
      if(InpCloseOnOppositeSignal && buyPositionCount > 0)
      {
         CloseAllPositions(true);
         if(InpDebugMode)
            Print("SELL signal detected - closing all BUY positions");
      }
      
      // Check if we should open/add SELL position
      if(ShouldOpenPosition(false))
      {
         OpenPosition(ORDER_TYPE_SELL, currentPrice);
         lastSellSignalTime = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| Check if should open position                                    |
//+------------------------------------------------------------------+
bool ShouldOpenPosition(bool isBuy)
{
   int currentCount = isBuy ? buyPositionCount : sellPositionCount;
   
   // No positions - open first one
   if(currentCount == 0)
      return true;
   
   // Max positions reached
   if(currentCount >= InpMaxPositionsPerSide)
      return false;
   
   // Check minimum distance from last position
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lastEntryPrice = isBuy ? buyPositions[currentCount - 1].openPrice : sellPositions[currentCount - 1].openPrice;
   
   double distance = MathAbs(currentPrice - lastEntryPrice);
   double minDistance = PipsToPrice(InpMinDistancePips);
   
   if(distance >= minDistance)
   {
      if(InpDebugMode)
      {
         Print("Additional ", isBuy ? "BUY" : "SELL", " position allowed - Distance: ", 
               DoubleToString(PriceToPips(distance), 1), " pips (min: ", InpMinDistancePips, ")");
      }
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Open position                                                     |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE orderType, double price)
{
   int currentCount = (orderType == ORDER_TYPE_BUY) ? buyPositionCount : sellPositionCount;
   
   double lotSize = InpBaseLotSize;
   
   // Apply broker limits
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   lotSize = NormalizeDouble(lotSize, 2);
   
   // Calculate TP and SL
   double tp = 0;
   double sl = 0;
   
   if(orderType == ORDER_TYPE_BUY)
   {
      // BUY TP
      if(InpUseMiddleBB_TP)
         tp = bb_middle;
      else
         tp = price + PipsToPrice(InpFixedTP_Pips);
      
      // BUY SL
      if(InpStopLoss_Pips > 0)
         sl = price - PipsToPrice(InpStopLoss_Pips);
   }
   else
   {
      // SELL TP
      if(InpUseMiddleBB_TP)
         tp = bb_middle;
      else
         tp = price - PipsToPrice(InpFixedTP_Pips);
      
      // SELL SL
      if(InpStopLoss_Pips > 0)
         sl = price + PipsToPrice(InpStopLoss_Pips);
   }
   
   tp = NormalizeDouble(tp, _Digits);
   sl = NormalizeDouble(sl, _Digits);
   
   string comment = StringFormat("BBScalp_%s_%d", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL", currentCount + 1);
   
   bool result = false;
   if(orderType == ORDER_TYPE_BUY)
      result = trade.Buy(lotSize, _Symbol, price, sl, tp, comment);
   else
      result = trade.Sell(lotSize, _Symbol, price, sl, tp, comment);
   
   if(result)
   {
      if(InpDebugMode)
      {
         Print("=== Position Opened ===");
         Print("Type: ", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL");
         Print("Position #", currentCount + 1);
         Print("Lot Size: ", lotSize);
         Print("Entry: ", DoubleToString(price, _Digits));
         Print("TP: ", DoubleToString(tp, _Digits), " (", InpUseMiddleBB_TP ? "Middle BB" : "Fixed", ")");
         if(InpStopLoss_Pips > 0)
            Print("SL: ", DoubleToString(sl, _Digits));
         Print("BB Lower: ", DoubleToString(bb_lower, _Digits));
         Print("BB Middle: ", DoubleToString(bb_middle, _Digits));
         Print("BB Upper: ", DoubleToString(bb_upper, _Digits));
      }
   }
   else
   {
      Print("Position open failed: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Close all positions for one side                                 |
//+------------------------------------------------------------------+
void CloseAllPositions(bool isBuy)
{
   int posCount = isBuy ? buyPositionCount : sellPositionCount;
   
   if(posCount == 0)
      return;
   
   int closedCount = 0;
   
   for(int i = 0; i < posCount; i++)
   {
      PositionInfo pos = isBuy ? buyPositions[i] : sellPositions[i];
      
      if(trade.PositionClose(pos.ticket))
         closedCount++;
   }
   
   if(InpDebugMode && closedCount > 0)
   {
      Print("Closed ", closedCount, " ", isBuy ? "BUY" : "SELL", " position(s) on opposite signal");
   }
}

//+------------------------------------------------------------------+
//| Check for favorable spikes and set trailing stops                |
//+------------------------------------------------------------------+
void CheckForSpikes()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Check for BUY positions spike (price above upper BB)
   if(buyPositionCount > 0)
   {
      double distanceAboveUpper = currentPrice - bb_upper;
      
      if(distanceAboveUpper >= PipsToPrice(InpSpikeTriggerPips))
      {
         // Spike detected - set trailing stop at upper BB and extended TP for all BUY positions
         double bbWidth = bb_upper - bb_middle;
         double newTP = NormalizeDouble(bb_upper + bbWidth, _Digits);
         
         for(int i = 0; i < buyPositionCount; i++)
         {
            if(PositionSelectByTicket(buyPositions[i].ticket))
            {
               double currentSL = PositionGetDouble(POSITION_SL);
               double newSL = NormalizeDouble(bb_upper, _Digits);
               double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               
               // Only update if new SL is better (higher) and above entry (profitable)
               if(newSL > entryPrice && (currentSL == 0 || newSL > currentSL))
               {
                  if(trade.PositionModify(buyPositions[i].ticket, newSL, newTP))
                  {
                     if(InpDebugMode && i == 0)
                     {
                        Print("=== SPIKE DETECTED - BUY ===");
                        Print("Price above upper BB by: ", DoubleToString(PriceToPips(distanceAboveUpper), 1), " pips");
                        Print("Trailing stop set at upper BB: ", DoubleToString(newSL, _Digits));
                        Print("Extended TP set at: ", DoubleToString(newTP, _Digits), " (+", DoubleToString(PriceToPips(bbWidth), 1), " pips from BB)");
                        Print("Protecting ", buyPositionCount, " BUY position(s)");
                     }
                  }
               }
            }
         }
      }
   }
   
   // Check for SELL positions spike (price below lower BB)
   if(sellPositionCount > 0)
   {
      double distanceBelowLower = bb_lower - currentPrice;
      
      if(distanceBelowLower >= PipsToPrice(InpSpikeTriggerPips))
      {
         // Spike detected - set trailing stop at lower BB and extended TP for all SELL positions
         double bbWidth = bb_middle - bb_lower;
         double newTP = NormalizeDouble(bb_lower - bbWidth, _Digits);
         
         for(int i = 0; i < sellPositionCount; i++)
         {
            if(PositionSelectByTicket(sellPositions[i].ticket))
            {
               double currentSL = PositionGetDouble(POSITION_SL);
               double newSL = NormalizeDouble(bb_lower, _Digits);
               double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               
               // Only update if new SL is better (lower) and below entry (profitable)
               if(newSL < entryPrice && (currentSL == 0 || newSL < currentSL))
               {
                  if(trade.PositionModify(sellPositions[i].ticket, newSL, newTP))
                  {
                     if(InpDebugMode && i == 0)
                     {
                        Print("=== SPIKE DETECTED - SELL ===");
                        Print("Price below lower BB by: ", DoubleToString(PriceToPips(distanceBelowLower), 1), " pips");
                        Print("Trailing stop set at lower BB: ", DoubleToString(newSL, _Digits));
                        Print("Extended TP set at: ", DoubleToString(newTP, _Digits), " (-", DoubleToString(PriceToPips(bbWidth), 1), " pips from BB)");
                        Print("Protecting ", sellPositionCount, " SELL position(s)");
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update TPs dynamically to follow middle BB                       |
//+------------------------------------------------------------------+
void UpdateDynamicTPs()
{
   if(!InpUseMiddleBB_TP)
      return;
   
   double newTP = NormalizeDouble(bb_middle, _Digits);
   
   // Update BUY positions
   for(int i = 0; i < buyPositionCount; i++)
   {
      if(PositionSelectByTicket(buyPositions[i].ticket))
      {
         double currentTP = PositionGetDouble(POSITION_TP);
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         // Only update if TP is still profitable and changed significantly
         if(newTP > entryPrice && MathAbs(currentTP - newTP) > PipsToPrice(1.0))
         {
            trade.PositionModify(buyPositions[i].ticket, PositionGetDouble(POSITION_SL), newTP);
         }
      }
   }
   
   // Update SELL positions
   for(int i = 0; i < sellPositionCount; i++)
   {
      if(PositionSelectByTicket(sellPositions[i].ticket))
      {
         double currentTP = PositionGetDouble(POSITION_TP);
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         // Only update if TP is still profitable and changed significantly
         if(newTP < entryPrice && MathAbs(currentTP - newTP) > PipsToPrice(1.0))
         {
            trade.PositionModify(sellPositions[i].ticket, PositionGetDouble(POSITION_SL), newTP);
         }
      }
   }
}
//+------------------------------------------------------------------+
