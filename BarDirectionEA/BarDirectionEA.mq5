//+------------------------------------------------------------------+
//|                                              BarDirectionEA.mq5 |
//|                                  Copyright 2026, Cris Trading   |
//|                                                                  |
//|  Strategy:                                                       |
//|  1. On bar close enter in bar direction, TP = TpPoints           |
//|  2. If price moves against by ReversePct% of TpPoints → hedge:  |
//|     - Open opposite trade, same TpPoints                         |
//|     - Move original SL to new trade's TP level                  |
//|     - Adjust original lot so hitting TP earns base_lot × TpPts  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Cris Trading"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Trade Settings ==="
input double BaseLotSize        = 0.01;       // Base lot size
input double TpPoints           = 200.0;      // Take Profit in points
input double ReversePct         = 50.0;       // Reversal threshold (% of TP points)
input long   MagicNumber        = 77777;      // Magic number
input int    Slippage           = 50;         // Slippage (points)
input string TradeComment       = "BarDir";   // Comment prefix

input group "=== Risk Settings ==="
input double MaxLotSize         = 50.0;       // Max lot size cap
input bool   OneTradePerBar     = true;       // Only one entry per bar (each direction)

//--- Comment tags
#define TAG_ORIG  "ORIG"
#define TAG_REV   "REV"

//--- Trade record
struct TradeRec
{
   ulong   ticket;         // position ticket
   int     direction;      // 1 = BUY, -1 = SELL
   double  entryPrice;
   double  tpPoints;
   double  baseLot;        // original base lot at entry
   bool    hedged;         // reversal already opened?
   ulong   hedgeTicket;    // counterpart ticket (0 if none)
   datetime barTime;       // bar that triggered this entry
   bool    isReversal;     // is this the reversal leg?
};

TradeRec g_trades[];

//--- Bar tracking
datetime g_lastBarTime  = 0;
datetime g_lastBuyBar   = 0;
datetime g_lastSellBar  = 0;

CTrade   trade;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   ArrayResize(g_trades, 0);
   Print("BarDirectionEA initialized. Symbol: ", _Symbol,
         "  TF: ", EnumToString(_Period),
         "  TpPoints: ", TpPoints,
         "  ReversePct: ", ReversePct);
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
   //--- 1. Check for new bar entry
   datetime barTimes[];
   if(CopyTime(_Symbol, _Period, 0, 2, barTimes) < 2) return;

   datetime currentBarTime = barTimes[1]; // last CLOSED bar

   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      OnNewBar(currentBarTime);
   }

   //--- 2. Check existing trades for reversal trigger
   CheckReversalTriggers();

   //--- 3. Clean stale records
   PruneClosedTrades();
}

//+------------------------------------------------------------------+
//| Called when a new bar opens (i.e. previous bar just closed)      |
//+------------------------------------------------------------------+
void OnNewBar(datetime closedBarTime)
{
   double open  = iOpen (_Symbol, _Period, 1);
   double close = iClose(_Symbol, _Period, 1);

   if(open <= 0 || close <= 0) return;

   bool bullish = close > open;
   bool bearish = close < open;

   if(bullish)
   {
      if(!OneTradePerBar || g_lastBuyBar != closedBarTime)
      {
         g_lastBuyBar = closedBarTime;
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double tp  = ask + TpPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         if(OpenOriginalTrade(ORDER_TYPE_BUY, ask, tp, closedBarTime))
            Print("BUY opened on bullish bar close. Entry: ", ask, " TP: ", tp);
      }
   }

   if(bearish)
   {
      if(!OneTradePerBar || g_lastSellBar != closedBarTime)
      {
         g_lastSellBar = closedBarTime;
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double tp  = bid - TpPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         if(OpenOriginalTrade(ORDER_TYPE_SELL, bid, tp, closedBarTime))
            Print("SELL opened on bearish bar close. Entry: ", bid, " TP: ", tp);
      }
   }
}

//+------------------------------------------------------------------+
//| Open an original (non-reversal) trade and track it               |
//+------------------------------------------------------------------+
bool OpenOriginalTrade(ENUM_ORDER_TYPE type, double price, double tp, datetime barTime)
{
   string comment = TradeComment + "_" + TAG_ORIG;
   bool ok = false;

   if(type == ORDER_TYPE_BUY)
      ok = trade.Buy(BaseLotSize, _Symbol, price, 0, tp, comment);
   else
      ok = trade.Sell(BaseLotSize, _Symbol, price, 0, tp, comment);

   if(!ok)
   {
      Print("OpenOriginalTrade failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      return false;
   }

   ulong posTicket = GetPositionTicketByOrder(trade.ResultOrder());

   TradeRec rec;
   rec.ticket      = posTicket;
   rec.direction   = (type == ORDER_TYPE_BUY) ? 1 : -1;
   rec.entryPrice  = price;
   rec.tpPoints    = TpPoints;
   rec.baseLot     = BaseLotSize;
   rec.hedged      = false;
   rec.hedgeTicket = 0;
   rec.barTime     = barTime;
   rec.isReversal  = false;

   int sz = ArraySize(g_trades);
   ArrayResize(g_trades, sz + 1);
   g_trades[sz] = rec;

   return true;
}

//+------------------------------------------------------------------+
//| Check all unhedged original trades for reversal trigger          |
//+------------------------------------------------------------------+
void CheckReversalTriggers()
{
   double point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double reversePoints = TpPoints * ReversePct / 100.0;

   for(int i = 0; i < ArraySize(g_trades); i++)
   {
      if(g_trades[i].isReversal) continue;  // don't hedge reversals
      if(g_trades[i].hedged)     continue;

      ulong ticket = g_trades[i].ticket;
      if(!PositionSelectByTicket(ticket)) continue;  // already closed

      double entry = g_trades[i].entryPrice;
      int    dir   = g_trades[i].direction;
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double mid   = (bid + ask) * 0.5;

      //--- Calculate adverse excursion from entry
      double adverse = 0.0;
      if(dir == 1)  adverse = (entry - mid) / point;   // BUY moved down
      else           adverse = (mid - entry) / point;   // SELL moved up

      if(adverse < reversePoints) continue;  // threshold not reached yet

      //--- Trigger: open reversal trade
      Print("Reversal triggered for ticket ", ticket,
            "  adverse: ", adverse, " pts  threshold: ", reversePoints, " pts");

      OpenReversalTrade(i, reversePoints, point);
   }
}

//+------------------------------------------------------------------+
//| Open reversal trade and adjust original                          |
//+------------------------------------------------------------------+
void OpenReversalTrade(int idx, double revPts, double point)
{
   ulong  origTicket = g_trades[idx].ticket;
   int    dir        = g_trades[idx].direction;   // original direction
   double baseLot    = g_trades[idx].baseLot;
   double tp_pts     = g_trades[idx].tpPoints;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- Prices for reversal
   double revEntry, revTP, revSL;
   if(dir == 1)   // original BUY → reversal SELL
   {
      revEntry = bid;
      revTP    = revEntry - tp_pts * point;
      revSL    = 0.0;  // no SL on reversal (original's TP acts as cap)
   }
   else           // original SELL → reversal BUY
   {
      revEntry = ask;
      revTP    = revEntry + tp_pts * point;
      revSL    = 0.0;
   }

   //--- New SL for original = reversal's TP
   double origNewSL = revTP;

   //--- Volume adjustment for original:
   //    adj_lot × tp_pts = base_lot × tp_pts + base_lot × rev_pts
   //    → adj_lot = base_lot × (tp_pts + rev_pts) / tp_pts
   double adjLot = NormalizeVolume(baseLot * (tp_pts + revPts) / tp_pts);

   //--- Open reversal trade
   string revComment = TradeComment + "_" + TAG_REV;
   bool okRev = false;
   if(dir == 1)
      okRev = trade.Sell(baseLot, _Symbol, revEntry, revSL, revTP, revComment);
   else
      okRev = trade.Buy (baseLot, _Symbol, revEntry, revSL, revTP, revComment);

   if(!okRev)
   {
      Print("Reversal order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      return;
   }

   ulong revTicket = GetPositionTicketByOrder(trade.ResultOrder());
   Print("Reversal trade opened. Ticket: ", revTicket,
         "  Entry: ", revEntry, "  TP: ", revTP, "  Lot: ", baseLot);

   //--- Adjust original: set new SL and new volume
   if(PositionSelectByTicket(origTicket))
   {
      double origTP = PositionGetDouble(POSITION_TP);

      //--- Modify SL of original to reversal's TP
      if(!trade.PositionModify(origTicket, origNewSL, origTP))
         Print("Modify original SL failed: ", trade.ResultRetcode());
      else
         Print("Original SL moved to: ", origNewSL);

      //--- Adjust original volume by closing and reopening
      double curLot = PositionGetDouble(POSITION_VOLUME);
      if(MathAbs(adjLot - curLot) >= SymbolInfoDouble(TradeSymbol, SYMBOL_VOLUME_STEP))
      {
         double extraLot = NormalizeVolume(adjLot - curLot);
         if(extraLot >= SymbolInfoDouble(TradeSymbol, SYMBOL_VOLUME_MIN))
         {
            //--- Add extra lot as an additional position (same direction, same TP + SL)
            string adjComment = TradeComment + "_" + TAG_ORIG + "_adj";
            bool okAdj = false;
            if(dir == 1)
               okAdj = trade.Buy (extraLot, _Symbol, ask, origNewSL, origTP, adjComment);
            else
               okAdj = trade.Sell(extraLot, _Symbol, bid, origNewSL, origTP, adjComment);

            if(okAdj)
               Print("Volume adjustment: added ", extraLot, " lot(s) in original direction. Adj total: ", adjLot);
            else
               Print("Volume adjustment order failed: ", trade.ResultRetcode());
         }
      }
   }

   //--- Record reversal
   TradeRec revRec;
   revRec.ticket      = revTicket;
   revRec.direction   = -dir;
   revRec.entryPrice  = revEntry;
   revRec.tpPoints    = tp_pts;
   revRec.baseLot     = baseLot;
   revRec.hedged      = false;
   revRec.hedgeTicket = origTicket;
   revRec.barTime     = g_trades[idx].barTime;
   revRec.isReversal  = true;

   int sz = ArraySize(g_trades);
   ArrayResize(g_trades, sz + 1);
   g_trades[sz] = revRec;

   //--- Mark original as hedged
   g_trades[idx].hedged      = true;
   g_trades[idx].hedgeTicket = revTicket;
}

//+------------------------------------------------------------------+
//| Remove records for positions that are no longer open             |
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
//| Get position ticket from order ticket (netting / hedging modes)  |
//| In MT5 hedging mode the position ID equals the opening deal ID.  |
//| We scan all positions for a matching ticket or, if that fails,   |
//| return the position with the highest ticket (most recently opened)|
//+------------------------------------------------------------------+
ulong GetPositionTicketByOrder(ulong orderTicket)
{
   //--- In hedging mode position ID == order ID
   if(PositionSelectByTicket(orderTicket))
      return orderTicket;

   //--- Fallback: find highest-ticket position with our magic that is not
   //    already tracked in g_trades
   ulong best = 0;
   int total  = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;

      //--- Skip already tracked tickets
      bool known = false;
      for(int j = 0; j < ArraySize(g_trades); j++)
         if(g_trades[j].ticket == t) { known = true; break; }
      if(known) continue;

      if(t > best) best = t;
   }
   return (best > 0) ? best : orderTicket;
}

//+------------------------------------------------------------------+
//| Normalize volume to symbol constraints                           |
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
