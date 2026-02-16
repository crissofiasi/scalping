//+------------------------------------------------------------------+
//|                                            BBGridAveraging.mq5   |
//|                              BB Grid Averaging EA                |
//|                                                    February 2026 |
//+------------------------------------------------------------------+
#property copyright "BB Grid Averaging EA"
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
input double   InpMinBBWidthPips = 20.0;       // Minimum BB Width (pips) - don't trade if too tight

//=== Grid Settings ===
input group "=== Grid Settings ==="
input int      InpMaxPositionsPerSide = 5;     // Max Positions Per Side
input double   InpGridStepPips = 10.0;         // Distance Between Positions (pips)
input double   InpVolumeMultiplier = 1.5;      // Volume Multiplier for each position
input double   InpBaseLotSize = 0.01;          // Base Lot Size (first position)
input double   InpMaxLotSize = 0.5;            // Maximum Lot Size (any single position)

//=== Take Profit Settings ===
input group "=== Take Profit ==="
input bool     InpUseOppositeBB_TP = true;     // Use Opposite BB as Take Profit
input bool     InpUseDynamicBB_TP = true;      // Adjust TP to closer BB if still profitable

//=== Risk Management ===
input group "=== Risk Management ==="
input bool     InpCloseFarthestWhenMaxReached = true; // Close farthest position when max reached
input double   InpMaxWeeklyDrawdownPercent = 10.0;    // Max Weekly Drawdown (%)
input double   InpMaxMonthlyDrawdownPercent = 20.0;   // Max Monthly Drawdown (%)

//=== General Settings ===
input group "=== General Settings ==="
input int      InpMagicNumber = 999888;        // Magic Number
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
   bool isBuy;
   datetime openTime;
};

PositionInfo buyPositions[];
PositionInfo sellPositions[];
int buyPositionCount = 0;
int sellPositionCount = 0;

// Drawdown tracking
double weeklyPeakBalance = 0;
double monthlyPeakBalance = 0;
datetime lastWeekReset = 0;
datetime lastMonthReset = 0;

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
   Print("BB Grid Averaging EA Initialized");
   Print("========================================");
   Print("Bollinger Bands: ", InpBB_Period, " period, ", InpBB_Deviation, " deviation");
   Print("Min BB Width: ", InpMinBBWidthPips, " pips");
   Print("Max Positions Per Side: ", InpMaxPositionsPerSide);
   Print("Grid Step: ", InpGridStepPips, " pips");
   Print("Volume Multiplier: ", InpVolumeMultiplier);
   Print("Base Lot: ", InpBaseLotSize, " | Max Lot: ", InpMaxLotSize);
   Print("Take Profit: Opposite BB Band", InpUseDynamicBB_TP ? " (dynamic adjustment enabled)" : "");
   Print("Close Farthest When Max: ", InpCloseFarthestWhenMaxReached ? "Yes" : "No");
   Print("========================================");
   
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
   IndicatorRelease(handleBB);
   Print("BB Grid Averaging EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!UpdateIndicators())
      return;
   
   if(!CheckDrawdownLimits())
      return;
   
   UpdatePositionTracking();
   
   CheckForEntry();
   
   UpdateAllPositionsTPs();
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
         buyPositions[buyPositionCount].isBuy = true;
         buyPositions[buyPositionCount].openTime = openTime;
         buyPositionCount++;
      }
      else if(!isBuy && sellPositionCount < InpMaxPositionsPerSide)
      {
         sellPositions[sellPositionCount].ticket = ticket;
         sellPositions[sellPositionCount].openPrice = openPrice;
         sellPositions[sellPositionCount].lotSize = lots;
         sellPositions[sellPositionCount].isBuy = false;
         sellPositions[sellPositionCount].openTime = openTime;
         sellPositionCount++;
      }
   }
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   double bbWidth = PriceToPips(bb_upper - bb_lower);
   
   if(bbWidth < InpMinBBWidthPips)
   {
      static datetime lastPrint = 0;
      if(InpDebugMode && TimeCurrent() - lastPrint > 300)
      {
         Print("BB too tight: ", DoubleToString(bbWidth, 1), " pips (min: ", InpMinBBWidthPips, ")");
         lastPrint = TimeCurrent();
      }
      return;
   }
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Check BUY conditions (price near lower BB)
   if(MathAbs(currentPrice - bb_lower) <= PipsToPrice(2.0))
   {
      if(ShouldAddPosition(true))
      {
         if(buyPositionCount >= InpMaxPositionsPerSide && InpCloseFarthestWhenMaxReached)
         {
            CloseFarthestPosition(true);
         }
         
         if(buyPositionCount < InpMaxPositionsPerSide)
         {
            OpenGridPosition(ORDER_TYPE_BUY, ask);
         }
      }
   }
   
   // Check SELL conditions (price near upper BB)
   if(MathAbs(currentPrice - bb_upper) <= PipsToPrice(2.0))
   {
      if(ShouldAddPosition(false))
      {
         if(sellPositionCount >= InpMaxPositionsPerSide && InpCloseFarthestWhenMaxReached)
         {
            CloseFarthestPosition(false);
         }
         
         if(sellPositionCount < InpMaxPositionsPerSide)
         {
            OpenGridPosition(ORDER_TYPE_SELL, currentPrice);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if should add position                                     |
//+------------------------------------------------------------------+
bool ShouldAddPosition(bool isBuy)
{
   int currentCount = isBuy ? buyPositionCount : sellPositionCount;
   
   // First position - always allow if at BB
   if(currentCount == 0)
      return true;
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lastEntryPrice = isBuy ? buyPositions[currentCount - 1].openPrice : sellPositions[currentCount - 1].openPrice;
   
   double requiredDistance = PipsToPrice(InpGridStepPips);
   
   if(isBuy)
   {
      // For buy: price should drop below last entry
      if(currentPrice <= lastEntryPrice - requiredDistance)
         return true;
   }
   else
   {
      // For sell: price should rise above last entry
      if(currentPrice >= lastEntryPrice + requiredDistance)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Open grid position                                               |
//+------------------------------------------------------------------+
void OpenGridPosition(ENUM_ORDER_TYPE orderType, double price)
{
   int currentCount = (orderType == ORDER_TYPE_BUY) ? buyPositionCount : sellPositionCount;
   
   // Calculate lot size with multiplier
   double lotSize = InpBaseLotSize;
   
   for(int i = 0; i < currentCount; i++)
   {
      lotSize *= InpVolumeMultiplier;
   }
   
   // Apply max lot limit
   lotSize = MathMin(lotSize, InpMaxLotSize);
   
   // Apply broker limits
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   lotSize = NormalizeDouble(lotSize, 2);
   
   // TP will be updated to average, so set initial TP far away
   double tp = (orderType == ORDER_TYPE_BUY) ? price + PipsToPrice(100.0) : price - PipsToPrice(100.0);
   tp = NormalizeDouble(tp, _Digits);
   
   string comment = StringFormat("BBGrid_%s_%d", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL", currentCount + 1);
   
   bool result = false;
   if(orderType == ORDER_TYPE_BUY)
      result = trade.Buy(lotSize, _Symbol, price, 0, tp, comment);
   else
      result = trade.Sell(lotSize, _Symbol, price, 0, tp, comment);
   
   if(result)
   {
      if(InpDebugMode)
      {
         Print("=== Grid Position Opened ===");
         Print("Type: ", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL");
         Print("Position #", currentCount + 1, " of ", InpMaxPositionsPerSide);
         Print("Lot Size: ", lotSize, " (", InpVolumeMultiplier, "x multiplier)");
         Print("Entry: ", price);
      }
   }
   else
   {
      Print("Grid position failed: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Close farthest position from current price                       |
//+------------------------------------------------------------------+
void CloseFarthestPosition(bool isBuy)
{
   int posCount = isBuy ? buyPositionCount : sellPositionCount;
   
   if(posCount == 0)
      return;
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Find farthest position
   int farthestIndex = 0;
   double maxDistance = 0;
   
   for(int i = 0; i < posCount; i++)
   {
      PositionInfo pos = isBuy ? buyPositions[i] : sellPositions[i];
      double distance = MathAbs(currentPrice - pos.openPrice);
      
      if(distance > maxDistance)
      {
         maxDistance = distance;
         farthestIndex = i;
      }
   }
   
   PositionInfo farthestPos = isBuy ? buyPositions[farthestIndex] : sellPositions[farthestIndex];
   
   if(trade.PositionClose(farthestPos.ticket))
   {
      if(InpDebugMode)
      {
         Print("=== Closed Farthest Position ===");
         Print("Type: ", isBuy ? "BUY" : "SELL");
         Print("Entry: ", farthestPos.openPrice);
         Print("Distance: ", DoubleToString(PriceToPips(maxDistance), 1), " pips");
         Print("Reason: Max positions reached, making room for new entry");
      }
   }
}

//+------------------------------------------------------------------+
//| Update all positions TPs to average + target                     |
//+------------------------------------------------------------------+
void UpdateAllPositionsTPs()
{
   UpdatePositionTP(true);   // Update BUY positions
   UpdatePositionTP(false);  // Update SELL positions
}

//+------------------------------------------------------------------+
//| Update positions TP for one side                                 |
//+------------------------------------------------------------------+
void UpdatePositionTP(bool isBuy)
{
   int posCount = isBuy ? buyPositionCount : sellPositionCount;
   
   if(posCount == 0)
      return;
   
   // Calculate weighted average entry
   double totalLots = 0;
   double weightedPrice = 0;
   
   for(int i = 0; i < posCount; i++)
   {
      PositionInfo pos = isBuy ? buyPositions[i] : sellPositions[i];
      totalLots += pos.lotSize;
      weightedPrice += pos.openPrice * pos.lotSize;
   }
   
   double avgEntry = weightedPrice / totalLots;
   
   // Calculate TP - Use opposite BB band
   double newTP;
   double oppositeBB = isBuy ? bb_upper : bb_lower;
   
   if(InpUseOppositeBB_TP)
   {
      // Primary TP: opposite BB band (BUY → upper BB, SELL → lower BB)
      newTP = oppositeBB;
      
      // Optional: if dynamic adjustment enabled and BB moved closer to entry
      if(InpUseDynamicBB_TP)
      {
         // Ensure TP is still profitable
         bool bbIsProfitable = isBuy ? (oppositeBB > avgEntry) : (oppositeBB < avgEntry);
         
         if(!bbIsProfitable)
         {
            // BB crossed average entry - use breakeven as minimum TP
            newTP = avgEntry;
            
            if(InpDebugMode)
            {
               static datetime lastPrint = 0;
               if(TimeCurrent() - lastPrint > 60)
               {
                  Print(isBuy ? "BUY" : "SELL", " TP set to breakeven - opposite BB not profitable: ",
                        DoubleToString(avgEntry, _Digits));
                  lastPrint = TimeCurrent();
               }
            }
         }
      }
   }
   else
   {
      // Fallback: breakeven
      newTP = avgEntry;
   }
   
   newTP = NormalizeDouble(newTP, _Digits);
   
   // Update all positions
   for(int i = 0; i < posCount; i++)
   {
      PositionInfo pos = isBuy ? buyPositions[i] : sellPositions[i];
      
      if(PositionSelectByTicket(pos.ticket))
      {
         double currentTP = PositionGetDouble(POSITION_TP);
         
         if(MathAbs(currentTP - newTP) > PipsToPrice(0.5))
         {
            if(trade.PositionModify(pos.ticket, 0, newTP))
            {
               if(InpDebugMode && i == 0)
               {
                  Print("Updated ", isBuy ? "BUY" : "SELL", " TPs to opposite BB: ", 
                        DoubleToString(newTP, _Digits),
                        " (avg entry: ", DoubleToString(avgEntry, _Digits), 
                        ", positions: ", posCount, ")");
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check drawdown limits                                            |
//+------------------------------------------------------------------+
bool CheckDrawdownLimits()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   datetime currentWeekStart = iTime(_Symbol, PERIOD_W1, 0);
   if(currentWeekStart != lastWeekReset)
   {
      weeklyPeakBalance = currentBalance;
      lastWeekReset = currentWeekStart;
      if(InpDebugMode)
         Print("New week - Weekly peak reset to: ", weeklyPeakBalance);
   }
   
   datetime currentMonthStart = iTime(_Symbol, PERIOD_MN1, 0);
   if(currentMonthStart != lastMonthReset)
   {
      monthlyPeakBalance = currentBalance;
      lastMonthReset = currentMonthStart;
      if(InpDebugMode)
         Print("New month - Monthly peak reset to: ", monthlyPeakBalance);
   }
   
   if(currentBalance > weeklyPeakBalance)
      weeklyPeakBalance = currentBalance;
   
   if(currentBalance > monthlyPeakBalance)
      monthlyPeakBalance = currentBalance;
   
   double weeklyDrawdown = ((weeklyPeakBalance - currentBalance) / weeklyPeakBalance) * 100.0;
   double monthlyDrawdown = ((monthlyPeakBalance - currentBalance) / monthlyPeakBalance) * 100.0;
   
   if(weeklyDrawdown >= InpMaxWeeklyDrawdownPercent)
   {
      static bool printedWeekly = false;
      if(!printedWeekly)
      {
         Print("*** WEEKLY DRAWDOWN LIMIT REACHED: ", DoubleToString(weeklyDrawdown, 2), "% ***");
         printedWeekly = true;
      }
      return false;
   }
   
   if(monthlyDrawdown >= InpMaxMonthlyDrawdownPercent)
   {
      static bool printedMonthly = false;
      if(!printedMonthly)
      {
         Print("*** MONTHLY DRAWDOWN LIMIT REACHED: ", DoubleToString(monthlyDrawdown, 2), "% ***");
         printedMonthly = true;
      }
      return false;
   }
   
   return true;
}
//+------------------------------------------------------------------+
