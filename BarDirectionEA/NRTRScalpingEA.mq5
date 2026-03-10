//+------------------------------------------------------------------+
//|                                           NRTRScalpingEA.mq5    |
//|                                  Copyright 2026, Cris Trading   |
//|                                                                  |
//|  Strategy (NRTR – Nick Rypock Trailing Ratchet):                |
//|  1. NRTR computed internally (ATR-based sensitivity)             |
//|     Uptrend:   ratchet = HH - K * ATR  (HH ratchets up)         |
//|     Downtrend: ratchet = LL + K * ATR  (LL ratchets down)       |
//|     Flip: BUY when uptrend starts, SELL when downtrend starts    |
//|  2. Entry on confirmed bar-close NRTR flip                       |
//|  3. SL placed at ratchet level at entry                          |
//|  4. Dynamic TP = max(max H-L over DynTpBars, TpMinPoints)        |
//|  5. Reversal hedge on opposite NRTR flip (MA-cross style)        |
//|     Lot sized to cover weighted floating loss at new TP          |
//|  6. Scale-in: same-dir flip when price is >= MinProfitPoints     |
//|     adverse from nearest entry; lot covers floating loss         |
//|  7. Early close: close profitable trades on bar change           |
//|  8. Early protection: lock SL to min-profit when near TP         |
//|  9. EA restart recovery: rebuild state from open positions       |
//| 10. Weekend filter: inhibit / close N bars before weekend        |
//| 11. Max loss breaker + cooloff bars                              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Cris Trading"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs ---------------------------------------------------------
input group "=== NRTR Settings ==="
input int    NRTR_ATRPeriod  = 14;    // ATR period for ratchet sensitivity
input double NRTR_K          = 2.0;   // Ratchet = Extreme ± K * ATR
input int    NRTR_Lookback   = 200;   // History bars to initialize NRTR state

input group "=== Trade Settings ==="
input double BaseLotSize     = 0.01;  // Base lot size
input double TpMinPoints     = 200.0; // Minimum TP (points) – floor for dynamic TP
input long   MagicNumber     = 88881; // Magic number
input int    Slippage        = 50;    // Slippage in points
input string TradeComment    = "NRTR";// Comment prefix

input group "=== Dynamic TP ==="
input int    DynTpBars       = 10;    // Lookback bars for dynamic TP
//   TP = max( max(High-Low) over DynTpBars bars, TpMinPoints )  [in points]

input group "=== Early Close & Protection ==="
input bool   EnableEarlyClose      = true;  // Close profitable trades on bar change
input bool   EnableEarlyProtection = true;  // Move SL to lock min profit when near TP
input bool   EnableScaleIn         = true;  // Scale-in on same-dir NRTR flip
input double EarlyTpPct      = 50.0;  // SL-lock activates at X% of TP distance
input double MinProfitPoints = 20.0;  // Protective SL offset / scale-in gap (points)

input group "=== Risk Settings ==="
input double MaxLotSize       = 50.0; // Max lot size cap
input double MaxTotalOpenLoss = 0.0;  // Max floating loss in account currency (0=off)
input int    CooloffBars      = 2;    // Cooloff bars after loss-breaker fires
input bool   OneTradePerBar   = true; // Only one entry per direction per bar

input group "=== Weekend Filter (server time) ==="
input int  WeekendInhibitBars = 3;    // Bars before weekend: block new entries (0=off)
input int  WeekendCloseBars   = 1;    // Bars before weekend: close all trades  (0=off)
input int  WeekendCloseHour   = 22;   // Friday hour considered session-end

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

//--- NRTR state
struct NRTRState
{
   int    direction;  // 1 = uptrend, -1 = downtrend
   double level;      // ratchet level (acts as trailing stop)
   double extreme;    // highest high (up) or lowest low (down) since last flip
};

//--- Trade record
struct TradeRec
{
   ulong    ticket;
   int      direction;       // 1=BUY, -1=SELL
   double   entryPrice;
   double   tpPoints;        // TP distance in points used at entry
   double   baseLot;
   bool     hedged;          // reversal already fired?
   ulong    hedgeTicket;
   datetime barTime;
   bool     isReversal;
   bool     isScaleIn;
   bool     earlyProtected;  // SL already locked to min-profit?
};

TradeRec g_trades[];

//--- State
datetime g_lastBarTime     = 0;
datetime g_lastBuyBar      = 0;
datetime g_lastSellBar     = 0;
int      g_cooloffBarsLeft = 0;

CTrade trade;

//+------------------------------------------------------------------+
//| Compute ATR (Wilder) at barIdx using NRTR_ATRPeriod bars         |
//| barIdx 0 = current forming bar, 1 = last closed, etc.           |
//+------------------------------------------------------------------+
double CalcATR(int barIdx)
{
   double sum = 0.0;
   int    per = NRTR_ATRPeriod;

   for(int i = barIdx; i < barIdx + per; i++)
   {
      double hi   = iHigh (_Symbol, _Period, i);
      double lo   = iLow  (_Symbol, _Period, i);
      double prvc = iClose(_Symbol, _Period, i + 1);
      if(hi <= 0 || lo <= 0 || prvc <= 0) continue;

      double tr = MathMax(hi - lo,
                  MathMax(MathAbs(hi - prvc), MathAbs(lo - prvc)));
      sum += tr;
   }
   return sum / per;
}

//+------------------------------------------------------------------+
//| Run the NRTR state machine from NRTR_Lookback bars back          |
//| to barIdx and return the state AT barIdx                         |
//+------------------------------------------------------------------+
NRTRState CalcNRTRAtBar(int barIdx)
{
   int startBar = barIdx + NRTR_Lookback - 1;

   //--- Seed with state at the oldest bar (assume uptrend start)
   NRTRState s;
   s.direction = 1;
   double initClose = iClose(_Symbol, _Period, startBar);
   double initATR   = CalcATR(startBar);
   s.extreme = initClose;
   s.level   = initClose - NRTR_K * initATR;

   //--- Walk forward bar by bar from startBar-1 down to barIdx
   for(int b = startBar - 1; b >= barIdx; b--)
   {
      double cl  = iClose(_Symbol, _Period, b);
      double atr = CalcATR(b);
      double ratchetDist = NRTR_K * atr;

      if(s.direction == 1)   // uptrend
      {
         if(cl > s.extreme) { s.extreme = cl; }
         double newLevel = s.extreme - ratchetDist;
         if(newLevel > s.level) s.level = newLevel;   // ratchet only up

         if(cl < s.level)   // flip to downtrend
         {
            s.direction = -1;
            s.extreme   = cl;
            s.level     = cl + ratchetDist;
         }
      }
      else                   // downtrend
      {
         if(cl < s.extreme) { s.extreme = cl; }
         double newLevel = s.extreme + ratchetDist;
         if(newLevel < s.level) s.level = newLevel;   // ratchet only down

         if(cl > s.level)   // flip to uptrend
         {
            s.direction = 1;
            s.extreme   = cl;
            s.level     = cl - ratchetDist;
         }
      }
   }

   return s;
}

//+------------------------------------------------------------------+
//| Dynamic TP: max H-L range over DynTpBars, floored at TpMinPoints|
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

   ArrayResize(g_trades, 0);
   RebuildFromOpenPositions();

   Print("NRTRScalpingEA initialized.  Symbol: ", _Symbol,
         "  TF: ", EnumToString(_Period),
         "  ATR(", NRTR_ATRPeriod, ")  K=", NRTR_K,
         "  TpMinPoints: ", TpMinPoints,
         "  Recovered: ", ArraySize(g_trades), " positions");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ArrayFree(g_trades);
}

//+------------------------------------------------------------------+
//| Expert tick                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 1. Max loss breaker
   CheckMaxLossBreaker();

   //--- 2. Early protection (per tick)
   if(EnableEarlyProtection)
      CheckEarlyProtection();

   //--- 3. New-bar logic
   datetime barTimes[];
   if(CopyTime(_Symbol, _Period, 0, 2, barTimes) < 2) return;

   datetime currentBarTime = barTimes[1];

   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;

      //--- 3a. Weekend close filter
      if(WeekendCloseBars > 0 && IsNearWeekend(WeekendCloseBars))
      {
         Print("Weekend close filter: closing all EA trades.");
         CloseAllEATrades();
      }
      else
      {
         //--- 3b. Early bar-close: close profitable trades
         if(EnableEarlyClose)
            CloseAllProfitableTrades();
      }

      //--- 3c. Cooloff countdown
      if(g_cooloffBarsLeft > 0)
      {
         g_cooloffBarsLeft--;
         Print("Cooloff active: ", g_cooloffBarsLeft, " bar(s) remaining.");
      }
      else
      {
         if(WeekendInhibitBars > 0 && IsNearWeekend(WeekendInhibitBars))
         {
            Print("Weekend inhibit filter: skipping new entry.");
         }
         else if(IsTradingHourAllowed())
         {
            OnNewBar(currentBarTime);
         }
         else
         {
            MqlDateTime _dt; TimeToStruct(TimeCurrent(), _dt);
            Print("New bar skipped – outside trading hours (H", _dt.hour, ")");
         }
      }
   }

   //--- 4. Prune closed position records
   PruneClosedTrades();
}

//+------------------------------------------------------------------+
//| Called once per new closed bar                                   |
//+------------------------------------------------------------------+
void OnNewBar(datetime closedBarTime)
{
   //--- Get NRTR state on bar[1] (just closed) and bar[2] (previous)
   NRTRState s1 = CalcNRTRAtBar(1);   // just-closed bar
   NRTRState s2 = CalcNRTRAtBar(2);   // bar before that

   bool flipUp   = (s1.direction ==  1 && s2.direction == -1);  // downtrend → uptrend
   bool flipDown = (s1.direction == -1 && s2.direction ==  1);  // uptrend → downtrend

   //--- NRTR-cross reversal: check before new entries
   CheckNRTRReversal(s1.direction, s1.level);

   double dynTp  = CalcDynamicTP();
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   //--- BUY entry: NRTR just flipped up
   if(flipUp)
   {
      if(!OneTradePerBar || g_lastBuyBar != closedBarTime)
      {
         g_lastBuyBar = closedBarTime;
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         int    openBuys = CountOpenEATradesInDir(1);

         if(openBuys == 0)
         {
            double tp = NormalizeDouble(ask + dynTp * point, digits);
            double sl = NormalizeDouble(s1.level, digits);   // ratchet = natural SL
            if(OpenTrade(ORDER_TYPE_BUY, ask, sl, tp, dynTp, closedBarTime, TAG_ORIG))
               Print("NRTR BUY entered. Entry:", ask, " SL:", sl, " TP:", tp,
                     " RatchetLevel:", s1.level, " DynTpPts:", dynTp);
         }
         else if(EnableScaleIn)
         {
            TryScaleIn(1, ask, dynTp, s1.level, closedBarTime);
         }
      }
   }

   //--- SELL entry: NRTR just flipped down
   if(flipDown)
   {
      if(!OneTradePerBar || g_lastSellBar != closedBarTime)
      {
         g_lastSellBar = closedBarTime;
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         int    openSells = CountOpenEATradesInDir(-1);

         if(openSells == 0)
         {
            double tp = NormalizeDouble(bid - dynTp * point, digits);
            double sl = NormalizeDouble(s1.level, digits);
            if(OpenTrade(ORDER_TYPE_SELL, bid, sl, tp, dynTp, closedBarTime, TAG_ORIG))
               Print("NRTR SELL entered. Entry:", bid, " SL:", sl, " TP:", tp,
                     " RatchetLevel:", s1.level, " DynTpPts:", dynTp);
         }
         else if(EnableScaleIn)
         {
            TryScaleIn(-1, bid, dynTp, s1.level, closedBarTime);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| NRTR reversal: when NRTR direction conflicts with open positions |
//|  NRTR uptrend  → reverse any open unhedged SELL trades          |
//|  NRTR downtrend→ reverse any open unhedged BUY  trades          |
//+------------------------------------------------------------------+
void CheckNRTRReversal(int nrtrDir, double ratchetLevel)
{
   //--- Positions whose direction is OPPOSITE to current NRTR should be reversed
   int conflictDir = -nrtrDir;   // e.g. nrtr=up(1) → conflict=SELL(-1)

   if(CountOpenEATradesInDir_Unhedged(conflictDir) == 0) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   Print("NRTR reversal: current direction ", nrtrDir,
         " conflicts with open ", (conflictDir == 1 ? "BUY" : "SELL"),
         " trades. Reversing.");

   OpenReversalNow(conflictDir, point, bid, ask);
}

//+------------------------------------------------------------------+
//| Open a trade (original, scale-in, or reversal) with full SL/TP  |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp,
               double tpPts, datetime barTime, string tag)
{
   string comment = TradeComment + "_" + tag;
   bool ok = (type == ORDER_TYPE_BUY)
             ? trade.Buy (BaseLotSize, _Symbol, price, sl, tp, comment)
             : trade.Sell(BaseLotSize, _Symbol, price, sl, tp, comment);

   if(!ok)
   {
      Print("OpenTrade failed (", tag, "): ", trade.ResultRetcode(),
            " – ", trade.ResultRetcodeDescription());
      return false;
   }

   ulong posTicket = GetPositionTicketByOrder(trade.ResultOrder());

   TradeRec rec;
   rec.ticket         = posTicket;
   rec.direction      = (type == ORDER_TYPE_BUY) ? 1 : -1;
   rec.entryPrice     = price;
   rec.tpPoints       = tpPts;
   rec.baseLot        = BaseLotSize;
   rec.hedged         = false;
   rec.hedgeTicket    = 0;
   rec.barTime        = barTime;
   rec.isReversal     = (tag == TAG_REV);
   rec.isScaleIn      = (tag == TAG_AVG);
   rec.earlyProtected = false;

   int sz = ArraySize(g_trades);
   ArrayResize(g_trades, sz + 1);
   g_trades[sz] = rec;
   return true;
}

//+------------------------------------------------------------------+
//| Scale-in into existing same-direction trades                     |
//+------------------------------------------------------------------+
void TryScaleIn(int dir, double execPrice, double dynTp,
                double ratchetLevel, datetime barTime)
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   //--- Find nearest same-dir entry
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
   bool condOk = (dir == 1) ? (execPrice <= nearestEntry - MinProfitPoints * point)
                             : (execPrice >= nearestEntry + MinProfitPoints * point);
   if(!condOk)
   {
      Print("ScaleIn skipped: gap ", minDist / point,
            " pts < MinProfitPoints ", MinProfitPoints);
      return;
   }

   //--- Floating loss of all open same-dir trades
   double floatingLoss = 0.0;
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir)                continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;
      floatingLoss += PositionGetDouble(POSITION_PROFIT);
   }

   //--- Volume to cover loss at dynTp
   double tickVal     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double ptValPerLot = (tickSz > 0.0 && tickVal > 0.0)
                        ? tickVal / tickSz * point : 0.0;

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

   double tp = (dir == 1)
               ? NormalizeDouble(execPrice + dynTp * point, digits)
               : NormalizeDouble(execPrice - dynTp * point, digits);
   double sl = NormalizeDouble(ratchetLevel, digits);

   string comment = TradeComment + "_" + TAG_AVG;
   bool ok = (dir == 1)
             ? trade.Buy (adjVol, _Symbol, execPrice, sl, tp, comment)
             : trade.Sell(adjVol, _Symbol, execPrice, sl, tp, comment);

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

   Print("ScaleIn ", (dir == 1 ? "BUY" : "SELL"),
         " Ticket:", posTicket, " Entry:", execPrice,
         " SL:", sl, " TP:", tp, " Lot:", adjVol,
         " FloatLoss:", floatingLoss, " NearestEntry:", nearestEntry);
}

//+------------------------------------------------------------------+
//| Open hedging reversal; lot sized from actual per-trade distances |
//| dir: direction of LOSING (conflicting) positions                  |
//+------------------------------------------------------------------+
void OpenReversalNow(int dir, double point, double bid, double ask)
{
   double tp_pts = CalcDynamicTP();
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double revEntry, revTP;
   if(dir == 1)   // reversing BUYs → open SELL hedge
   {
      revEntry = bid;
      revTP    = NormalizeDouble(revEntry - tp_pts * point, digits);
   }
   else           // reversing SELLs → open BUY hedge
   {
      revEntry = ask;
      revTP    = NormalizeDouble(revEntry + tp_pts * point, digits);
   }

   //--- Weighted lot: each losing trade contributes vol*(tp+dist)/tp
   double weightedLosing  = 0.0;
   double totalWinningLot = 0.0;
   int sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(g_trades[i].direction == dir)
      {
         double dist = MathAbs(g_trades[i].entryPrice - revEntry) / point;
         weightedLosing += vol * (tp_pts + dist) / tp_pts;
      }
      else
         totalWinningLot += vol;
   }

   double rawHedgeLot = weightedLosing + BaseLotSize - totalWinningLot;

   if(rawHedgeLot > MaxLotSize)
   {
      Print("HEDGING STOPPED: required lot ", rawHedgeLot,
            " > MaxLotSize ", MaxLotSize, ". Positions float to TP/SL.");
      return;
   }

   double adjHedgeLot = NormalizeVolume(MathMax(rawHedgeLot, BaseLotSize));

   string revComment = TradeComment + "_" + TAG_REV;
   bool   okRev = (dir == 1)
                  ? trade.Sell(adjHedgeLot, _Symbol, revEntry, 0, revTP, revComment)
                  : trade.Buy (adjHedgeLot, _Symbol, revEntry, 0, revTP, revComment);

   if(!okRev)
   {
      Print("Reversal order failed: ", trade.ResultRetcode(),
            " – ", trade.ResultRetcodeDescription());
      return;
   }

   ulong revTicket = GetPositionTicketByOrder(trade.ResultOrder());
   Print("Reversal opened. Ticket:", revTicket,
         " Entry:", revEntry, " TP:", revTP,
         " Lot:", adjHedgeLot,
         " WeightedLosing:", weightedLosing,
         " WinningLot:", totalWinningLot);

   //--- Move SL of all conflicting positions to hedge TP; mark hedged
   sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir) continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;

      double existingTP = PositionGetDouble(POSITION_TP);
      if(!trade.PositionModify(g_trades[i].ticket, revTP, existingTP))
         Print("Modify SL failed ticket ", g_trades[i].ticket,
               ": ", trade.ResultRetcode());
      else
         Print("SL moved to ", revTP, " for ticket ", g_trades[i].ticket);

      g_trades[i].hedged      = true;
      g_trades[i].hedgeTicket = revTicket;
   }

   //--- Track the new hedge (starts unhedged so it can trigger next level)
   TradeRec revRec;
   revRec.ticket         = revTicket;
   revRec.direction      = -dir;
   revRec.entryPrice     = revEntry;
   revRec.tpPoints       = tp_pts;
   revRec.baseLot        = BaseLotSize;
   revRec.hedged         = false;
   revRec.hedgeTicket    = 0;
   revRec.barTime        = TimeCurrent();
   revRec.isReversal     = true;
   revRec.isScaleIn      = false;
   revRec.earlyProtected = false;

   sz = ArraySize(g_trades);
   ArrayResize(g_trades, sz + 1);
   g_trades[sz] = revRec;
}

//+------------------------------------------------------------------+
//| Early close: close EA trades with positive P&L on bar change     |
//+------------------------------------------------------------------+
void CloseAllProfitableTrades()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t))                        continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;

      double profit = PositionGetDouble(POSITION_PROFIT)
                    + PositionGetDouble(POSITION_SWAP);
      if(profit > 0.0)
      {
         if(!trade.PositionClose(t, Slippage))
            Print("EarlyClose failed ticket ", t, ": ", trade.ResultRetcode());
         else
            Print("EarlyClose: ticket ", t, " profit ", profit);
      }
   }
}

//+------------------------------------------------------------------+
//| Close ALL open EA positions                                       |
//+------------------------------------------------------------------+
void CloseAllEATrades()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t))                        continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;

      if(!trade.PositionClose(t, Slippage))
         Print("CloseAll failed ticket ", t, ": ", trade.ResultRetcode());
   }
   ArrayResize(g_trades, 0);
}

//+------------------------------------------------------------------+
//| Per-tick: lock in min profit once price reaches EarlyTpPct% TP  |
//+------------------------------------------------------------------+
void CheckEarlyProtection()
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   int sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].earlyProtected)                      continue;
      if(!PositionSelectByTicket(g_trades[i].ticket))     continue;

      double entry    = g_trades[i].entryPrice;
      int    dir      = g_trades[i].direction;
      double tpPts    = g_trades[i].tpPoints;
      double threshold = tpPts * EarlyTpPct / 100.0;

      bool triggered = (dir == 1) ? (bid >= entry + threshold * point)
                                  : (ask <= entry - threshold * point);
      if(!triggered) continue;

      double newSL = (dir == 1)
                     ? NormalizeDouble(entry + MinProfitPoints * point, digits)
                     : NormalizeDouble(entry - MinProfitPoints * point, digits);

      double existingTP = PositionGetDouble(POSITION_TP);
      if(!trade.PositionModify(g_trades[i].ticket, newSL, existingTP))
         Print("EarlyProtect: Modify SL failed ticket ", g_trades[i].ticket,
               ": ", trade.ResultRetcode());
      else
      {
         g_trades[i].earlyProtected = true;
         Print("EarlyProtect: SL locked at ", newSL,
               " ticket ", g_trades[i].ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Max loss breaker                                                  |
//+------------------------------------------------------------------+
void CheckMaxLossBreaker()
{
   if(MaxTotalOpenLoss <= 0.0) return;

   double totalFloatingPL = 0.0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t))                        continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      totalFloatingPL += PositionGetDouble(POSITION_PROFIT);
   }

   if(totalFloatingPL >= -(MaxTotalOpenLoss)) return;

   Print("MAX LOSS BREAKER: P&L ", totalFloatingPL,
         " exceeded -", MaxTotalOpenLoss, ". Closing all.");
   CloseAllEATrades();
   g_cooloffBarsLeft = CooloffBars;
   Print("Cooloff started: ", CooloffBars, " bars.");
}

//+------------------------------------------------------------------+
//| Rebuild g_trades from open positions after EA restart            |
//+------------------------------------------------------------------+
void RebuildFromOpenPositions()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t))                         continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)  continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)      continue;

      ENUM_POSITION_TYPE posType =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double posTp  = PositionGetDouble(POSITION_TP);
      double sl     = PositionGetDouble(POSITION_SL);
      string comm   = PositionGetString(POSITION_COMMENT);

      int    dir    = (posType == POSITION_TYPE_BUY) ? 1 : -1;
      double tpPts  = TpMinPoints;
      if(posTp > 0 && point > 0)
         tpPts = MathAbs(posTp - entry) / point;
      if(tpPts < 1.0) tpPts = TpMinPoints;

      bool wasHedged = (sl > 0);

      TradeRec rec;
      rec.ticket         = t;
      rec.direction      = dir;
      rec.entryPrice     = entry;
      rec.tpPoints       = tpPts;
      rec.baseLot        = BaseLotSize;
      rec.hedged         = wasHedged;
      rec.hedgeTicket    = 0;
      rec.barTime        = (datetime)PositionGetInteger(POSITION_TIME);
      rec.isReversal     = StringFind(comm, TAG_REV) >= 0;
      rec.isScaleIn      = StringFind(comm, TAG_AVG) >= 0;
      rec.earlyProtected = wasHedged;

      int sz = ArraySize(g_trades);
      ArrayResize(g_trades, sz + 1);
      g_trades[sz] = rec;

      Print("Recovery: ticket ", t, " dir ", dir, " tpPts ", tpPts,
            " hedged ", wasHedged);
   }
}

//+------------------------------------------------------------------+
//| Count open EA trades in direction dir (1=BUY, -1=SELL)          |
//+------------------------------------------------------------------+
int CountOpenEATradesInDir(int dir)
{
   int cnt = 0;
   int sz  = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir)                continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;
      cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
//| Count open unhedged EA trades in direction dir                   |
//+------------------------------------------------------------------+
int CountOpenEATradesInDir_Unhedged(int dir)
{
   int cnt = 0;
   int sz  = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir)                continue;
      if(g_trades[i].hedged)                          continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;
      cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
//| Remove tracking records for positions that are no longer open    |
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
//| Get position ticket from order ticket                            |
//+------------------------------------------------------------------+
ulong GetPositionTicketByOrder(ulong orderTicket)
{
   if(PositionSelectByTicket(orderTicket)) return orderTicket;

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
//| Normalize lot to symbol step / min / max                         |
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
//| Trading hour filter                                               |
//+------------------------------------------------------------------+
bool IsTradingHourAllowed()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
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
//| Returns true if barsAhead bars forward is within weekend         |
//+------------------------------------------------------------------+
bool IsNearWeekend(int barsAhead)
{
   if(barsAhead <= 0) return false;
   datetime checkTime = TimeCurrent() + barsAhead * PeriodSeconds(_Period);
   MqlDateTime dt; TimeToStruct(checkTime, dt);
   if(dt.day_of_week == 6) return true;
   if(dt.day_of_week == 0) return true;
   if(dt.day_of_week == 5 && dt.hour >= WeekendCloseHour) return true;
   return false;
}
//+------------------------------------------------------------------+
