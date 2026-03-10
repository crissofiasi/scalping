//+------------------------------------------------------------------+
//|                                              MADirectionEA.mq5   |
//|                                  Copyright 2026, Cris Trading   |
//|                                                                  |
//|  Strategy:                                                       |
//|  1. MA-based entry: buy if prev bar closes above MA, sell below  |
//|  2. Early close: on bar change, close profitable EA trades       |
//|  3. Early protection: when price reaches EarlyTpPct% of TP,     |
//|     move SL to entry + MinProfitPoints (locks in profit)         |
//|  4. EA reset recovery: on init, scan open positions and rebuild  |
//|     tracking state so hedging logic resumes correctly            |
//|  5. Reversal threshold in points (not % of TP)                  |
//|  6. Dynamic TP = max(max bar H-L over DynTpBars, TpMinPoints)   |
//|  7. Weekend filter: inhibit new trades / close open trades       |
//|     N bars before weekend session end                            |
//|  8. Scale-in: on same-dir bar signal, average into open position |
//|     if price is >= MinProfitPoints adverse from nearest entry;   |
//|     volume sized to cover floating loss at new dynamic TP        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Cris Trading"
#property link      ""
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>

//--- Input parameters -----------------------------------------------
input group "=== MA Signal ==="
input int              MA_Period  = 20;          // MA period
input ENUM_MA_METHOD   MA_Method  = MODE_EMA;    // MA method (EMA, SMA, SMMA, LWMA)
input ENUM_APPLIED_PRICE MA_Price = PRICE_CLOSE; // MA applied price

input group "=== Trade Settings ==="
input double BaseLotSize    = 0.01;    // Base lot size
input double TpMinPoints    = 200.0;   // Min TP in points (fixed floor)
input double ReversePoints  = 100.0;   // Reversal threshold in points
input long   MagicNumber    = 77778;   // Magic number
input int    Slippage       = 50;      // Slippage in points
input string TradeComment   = "MADir"; // Comment prefix

input group "=== Dynamic TP ==="
input int    DynTpBars      = 10;      // Lookback bars for dynamic TP
//   TP = max( max(High-Low) over DynTpBars bars,  TpMinPoints )  [in points]

input group "=== Early Close & Protection ==="
input bool   EnableEarlyClose      = true;  // Close profitable trades on bar change
input bool   EnableEarlyProtection = true;  // Move SL to lock min profit when near TP
input bool   EnableScaleIn         = true;  // Scale-in to same-dir position when price moves against
input double EarlyTpPct      = 50.0;  // Price reaches X% of TP → activate SL lock
input double MinProfitPoints = 20.0;  // Protective SL offset / scale-in gap (points)

input group "=== Risk Settings ==="
input double MaxLotSize       = 50.0; // Max lot size cap
input double MaxTotalOpenLoss = 0.0;  // Max floating loss in account currency (0=off)
input int    CooloffBars      = 2;    // Cooloff bars after loss-breaker fired
input bool   OneTradePerBar   = true; // Only one entry per direction per bar

input group "=== Weekend Filter (server time) ==="
input int WeekendInhibitBars = 3;     // Bars before weekend: block new entries (0=off)
input int WeekendCloseBars   = 1;     // Bars before weekend: close all trades   (0=off)
input int WeekendCloseHour   = 22;    // Friday hour treated as session end (server time)

input group "=== Trading Hours (server time) ==="
input bool H00=true;  input bool H01=true;  input bool H02=true;  input bool H03=true;
input bool H04=true;  input bool H05=true;  input bool H06=true;  input bool H07=true;
input bool H08=true;  input bool H09=true;  input bool H10=true;  input bool H11=true;
input bool H12=true;  input bool H13=true;  input bool H14=true;  input bool H15=true;
input bool H16=true;  input bool H17=true;  input bool H18=true;  input bool H19=true;
input bool H20=true;  input bool H21=true;  input bool H22=true;  input bool H23=true;

//--- Constants
#define TAG_ORIG "ORIG"
#define TAG_REV  "REV"
#define TAG_AVG  "AVG"

//--- Trade record --------------------------------------------------
struct TradeRec
{
   ulong    ticket;
   int      direction;      // 1 = BUY, -1 = SELL
   double   entryPrice;
   double   tpPoints;       // TP distance in points used at entry
   double   baseLot;
   bool     hedged;         // reversal already fired?
   ulong    hedgeTicket;    // ticket of hedge position (0 = none)
   datetime barTime;
   bool     isReversal;
   bool     isScaleIn;      // opened as a scale-in (averaging) trade?
   bool     earlyProtected; // SL already locked to min-profit level?
};

TradeRec g_trades[];

//--- State
datetime g_lastBarTime     = 0;
datetime g_lastBuyBar      = 0;
datetime g_lastSellBar     = 0;
int      g_cooloffBarsLeft = 0;
int      g_maHandle        = INVALID_HANDLE;

CTrade trade;

//+------------------------------------------------------------------+
//| Calculate dynamic TP in points for current market condition      |
//+------------------------------------------------------------------+
double CalcDynamicTP()
{
   double maxRange = 0.0;
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) point = 0.00001;

   for(int i = 1; i <= DynTpBars; i++)
   {
      double hi = iHigh(_Symbol, _Period, i);
      double lo = iLow (_Symbol, _Period, i);
      if(hi <= 0 || lo <= 0) continue;
      double rangePts = (hi - lo) / point;
      if(rangePts > maxRange) maxRange = rangePts;
   }

   return MathMax(maxRange, TpMinPoints);
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_maHandle = iMA(_Symbol, _Period, MA_Period, 0, MA_Method, MA_Price);
   if(g_maHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create MA indicator handle.");
      return INIT_FAILED;
   }

   ArrayResize(g_trades, 0);

   //--- Recovery: rebuild tracking from open positions
   RebuildFromOpenPositions();

   Print("MADirectionEA initialized.  Symbol: ", _Symbol,
         "  TF: ", EnumToString(_Period),
         "  MA: ", MA_Period, " ", EnumToString(MA_Method),
         "  TpMinPoints: ", TpMinPoints,
         "  ReversePoints: ", ReversePoints,
         "  Recovered: ", ArraySize(g_trades), " positions");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_maHandle != INVALID_HANDLE)
      IndicatorRelease(g_maHandle);
   ArrayFree(g_trades);
}

//+------------------------------------------------------------------+
//| Expert tick                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 1. Max loss breaker
   CheckMaxLossBreaker();

   //--- 2. Per-tick early protection (move SL to lock in min profit)
   if(EnableEarlyProtection)
      CheckEarlyProtection();

   //--- 3. Check reversal thresholds
   CheckReversalTriggers();

   //--- 4. New-bar logic
   datetime barTimes[];
   if(CopyTime(_Symbol, _Period, 0, 2, barTimes) < 2) return;

   datetime currentBarTime = barTimes[1]; // last CLOSED bar

   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;

      //--- 4a. Weekend close-trades filter
      if(WeekendCloseBars > 0 && IsNearWeekend(WeekendCloseBars))
      {
         Print("Weekend close filter: closing all EA trades.");
         CloseAllEATrades();
      }
      else
      {
         //--- 4b. Early bar-close: close profitable trades on bar change
         if(EnableEarlyClose)
            CloseAllProfitableTrades();
      }

      //--- 4c. Cooloff countdown
      if(g_cooloffBarsLeft > 0)
      {
         g_cooloffBarsLeft--;
         Print("Cooloff active: ", g_cooloffBarsLeft, " bar(s) remaining.");
      }
      else
      {
         //--- 4d. Weekend entry inhibit
         if(WeekendInhibitBars > 0 && IsNearWeekend(WeekendInhibitBars))
         {
            Print("Weekend inhibit filter: skipping new entry.");
         }
         else if(IsTradingHourAllowed())
         {
            OnNewBar(currentBarTime);   // handles fresh entries and scale-in
         }
         else
         {
            MqlDateTime _dt; TimeToStruct(TimeCurrent(), _dt);
            Print("New bar skipped – outside trading hours (H", _dt.hour, ")");
         }
      }
   }

   //--- 5. Clean stale records
   PruneClosedTrades();
}

//+------------------------------------------------------------------+
//| Called once per new bar to evaluate MA signal and open trade     |
//+------------------------------------------------------------------+
void OnNewBar(datetime closedBarTime)
{
   //--- Get MA value on the CLOSED bar (index 1)
   double maVal[];
   ArraySetAsSeries(maVal, true);
   if(CopyBuffer(g_maHandle, 0, 0, 3, maVal) < 3)
   {
      Print("OnNewBar: CopyBuffer failed for MA.");
      return;
   }

   double prevClose = iClose(_Symbol, _Period, 1);
   double maOnPrev  = maVal[1];   // MA value on previous (closed) bar

   if(prevClose <= 0 || maOnPrev <= 0) return;

   bool buySignal  = prevClose > maOnPrev;   // close above MA → buy
   bool sellSignal = prevClose < maOnPrev;   // close below MA → sell

   double dynTp = CalcDynamicTP();

   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(buySignal)
   {
      if(!OneTradePerBar || g_lastBuyBar != closedBarTime)
      {
         g_lastBuyBar = closedBarTime;
         double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         int    openBuys = CountOpenEATradesInDir(1);

         if(openBuys == 0)
         {
            //--- Fresh BUY entry (no existing same-dir trades)
            double tp = NormalizeDouble(ask + dynTp * point, digits);
            if(OpenOriginalTrade(ORDER_TYPE_BUY, ask, tp, dynTp, closedBarTime))
               Print("BUY opened. Entry: ", ask, " TP: ", tp, " DynTpPts: ", dynTp,
                     " MA: ", maOnPrev, " PrevClose: ", prevClose);
         }
         else if(EnableScaleIn)
         {
            //--- Scale-in into existing BUY trades
            TryScaleIn(1, ask, dynTp, closedBarTime, maOnPrev, prevClose);
         }
      }
   }

   if(sellSignal)
   {
      if(!OneTradePerBar || g_lastSellBar != closedBarTime)
      {
         g_lastSellBar = closedBarTime;
         double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         int    openSells = CountOpenEATradesInDir(-1);

         if(openSells == 0)
         {
            //--- Fresh SELL entry (no existing same-dir trades)
            double tp = NormalizeDouble(bid - dynTp * point, digits);
            if(OpenOriginalTrade(ORDER_TYPE_SELL, bid, tp, dynTp, closedBarTime))
               Print("SELL opened. Entry: ", bid, " TP: ", tp, " DynTpPts: ", dynTp,
                     " MA: ", maOnPrev, " PrevClose: ", prevClose);
         }
         else if(EnableScaleIn)
         {
            //--- Scale-in into existing SELL trades
            TryScaleIn(-1, bid, dynTp, closedBarTime, maOnPrev, prevClose);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open an original trade and add to tracking                       |
//+------------------------------------------------------------------+
bool OpenOriginalTrade(ENUM_ORDER_TYPE type, double price, double tp,
                       double tpPts, datetime barTime)
{
   string comment = TradeComment + "_" + TAG_ORIG;
   bool ok = false;

   if(type == ORDER_TYPE_BUY)
      ok = trade.Buy(BaseLotSize, _Symbol, price, 0, tp, comment);
   else
      ok = trade.Sell(BaseLotSize, _Symbol, price, 0, tp, comment);

   if(!ok)
   {
      Print("OpenOriginalTrade failed: ", trade.ResultRetcode(),
            " – ", trade.ResultRetcodeDescription());
      return false;
   }

   ulong posTicket = GetPositionTicketByOrder(trade.ResultOrder());

   TradeRec rec;
   rec.ticket        = posTicket;
   rec.direction     = (type == ORDER_TYPE_BUY) ? 1 : -1;
   rec.entryPrice    = price;
   rec.tpPoints      = tpPts;
   rec.baseLot       = BaseLotSize;
   rec.hedged        = false;
   rec.hedgeTicket   = 0;
   rec.barTime       = barTime;
   rec.isReversal    = false;
   rec.isScaleIn     = false;
   rec.earlyProtected = false;

   int sz = ArraySize(g_trades);
   ArrayResize(g_trades, sz + 1);
   g_trades[sz] = rec;
   return true;
}

//+------------------------------------------------------------------+
//| Count open EA trades on this symbol in a given direction         |
//| dir: 1=BUY, -1=SELL                                              |
//+------------------------------------------------------------------+
int CountOpenEATradesInDir(int dir)
{
   int count = 0;
   int sz    = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir) continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Attempt a scale-in trade in direction dir at execPrice           |
//| Volume is sized so its TP profit covers current floating loss    |
//+------------------------------------------------------------------+
void TryScaleIn(int dir, double execPrice, double dynTp,
                datetime barTime, double maVal, double prevClose)
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   //--- Find the entry nearest to current price among open same-dir positions
   double nearestEntry = -1.0;
   double minDist      = DBL_MAX;
   int sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir)                continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;
      double dist = MathAbs(g_trades[i].entryPrice - execPrice);
      if(dist < minDist) { minDist = dist; nearestEntry = g_trades[i].entryPrice; }
   }

   if(nearestEntry < 0.0) return;

   //--- Gate: price must be at least MinProfitPoints adverse from nearest entry
   bool condOk = false;
   if(dir == 1)   condOk = (execPrice <= nearestEntry - MinProfitPoints * point);
   else            condOk = (execPrice >= nearestEntry + MinProfitPoints * point);

   if(!condOk)
   {
      Print("ScaleIn skipped: gap ", minDist / point, " pts < MinProfitPoints ",
            MinProfitPoints, " from nearest entry ", nearestEntry);
      return;
   }

   //--- Sum current floating loss of all open same-dir EA trades
   double floatingLoss = 0.0;
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir)                continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;
      floatingLoss += PositionGetDouble(POSITION_PROFIT);
   }

   //--- Volume so that: newVol * dynTp * ptValPerLot >= |floatingLoss| + BaseLot profit
   double tickVal     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double ptValPerLot = (tickSz > 0.0 && tickVal > 0.0)
                        ? tickVal / tickSz * point
                        : 0.0;

   double rawVol = BaseLotSize;
   if(ptValPerLot > 0.0 && floatingLoss < 0.0)
      rawVol = MathAbs(floatingLoss) / (dynTp * ptValPerLot) + BaseLotSize;

   if(rawVol > MaxLotSize)
   {
      Print("ScaleIn STOPPED: required lot ", rawVol,
            " exceeds MaxLotSize ", MaxLotSize);
      return;
   }

   double adjVol = NormalizeVolume(MathMax(rawVol, BaseLotSize));

   //--- Place the scale-in order
   double tp = (dir == 1)
               ? NormalizeDouble(execPrice + dynTp * point, digits)
               : NormalizeDouble(execPrice - dynTp * point, digits);

   string comment = TradeComment + "_" + TAG_AVG;
   bool   ok      = (dir == 1)
                    ? trade.Buy (adjVol, _Symbol, execPrice, 0, tp, comment)
                    : trade.Sell(adjVol, _Symbol, execPrice, 0, tp, comment);

   if(!ok)
   {
      Print("ScaleIn order failed: ", trade.ResultRetcode(),
            " – ", trade.ResultRetcodeDescription());
      return;
   }

   ulong posTicket = GetPositionTicketByOrder(trade.ResultOrder());

   TradeRec rec;
   rec.ticket         = posTicket;
   rec.direction      = dir;
   rec.entryPrice     = execPrice;
   rec.tpPoints       = dynTp;
   rec.baseLot        = BaseLotSize;
   rec.hedged         = false;
   rec.hedgeTicket    = 0;
   rec.barTime        = barTime;
   rec.isReversal     = false;
   rec.isScaleIn      = true;
   rec.earlyProtected = false;

   int cnt = ArraySize(g_trades);
   ArrayResize(g_trades, cnt + 1);
   g_trades[cnt] = rec;

   Print("ScaleIn ", (dir==1?"BUY":"SELL"), " opened. Ticket: ", posTicket,
         "  Entry: ", execPrice, "  TP: ", tp, "  Lot: ", adjVol,
         "  FloatLoss: ", floatingLoss,
         "  NearestEntry: ", nearestEntry,
         "  MA: ", maVal, "  PrevClose: ", prevClose);
}

//+------------------------------------------------------------------+
//| On bar change: close any EA trade that has positive P&L          |
//+------------------------------------------------------------------+
void CloseAllProfitableTrades()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t))                              continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)       continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)           continue;

      double profit = PositionGetDouble(POSITION_PROFIT)
                    + PositionGetDouble(POSITION_SWAP);
      if(profit > 0.0)
      {
         if(!trade.PositionClose(t, Slippage))
            Print("EarlyClose failed for ticket ", t, ": ", trade.ResultRetcode());
         else
            Print("EarlyClose: ticket ", t, " closed with profit ", profit);
      }
   }
}

//+------------------------------------------------------------------+
//| Close ALL open EA positions (used by weekend filter & breaker)   |
//+------------------------------------------------------------------+
void CloseAllEATrades()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t))                              continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)       continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)           continue;

      if(!trade.PositionClose(t, Slippage))
         Print("CloseAllEA failed for ticket ", t, ": ", trade.ResultRetcode());
   }
   ArrayResize(g_trades, 0);
}

//+------------------------------------------------------------------+
//| Per-tick: move SL to min-profit once price reaches EarlyTpPct%  |
//+------------------------------------------------------------------+
void CheckEarlyProtection()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   int sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].earlyProtected)    continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;

      double entry     = g_trades[i].entryPrice;
      int    dir       = g_trades[i].direction;
      double tpPts     = g_trades[i].tpPoints;
      double threshold = tpPts * EarlyTpPct / 100.0;  // in points

      bool triggered = false;
      if(dir == 1)   // BUY: price moved up at least threshold points
         triggered = (bid >= entry + threshold * point);
      else           // SELL: price moved down at least threshold points
         triggered = (ask <= entry - threshold * point);

      if(!triggered) continue;

      //--- Move SL to entry + MinProfitPoints (locks at least MinProfitPoints)
      double newSL = 0.0;
      if(dir == 1)
         newSL = NormalizeDouble(entry + MinProfitPoints * point, digits);
      else
         newSL = NormalizeDouble(entry - MinProfitPoints * point, digits);

      double existingTP = PositionGetDouble(POSITION_TP);

      if(!trade.PositionModify(g_trades[i].ticket, newSL, existingTP))
         Print("EarlyProtect: Modify SL failed for ticket ", g_trades[i].ticket,
               ": ", trade.ResultRetcode());
      else
      {
         g_trades[i].earlyProtected = true;
         Print("EarlyProtect: SL moved to ", newSL,
               " for ticket ", g_trades[i].ticket,
               " (entry ", entry, " dir ", dir, ")");
      }
   }
}

//+------------------------------------------------------------------+
//| Check reversal thresholds on every tick                          |
//+------------------------------------------------------------------+
void CheckReversalTriggers()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   int sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].hedged) continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;

      double entry = g_trades[i].entryPrice;
      int    dir   = g_trades[i].direction;

      bool touched = false;
      if(dir == 1)   touched = (bid <= entry - ReversePoints * point); // BUY gone against
      else            touched = (ask >= entry + ReversePoints * point); // SELL gone against

      if(!touched) continue;

      Print("Reversal triggered for ticket ", g_trades[i].ticket,
            "  Entry: ", entry, "  Dir: ", dir,
            "  RevPts: ", ReversePoints);

      OpenReversalNow(i, point, bid, ask);

      sz = ArraySize(g_trades);   // refresh after possible resize
   }
}

//+------------------------------------------------------------------+
//| Open hedging reversal and adjust existing positions              |
//+------------------------------------------------------------------+
void OpenReversalNow(int origIdx, double point, double bid, double ask)
{
   int    dir    = g_trades[origIdx].direction;
   double tp_pts = g_trades[origIdx].tpPoints;

   double revEntry, revTP;
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(dir == 1)   // BUY triggered → hedge SELL
   {
      revEntry = bid;
      revTP    = NormalizeDouble(revEntry - tp_pts * point, digits);
   }
   else           // SELL triggered → hedge BUY
   {
      revEntry = ask;
      revTP    = NormalizeDouble(revEntry + tp_pts * point, digits);
   }

   //--- Sum lots on both sides across all tracked positions
   double totalLosingLot  = 0.0;
   double totalWinningLot = 0.0;
   int sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(g_trades[i].direction == dir)   totalLosingLot  += vol;
      else                                totalWinningLot += vol;
   }

   //--- Hedge lot formula: cover losses + target BaseLotSize profit
   double rawHedgeLot = totalLosingLot * (tp_pts + ReversePoints) / tp_pts
                        + BaseLotSize - totalWinningLot;

   if(rawHedgeLot > MaxLotSize)
   {
      Print("HEDGING STOPPED: required lot ", rawHedgeLot,
            " exceeds MaxLotSize ", MaxLotSize, ". Positions float to TP/SL.");
      return;
   }

   double adjHedgeLot = NormalizeVolume(MathMax(rawHedgeLot, BaseLotSize));

   string revComment = TradeComment + "_" + TAG_REV;
   bool   okRev      = false;
   if(dir == 1)
      okRev = trade.Sell(adjHedgeLot, _Symbol, revEntry, 0, revTP, revComment);
   else
      okRev = trade.Buy (adjHedgeLot, _Symbol, revEntry, 0, revTP, revComment);

   if(!okRev)
   {
      Print("Reversal order failed: ", trade.ResultRetcode(),
            " – ", trade.ResultRetcodeDescription());
      return;
   }

   ulong revTicket = GetPositionTicketByOrder(trade.ResultOrder());
   Print("Reversal opened. Ticket: ", revTicket,
         "  Entry: ", revEntry, "  TP: ", revTP,
         "  Lot: ", adjHedgeLot,
         "  LosingLot: ", totalLosingLot, "  WinningLot: ", totalWinningLot);

   //--- Move SL of all losing-side positions to hedge TP; mark hedged
   sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir) continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;

      double existingTP = PositionGetDouble(POSITION_TP);
      if(!trade.PositionModify(g_trades[i].ticket, revTP, existingTP))
         Print("Modify SL failed for ticket ", g_trades[i].ticket,
               ": ", trade.ResultRetcode());
      else
         Print("SL moved to ", revTP, " for ticket ", g_trades[i].ticket);

      g_trades[i].hedged      = true;
      g_trades[i].hedgeTicket = revTicket;
   }

   //--- Add new hedge to tracking (unhedged so it can trigger next level)
   TradeRec revRec;
   revRec.ticket         = revTicket;
   revRec.direction      = -dir;
   revRec.entryPrice     = revEntry;
   revRec.tpPoints       = tp_pts;
   revRec.baseLot        = BaseLotSize;
   revRec.hedged         = false;
   revRec.hedgeTicket    = 0;
   revRec.barTime        = g_trades[origIdx].barTime;
   revRec.isReversal     = true;
   revRec.isScaleIn      = false;
   revRec.earlyProtected = false;

   sz = ArraySize(g_trades);
   ArrayResize(g_trades, sz + 1);
   g_trades[sz] = revRec;
}

//+------------------------------------------------------------------+
//| Rebuild g_trades from currently open positions after EA restart  |
//+------------------------------------------------------------------+
void RebuildFromOpenPositions()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t))                         continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)  continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)      continue;

      ENUM_POSITION_TYPE posType =
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double posTp = PositionGetDouble(POSITION_TP);
      double sl    = PositionGetDouble(POSITION_SL);
      string comm  = PositionGetString(POSITION_COMMENT);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      //--- Derive stored direction
      int dir = (posType == POSITION_TYPE_BUY) ? 1 : -1;

      //--- Derive tpPoints from position TP (fallback to TpMinPoints)
      double tpPts = TpMinPoints;
      if(posTp > 0 && point > 0)
         tpPts = MathAbs(posTp - entry) / point;
      if(tpPts < 1.0) tpPts = TpMinPoints;

      //--- Determine entry type from comment
      bool isRev = StringFind(comm, TAG_REV) >= 0;
      bool isSci = StringFind(comm, TAG_AVG) >= 0;

      //--- If SL is already set, assume it was already hedged
      bool wasHedged = (sl > 0);

      TradeRec rec;
      rec.ticket         = t;
      rec.direction      = dir;
      rec.entryPrice     = entry;
      rec.tpPoints       = tpPts;
      rec.baseLot        = BaseLotSize;
      rec.hedged         = wasHedged;
      rec.hedgeTicket    = 0;   // not recoverable; OK as hedge re-triggers if needed
      rec.barTime        = (datetime)PositionGetInteger(POSITION_TIME);
      rec.isReversal     = isRev;
      rec.isScaleIn      = isSci;
      rec.earlyProtected = wasHedged; // if already hedged treat as protected too

      int sz = ArraySize(g_trades);
      ArrayResize(g_trades, sz + 1);
      g_trades[sz] = rec;

      Print("Recovery: ticket ", t, "  dir ", dir, "  tpPts ", tpPts,
            "  hedged ", wasHedged, "  isRev ", isRev);
   }
}

//+------------------------------------------------------------------+
//| Close all EA positions + start cooloff if loss limit exceeded    |
//+------------------------------------------------------------------+
void CheckMaxLossBreaker()
{
   if(MaxTotalOpenLoss <= 0.0) return;

   double totalFloatingPL = 0.0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t))                              continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)       continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)           continue;
      totalFloatingPL += PositionGetDouble(POSITION_PROFIT);
   }

   if(totalFloatingPL >= -(MaxTotalOpenLoss)) return;

   Print("MAX LOSS BREAKER: floating P&L ", totalFloatingPL,
         " exceeded limit -", MaxTotalOpenLoss, ". Closing all.");

   CloseAllEATrades();
   g_cooloffBarsLeft = CooloffBars;
   Print("Cooloff started: entries blocked for ", CooloffBars, " bars.");
}

//+------------------------------------------------------------------+
//| Returns true if current trading hour is enabled                  |
//+------------------------------------------------------------------+
bool IsTradingHourAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   switch(dt.hour)
   {
      case  0: return H00; case  1: return H01; case  2: return H02;
      case  3: return H03; case  4: return H04; case  5: return H05;
      case  6: return H06; case  7: return H07; case  8: return H08;
      case  9: return H09; case 10: return H10; case 11: return H11;
      case 12: return H12; case 13: return H13; case 14: return H14;
      case 15: return H15; case 16: return H16; case 17: return H17;
      case 18: return H18; case 19: return H19; case 20: return H20;
      case 21: return H21; case 22: return H22; case 23: return H23;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Returns true if, barsAhead bars from now, we are >= weekend      |
//| Weekend = Friday >= WeekendCloseHour, Saturday, or Sunday        |
//+------------------------------------------------------------------+
bool IsNearWeekend(int barsAhead)
{
   if(barsAhead <= 0) return false;
   int periodSec = PeriodSeconds(_Period);
   datetime checkTime = TimeCurrent() + barsAhead * periodSec;

   MqlDateTime dt;
   TimeToStruct(checkTime, dt);

   if(dt.day_of_week == 6) return true;   // Saturday
   if(dt.day_of_week == 0) return true;   // Sunday
   if(dt.day_of_week == 5 && dt.hour >= WeekendCloseHour) return true; // Friday end
   return false;
}

//+------------------------------------------------------------------+
//| Count open EA positions on this symbol                           |
//+------------------------------------------------------------------+
int CountOpenEATrades()
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Remove tracking records for closed positions                     |
//+------------------------------------------------------------------+
void PruneClosedTrades()
{
   for(int i = ArraySize(g_trades) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(g_trades[i].ticket))
         ArrayRemove(g_trades, i, 1);
   }
}

//+------------------------------------------------------------------+
//| Resolve position ticket from order ticket (hedge / netting safe) |
//+------------------------------------------------------------------+
ulong GetPositionTicketByOrder(ulong orderTicket)
{
   if(PositionSelectByTicket(orderTicket))
      return orderTicket;

   ulong best = 0;
   int total  = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;

      bool known = false;
      for(int j = 0; j < ArraySize(g_trades); j++)
         if(g_trades[j].ticket == t) { known = true; break; }
      if(known) continue;

      if(t > best) best = t;
   }
   return (best > 0) ? best : orderTicket;
}

//+------------------------------------------------------------------+
//| Normalize volume to symbol step / min / max constraints          |
//+------------------------------------------------------------------+
double NormalizeVolume(double vol)
{
   double minVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   vol = MathRound(vol / volStep) * volStep;
   vol = MathMax(vol, minVol);
   vol = MathMin(vol, MathMin(maxVol, MaxLotSize));
   return NormalizeDouble(vol, 2);
}
//+------------------------------------------------------------------+
