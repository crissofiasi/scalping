//+------------------------------------------------------------------+
//|                                                 GridScalperEA.mq5 |
//|                              Bollinger Band Grid Scalping EA     |
//|                                                    February 2026 |
//+------------------------------------------------------------------+
#property copyright "Grid Scalping EA - Bollinger Bands"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
//=== Trading Hours ===
input group "=== Trading Hours (GMT) ==="
input int      InpStartHour = 0;               // Start Hour (GMT)
input int      InpStartMinute = 0;             // Start Minute
input int      InpEndHour = 23;                // End Hour (GMT)
input int      InpEndMinute = 59;              // End Minute

//=== Bollinger Bands Settings ===
input group "=== Bollinger Bands ==="
input int      InpBB_Period = 20;              // BB Period
input double   InpBB_Deviation = 2.0;          // BB Standard Deviation
input ENUM_APPLIED_PRICE InpBB_Price = PRICE_CLOSE;  // BB Applied Price
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5; // Timeframe

//=== Strategy Selection ===
input group "=== Strategy Selection ==="
enum ENUM_GRID_STRATEGY
   {
    GRID_MEAN_REVERSION = 0,  // Mean Reversion (inside BB)
    GRID_BREAKTHROUGH = 1,     // Breakthrough (outside BB)
    GRID_HYBRID = 2            // Hybrid (both strategies)
   };
input ENUM_GRID_STRATEGY InpGridStrategy = GRID_MEAN_REVERSION; // Grid Strategy

//=== Grid Settings ===
input group "=== Grid Settings ==="
input int      InpGridLevels = 5;              // Number of Grid Levels (per side)
input double   InpGridStepPips = 5.0;          // Grid Step Size (pips)
input double   InpTakeProfitPips = 10.0;       // Take Profit (pips)
input bool     InpUseBBAsGrid = true;          // Use BB Bands as Grid Boundaries
input double   InpFixedGridRangePips = 50.0;   // Fixed Grid Range if not using BB (pips)
input double   InpBreakthroughOffsetPips = 5.0; // Breakthrough: Distance beyond BB (pips)

//=== Risk Management ===
input group "=== Risk Management ==="
input double   InpLotSize = 0.01;              // Lot Size (base for mean reversion)
input double   InpBreakthroughLotMultiplier = 1.5; // Breakthrough Lot Multiplier (vs base)
input int      InpMaxOpenOrders = 10;          // Max Open Orders (total)
input bool     InpUseStopLoss = false;         // Use Stop Loss
input double   InpStopLossPips = 100.0;        // Stop Loss (pips) - wide catastrophic protection
input double   InpMaxWeeklyDrawdownPercent = 8.0;  // Max Weekly Drawdown (%)
input double   InpMaxMonthlyDrawdownPercent = 15.0; // Max Monthly Drawdown (%)

//=== General Settings ===
input group "=== General Settings ==="
input int      InpMagicNumber = 789012;        // Magic Number
input bool     InpDebugMode = true;            // Debug Mode (verbose logging)

//--- Global Variables
CTrade trade;
int handleBB;
double bb_upper, bb_middle, bb_lower;

// Grid tracking
struct GridOrder
{
   ulong ticket;
   double level;
   bool isBuy;
};

GridOrder openOrders[];
int orderCount = 0;

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
   
   //--- Determine pip size based on digits
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
   //--- Initialize trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   //--- Create indicator handle
   handleBB = iBands(_Symbol, InpTimeframe, InpBB_Period, 0, InpBB_Deviation, InpBB_Price);
   
   if(handleBB == INVALID_HANDLE)
   {
      Print("Error creating Bollinger Bands handle!");
      return(INIT_FAILED);
   }
   
   //--- Resize orders array
   ArrayResize(openOrders, InpMaxOpenOrders);
   
   Print("========================================");
   Print("Grid Scalping EA Initialized");
   Print("========================================");
   string strategyName = "Unknown";
   if(InpGridStrategy == GRID_MEAN_REVERSION) strategyName = "Mean Reversion";
   else if(InpGridStrategy == GRID_BREAKTHROUGH) strategyName = "Breakthrough";
   else if(InpGridStrategy == GRID_HYBRID) strategyName = "Hybrid (Both)";
   Print("Strategy: ", strategyName);
   Print("Bollinger Bands: ", InpBB_Period, " period, ", InpBB_Deviation, " deviation");
   Print("Grid Levels: ", InpGridLevels, " per side");
   Print("Grid Step: ", InpGridStepPips, " pips");
   Print("Take Profit: ", InpTakeProfitPips, " pips");
   Print("Base Lot Size: ", InpLotSize);
   if(InpGridStrategy == GRID_HYBRID)
   {
      Print("Mean Reversion Lot: ", InpLotSize);
      Print("Breakthrough Lot: ", InpLotSize * InpBreakthroughLotMultiplier, " (", InpBreakthroughLotMultiplier, "x base)");
   }
   Print("Max Open Orders: ", InpMaxOpenOrders);
   Print("Stop Loss: ", InpUseStopLoss ? DoubleToString(InpStopLossPips, 1) + " pips" : "None (grid recovery)");
   Print("Use BB as Grid: ", InpUseBBAsGrid ? "Yes" : "No");
   if(InpGridStrategy == GRID_BREAKTHROUGH || InpGridStrategy == GRID_HYBRID)
      Print("Breakthrough Offset: ", InpBreakthroughOffsetPips, " pips beyond BB");
   if(InpGridStrategy == GRID_HYBRID)
      Print("Note: Running BOTH strategies - breakthrough uses ", InpBreakthroughLotMultiplier, "x lot size to hedge mean reversion");
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
   IndicatorRelease(handleBB);
   Print("Grid Scalping EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Update indicator values
   if(!UpdateIndicators())
      return;
   
   //--- Check drawdown limits
   if(!CheckDrawdownLimits())
      return;
   
   //--- Check trading hours
   if(!IsWithinTradingHours())
      return;
   
   //--- Update open orders list
   UpdateOpenOrdersList();
   
   //--- Check and place grid orders
   ManageGridOrders();
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
//| Check if within trading hours                                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeGMT(dt);
   
   int currentMinutes = dt.hour * 60 + dt.min;
   int startMinutes = InpStartHour * 60 + InpStartMinute;
   int endMinutes = InpEndHour * 60 + InpEndMinute;
   
   if(currentMinutes < startMinutes || currentMinutes >= endMinutes)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Update list of open orders                                       |
//+------------------------------------------------------------------+
void UpdateOpenOrdersList()
{
   orderCount = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      if(orderCount < InpMaxOpenOrders)
      {
         openOrders[orderCount].ticket = ticket;
         openOrders[orderCount].level = PositionGetDouble(POSITION_PRICE_OPEN);
         openOrders[orderCount].isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         orderCount++;
      }
   }
   
   static datetime lastDebugTime = 0;
   if(InpDebugMode && TimeCurrent() - lastDebugTime > 60)
   {
      Print("=== Grid Status ===");
      Print("Open Orders: ", orderCount, " / ", InpMaxOpenOrders);
      Print("BB Upper: ", bb_upper, " | Middle: ", bb_middle, " | Lower: ", bb_lower);
      Print("Band Width: ", DoubleToString(PriceToPips(bb_upper - bb_lower), 1), " pips");
      lastDebugTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Manage grid orders                                               |
//+------------------------------------------------------------------+
void ManageGridOrders()
{
   if(orderCount >= InpMaxOpenOrders)
      return;
   
   if(InpGridStrategy == GRID_MEAN_REVERSION)
      ManageMeanReversionGrid();
   else if(InpGridStrategy == GRID_BREAKTHROUGH)
      ManageBreakthroughGrid();
   else if(InpGridStrategy == GRID_HYBRID)
   {
      //--- Run both strategies
      ManageMeanReversionGrid();
      if(orderCount < InpMaxOpenOrders)  // Check again in case limit reached
         ManageBreakthroughGrid();
   }
}

//+------------------------------------------------------------------+
//| Manage mean reversion grid (inside BB)                           |
//+------------------------------------------------------------------+
void ManageMeanReversionGrid()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Calculate grid boundaries
   double gridTop, gridBottom;
   
   if(InpUseBBAsGrid)
   {
      gridTop = bb_upper;
      gridBottom = bb_lower;
   }
   else
   {
      double rangePrice = PipsToPrice(InpFixedGridRangePips);
      gridTop = currentPrice + (rangePrice / 2);
      gridBottom = currentPrice - (rangePrice / 2);
   }
   
   //--- Calculate grid step
   double gridStep = PipsToPrice(InpGridStepPips);
   
   //--- Generate grid levels
   double buyLevels[];
   double sellLevels[];
   
   ArrayResize(buyLevels, InpGridLevels);
   ArrayResize(sellLevels, InpGridLevels);
   
   //--- Buy levels from bottom to middle
   for(int i = 0; i < InpGridLevels; i++)
   {
      buyLevels[i] = gridBottom + (i * gridStep);
   }
   
   //--- Sell levels from top to middle
   for(int i = 0; i < InpGridLevels; i++)
   {
      sellLevels[i] = gridTop - (i * gridStep);
   }
   
   //--- Check and place buy orders
   for(int i = 0; i < InpGridLevels; i++)
   {
      if(orderCount >= InpMaxOpenOrders)
         break;
      
      double level = buyLevels[i];
      
      //--- Check if price is near this level
      if(MathAbs(currentPrice - level) <= PipsToPrice(1.0))
      {
         //--- Check if order already exists at this level
         if(!OrderExistsAtLevel(level, true))
         {
            double lotSize = GetLotSize(false); // Mean reversion
            PlaceGridOrder(ORDER_TYPE_BUY, level, lotSize, false);
         }
      }
   }
   
   //--- Check and place sell orders
   for(int i = 0; i < InpGridLevels; i++)
   {
      if(orderCount >= InpMaxOpenOrders)
         break;
      
      double level = sellLevels[i];
      
      //--- Check if price is near this level
      if(MathAbs(currentPrice - level) <= PipsToPrice(1.0))
      {
         //--- Check if order already exists at this level
         if(!OrderExistsAtLevel(level, false))
         {
            double lotSize = GetLotSize(false); // Mean reversion
            PlaceGridOrder(ORDER_TYPE_SELL, level, lotSize, false);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage breakthrough grid (outside BB)                            |
//+------------------------------------------------------------------+
void ManageBreakthroughGrid()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double offset = PipsToPrice(InpBreakthroughOffsetPips);
   double gridStep = PipsToPrice(InpGridStepPips);
   
   //--- Buy grid ABOVE upper band (upside breakout)
   double buyStartLevel = bb_upper + offset;
   
   //--- Sell grid BELOW lower band (downside breakout)
   double sellStartLevel = bb_lower - offset;
   
   //--- Generate breakthrough buy levels (above upper BB)
   for(int i = 0; i < InpGridLevels; i++)
   {
      if(orderCount >= InpMaxOpenOrders)
         break;
      
      double level = buyStartLevel + (i * gridStep);
      
      //--- Check if price has crossed this level
      if(currentPrice >= level - PipsToPrice(1.0))
      {
         //--- Check if order already exists at this level
         if(!OrderExistsAtLevel(level, true))
         {
            double lotSize = GetLotSize(true); // Breakthrough
            PlaceGridOrder(ORDER_TYPE_BUY, level, lotSize, true);
         }
      }
   }
   
   //--- Generate breakthrough sell levels (below lower BB)
   for(int i = 0; i < InpGridLevels; i++)
   {
      if(orderCount >= InpMaxOpenOrders)
         break;
      
      double level = sellStartLevel - (i * gridStep);
      
      //--- Check if price has crossed this level
      if(currentPrice <= level + PipsToPrice(1.0))
      {
         //--- Check if order already exists at this level
         if(!OrderExistsAtLevel(level, false))
         {
            double lotSize = GetLotSize(true); // Breakthrough
            PlaceGridOrder(ORDER_TYPE_SELL, level, lotSize, true);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get lot size based on grid type (mean reversion vs breakthrough) |
//+------------------------------------------------------------------+
double GetLotSize(bool isBreakthroughGrid)
{
   if(InpGridStrategy == GRID_HYBRID && isBreakthroughGrid)
      return NormalizeDouble(InpLotSize * InpBreakthroughLotMultiplier, 2);
   
   return InpLotSize;
}

//+------------------------------------------------------------------+
//| Check if order exists at specific level                          |
//+------------------------------------------------------------------+
bool OrderExistsAtLevel(double level, bool isBuy)
{
   double tolerance = PipsToPrice(0.5);
   
   for(int i = 0; i < orderCount; i++)
   {
      if(openOrders[i].isBuy == isBuy)
      {
         if(MathAbs(openOrders[i].level - level) <= tolerance)
            return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Place grid order                                                  |
//+------------------------------------------------------------------+
void PlaceGridOrder(ENUM_ORDER_TYPE orderType, double level, double lotSize = 0, bool isBreakthroughGrid = false)
{
   //--- Use default lot size if not specified
   if(lotSize <= 0)
      lotSize = GetLotSize(isBreakthroughGrid);
   
   double price = (orderType == ORDER_TYPE_BUY) ? 
                  SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                  SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Calculate TP
   double tp;
   if(orderType == ORDER_TYPE_BUY)
      tp = price + PipsToPrice(InpTakeProfitPips);
   else
      tp = price - PipsToPrice(InpTakeProfitPips);
   
   //--- Calculate SL if enabled
   double sl = 0;
   if(InpUseStopLoss)
   {
      if(orderType == ORDER_TYPE_BUY)
         sl = price - PipsToPrice(InpStopLossPips);
      else
         sl = price + PipsToPrice(InpStopLossPips);
   }
   
   //--- Normalize values
   lotSize = NormalizeDouble(lotSize, 2);
   tp = NormalizeDouble(tp, _Digits);
   if(sl > 0)
      sl = NormalizeDouble(sl, _Digits);
   
   //--- Execute trade
   string gridType = isBreakthroughGrid ? "BT" : "MR";
   string comment = StringFormat("Grid_%s_%s_%.5f", 
                                 gridType,
                                 (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL",
                                 level);
   
   bool result = false;
   
   if(orderType == ORDER_TYPE_BUY)
   {
      result = trade.Buy(lotSize, _Symbol, price, sl, tp, comment);
   }
   else
   {
      result = trade.Sell(lotSize, _Symbol, price, sl, tp, comment);
   }
   
   if(result)
   {
      if(InpDebugMode)
         Print("Grid order placed: ", comment, " TP=", tp);
      
      //--- Add to our list
      if(orderCount < InpMaxOpenOrders)
      {
         openOrders[orderCount].ticket = trade.ResultOrder();
         openOrders[orderCount].level = level;
         openOrders[orderCount].isBuy = (orderType == ORDER_TYPE_BUY);
         orderCount++;
      }
   }
   else
   {
      Print("Grid order failed: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Check weekly and monthly drawdown limits                         |
//+------------------------------------------------------------------+
bool CheckDrawdownLimits()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   //--- Reset weekly tracking on new week
   datetime currentWeekStart = iTime(_Symbol, PERIOD_W1, 0);
   if(currentWeekStart != lastWeekReset)
   {
      weeklyPeakBalance = currentBalance;
      lastWeekReset = currentWeekStart;
      if(InpDebugMode)
         Print("New week - Weekly peak reset to: ", weeklyPeakBalance);
   }
   
   //--- Reset monthly tracking on new month
   datetime currentMonthStart = iTime(_Symbol, PERIOD_MN1, 0);
   if(currentMonthStart != lastMonthReset)
   {
      monthlyPeakBalance = currentBalance;
      lastMonthReset = currentMonthStart;
      if(InpDebugMode)
         Print("New month - Monthly peak reset to: ", monthlyPeakBalance);
   }
   
   //--- Update peak balances
   if(currentBalance > weeklyPeakBalance)
      weeklyPeakBalance = currentBalance;
   
   if(currentBalance > monthlyPeakBalance)
      monthlyPeakBalance = currentBalance;
   
   //--- Calculate drawdowns
   double weeklyDrawdown = ((weeklyPeakBalance - currentBalance) / weeklyPeakBalance) * 100.0;
   double monthlyDrawdown = ((monthlyPeakBalance - currentBalance) / monthlyPeakBalance) * 100.0;
   
   //--- Check limits
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
