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
input double BaseEquity      = 0.0;   // Base equity for linear lot scaling (0=off)
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
input bool   EnableScaleIn         = true;  // Scale-in on same-dir NRTR advance
input double EarlyTpPct      = 50.0;  // SL-lock activates at X% of TP distance
input double MinProfitPoints = 20.0;  // Protective SL offset / scale-in gap (points)
input int    EarlyCloseMinBars = 1;   // Minimum closed bars from entry before early close

input group "=== NRTR Advance Entries ==="
input bool   EnableAdvanceEntries   = true; // Allow entries on NRTR advances
input double RatchetTolerancePoints = 0.0;  // SL offset from ratchet (points)

input group "=== Lower TF Early Close ==="
input bool             EnableLowerTFEarlyClose = true;     // Gate early close by lower TF flip
input ENUM_TIMEFRAMES  LowerTF                 = PERIOD_M1; // Lower timeframe
input int              LowerTFShift            = 0;         // 0=current bar, 1=closed bar

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
#define TAG_ADV  "ADV"

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
   return CalcATR_TF(_Period, barIdx);
}

//+------------------------------------------------------------------+
//| Run the NRTR state machine from NRTR_Lookback bars back          |
//| to barIdx and return the state AT barIdx                         |
//+------------------------------------------------------------------+
NRTRState CalcNRTRAtBar(int barIdx)
{
   return CalcNRTRAtBar_TF(_Period, barIdx);
}

//+------------------------------------------------------------------+
//| Compute ATR (Wilder) on a specific timeframe                    |
//+------------------------------------------------------------------+
double CalcATR_TF(ENUM_TIMEFRAMES tf, int barIdx)
{
   double sum = 0.0;
   int    per = NRTR_ATRPeriod;

   for(int i = barIdx; i < barIdx + per; i++)
   {
      double hi   = iHigh (_Symbol, tf, i);
      double lo   = iLow  (_Symbol, tf, i);
      double prvc = iClose(_Symbol, tf, i + 1);
      if(hi <= 0 || lo <= 0 || prvc <= 0) continue;

      double tr = MathMax(hi - lo,
                  MathMax(MathAbs(hi - prvc), MathAbs(lo - prvc)));
      sum += tr;
   }
   return sum / per;
}

//+------------------------------------------------------------------+
//| Run NRTR state machine on a specific timeframe                  |
//+------------------------------------------------------------------+
NRTRState CalcNRTRAtBar_TF(ENUM_TIMEFRAMES tf, int barIdx)
{
   int startBar = barIdx + NRTR_Lookback - 1;

   //--- Seed with state at the oldest bar (assume uptrend start)
   NRTRState s;
   s.direction = 1;
   double initClose = iClose(_Symbol, tf, startBar);
   double initATR   = CalcATR_TF(tf, startBar);
   s.extreme = initClose;
   s.level   = initClose - NRTR_K * initATR;

   //--- Walk forward bar by bar from startBar-1 down to barIdx
   for(int b = startBar - 1; b >= barIdx; b--)
   {
      double cl  = iClose(_Symbol, tf, b);
      double atr = CalcATR_TF(tf, b);
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

   bool advanceUp   = (s1.direction ==  1 && s2.direction ==  1 && s1.extreme > s2.extreme);
   bool advanceDown = (s1.direction == -1 && s2.direction == -1 && s1.extreme < s2.extreme);

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
            double sl = NormalizeDouble(CalcRatchetSL(1, s1.level), digits);
            if(OpenTrade(ORDER_TYPE_BUY, ask, sl, tp, dynTp, closedBarTime, TAG_ORIG))
               Print("NRTR BUY entered. Entry:", ask, " SL:", sl, " TP:", tp,
                     " RatchetLevel:", s1.level, " DynTpPts:", dynTp);
         }
      }
   }
   else if(EnableAdvanceEntries && advanceUp)
   {
      if(!OneTradePerBar || g_lastBuyBar != closedBarTime)
      {
         g_lastBuyBar = closedBarTime;
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         int    openBuys = CountOpenEATradesInDir(1);

         if(openBuys == 0)
         {
            double tp = NormalizeDouble(ask + dynTp * point, digits);
            double sl = NormalizeDouble(CalcRatchetSL(1, s1.level), digits);
            if(OpenTrade(ORDER_TYPE_BUY, ask, sl, tp, dynTp, closedBarTime, TAG_ADV))
               Print("NRTR BUY advance entry. Entry:", ask, " SL:", sl, " TP:", tp,
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
            double sl = NormalizeDouble(CalcRatchetSL(-1, s1.level), digits);
            if(OpenTrade(ORDER_TYPE_SELL, bid, sl, tp, dynTp, closedBarTime, TAG_ORIG))
               Print("NRTR SELL entered. Entry:", bid, " SL:", sl, " TP:", tp,
                     " RatchetLevel:", s1.level, " DynTpPts:", dynTp);
         }
      }
   }
   else if(EnableAdvanceEntries && advanceDown)
   {
      if(!OneTradePerBar || g_lastSellBar != closedBarTime)
      {
         g_lastSellBar = closedBarTime;
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         int    openSells = CountOpenEATradesInDir(-1);

         if(openSells == 0)
         {
            double tp = NormalizeDouble(bid - dynTp * point, digits);
            double sl = NormalizeDouble(CalcRatchetSL(-1, s1.level), digits);
            if(OpenTrade(ORDER_TYPE_SELL, bid, sl, tp, dynTp, closedBarTime, TAG_ADV))
               Print("NRTR SELL advance entry. Entry:", bid, " SL:", sl, " TP:", tp,
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
//| Open a trade (original, scale-in, or reversal) with full SL/TP  |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp,
               double tpPts, datetime barTime, string tag)
{
   string comment = TradeComment + "_" + tag;
   double baseLot = GetBaseLot();
   bool ok = (type == ORDER_TYPE_BUY)
             ? trade.Buy (baseLot, _Symbol, price, sl, tp, comment)
             : trade.Sell(baseLot, _Symbol, price, sl, tp, comment);

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
   rec.baseLot        = baseLot;
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
   double baseLot = GetBaseLot();
   if(ptValPerLot > 0.0 && floatingLoss < 0.0)
      rawVol = MathAbs(floatingLoss) / (dynTp * ptValPerLot) + baseLot;

   if(rawVol > MaxLotSize)
   {
      Print("ScaleIn STOPPED: required lot ", rawVol,
            " exceeds MaxLotSize ", MaxLotSize);
      return;
   }

   double adjVol = NormalizeVolume(MathMax(rawVol, baseLot));

   double tp = (dir == 1)
               ? NormalizeDouble(execPrice + dynTp * point, digits)
               : NormalizeDouble(execPrice - dynTp * point, digits);
   double sl = NormalizeDouble(CalcRatchetSL(dir, ratchetLevel), digits);

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
   rec.baseLot        = baseLot;
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

   UpdateTPForDirection(dir, tp);
   UpdateSLToRatchet(dir, ratchetLevel);
}

//+------------------------------------------------------------------+
//| Update TP for same-dir trades to a common level                 |
//+------------------------------------------------------------------+
void UpdateTPForDirection(int dir, double tpPrice)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double newTP = NormalizeDouble(tpPrice, digits);

   int sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir)                continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;

      double existingSL = PositionGetDouble(POSITION_SL);
      double currentTP  = PositionGetDouble(POSITION_TP);
      if(MathAbs(currentTP - newTP) <= SymbolInfoDouble(_Symbol, SYMBOL_POINT))
         continue;

      if(!trade.PositionModify(g_trades[i].ticket, existingSL, newTP))
         Print("TP update failed ticket ", g_trades[i].ticket,
               ": ", trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Compute SL from ratchet level with tolerance                    |
//+------------------------------------------------------------------+
double CalcRatchetSL(int dir, double ratchetLevel)
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double offset = RatchetTolerancePoints * point;
   return (dir == 1) ? (ratchetLevel - offset) : (ratchetLevel + offset);
}

//+------------------------------------------------------------------+
//| Update SL for same-dir trades to ratchet ± tolerance            |
//+------------------------------------------------------------------+
void UpdateSLToRatchet(int dir, double ratchetLevel)
{
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double newSL  = NormalizeDouble(CalcRatchetSL(dir, ratchetLevel), digits);

   int sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir)                continue;
      if(g_trades[i].hedged)                          continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;

      double currentSL = PositionGetDouble(POSITION_SL);
      bool better = (dir == 1) ? (currentSL <= 0.0 || newSL > currentSL)
                               : (currentSL <= 0.0 || newSL < currentSL);
      if(!better) continue;

      double existingTP = PositionGetDouble(POSITION_TP);
      if(!trade.PositionModify(g_trades[i].ticket, newSL, existingTP))
         Print("Ratchet SL update failed ticket ", g_trades[i].ticket,
               ": ", trade.ResultRetcode());
   }
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

   if(!HasMinClosedBarsSinceEntry(t))                    continue;
   if(!IsEarlyCloseAllowedByLowerTF(t))                  continue;

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
//| Check minimum closed bars since entry                           |
//+------------------------------------------------------------------+
bool HasMinClosedBarsSinceEntry(ulong ticket)
{
   if(EarlyCloseMinBars <= 0) return true;
   if(!PositionSelectByTicket(ticket)) return false;

   datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
   int shift = iBarShift(_Symbol, _Period, entryTime, true);
   if(shift < 0) return false;

   return (shift >= EarlyCloseMinBars);
}

//+------------------------------------------------------------------+
//| Gate early close using lower TF flips                           |
//+------------------------------------------------------------------+
bool IsEarlyCloseAllowedByLowerTF(ulong ticket)
{
   if(!EnableLowerTFEarlyClose) return true;
   if(!PositionSelectByTicket(ticket)) return false;

   int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;

   NRTRState s1 = CalcNRTRAtBar_TF(LowerTF, LowerTFShift);
   NRTRState s2 = CalcNRTRAtBar_TF(LowerTF, LowerTFShift + 1);

   bool flipUp   = (s1.direction ==  1 && s2.direction == -1);
   bool flipDown = (s1.direction == -1 && s2.direction ==  1);

   if(dir == 1) return flipDown;
   return flipUp;
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

   bool blockBuy  = IsGroupProfitableAtSL(1);
   bool blockSell = IsGroupProfitableAtSL(-1);

   int sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].earlyProtected)                      continue;
      if(!PositionSelectByTicket(g_trades[i].ticket))     continue;

      double entry    = g_trades[i].entryPrice;
      int    dir      = g_trades[i].direction;
      double tpPts    = g_trades[i].tpPoints;
      double threshold = tpPts * EarlyTpPct / 100.0;

      if((dir == 1 && blockBuy) || (dir == -1 && blockSell)) continue;

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
//| True if total P/L at current SL is positive (same direction)    |
//+------------------------------------------------------------------+
bool IsGroupProfitableAtSL(int dir)
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(point <= 0.0 || tickVal <= 0.0 || tickSz <= 0.0) return false;

   double ptValPerLot = tickVal / tickSz * point;
   double total = 0.0;
   bool   any   = false;

   int sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir)                continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;

      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0) return false;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      double diffPts = (dir == 1) ? (sl - entry) / point
                                  : (entry - sl) / point;
      total += diffPts * ptValPerLot * vol;
      any = true;
   }

   return (any && total > 0.0);
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
//| Get base lot scaled by equity                                   |
//+------------------------------------------------------------------+
double GetBaseLot()
{
   if(BaseEquity <= 0.0) return BaseLotSize;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= BaseEquity) return BaseLotSize;

   return BaseLotSize * (equity / BaseEquity);
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
