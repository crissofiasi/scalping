//+------------------------------------------------------------------+
//|                                              BarDirectionEA.mq5 |
//|                                  Copyright 2026, Cris Trading   |
//|                                                                  |
//|  Strategy:                                                       |
//|  1. On bar close enter in bar direction, TP = TpPoints           |
//|  2. If ANY open position moves against by ReversePct% of TP:     |
//|     - Open opposite hedge with calculated lot                    |
//|     - Move ALL same-direction positions SL to new hedge TP       |
//|     - Hedge lot covers total losing-side volume + target profit  |
//|     - Repeats on every new reversal (multi-level hedging)        |
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
   ulong    ticket;        // position ticket
   int      direction;     // 1 = BUY, -1 = SELL
   double   entryPrice;
   double   tpPoints;
   double   baseLot;
   bool     hedged;        // reversal already fired?
   ulong    hedgeTicket;   // counterpart position ticket (0 if none)
   datetime barTime;
   bool     isReversal;
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
   //--- 1. Check reversal thresholds on every tick
   CheckReversalTriggers();

   //--- 2. Check for new bar entry (only when no open EA trades)
   datetime barTimes[];
   if(CopyTime(_Symbol, _Period, 0, 2, barTimes) < 2) return;

   datetime currentBarTime = barTimes[1]; // last CLOSED bar

   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      if(CountOpenEATrades() == 0)
         OnNewBar(currentBarTime);
      else
         Print("New bar ignored – ", CountOpenEATrades(), " EA trade(s) still open.");
   }

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
//| Open an original trade and track it                              |
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
//| Check all unhedged trades on every tick for reversal touch       |
//+------------------------------------------------------------------+
void CheckReversalTriggers()
{
   double point         = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double reversePoints = TpPoints * ReversePct / 100.0;
   double bid           = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask           = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   int sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].hedged) continue;   // already triggered a reversal

      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;

      double entry = g_trades[i].entryPrice;
      int    dir   = g_trades[i].direction;

      //--- Check if price has touched the reversal threshold
      bool touched = false;
      if(dir == 1)  touched = (bid <= entry - reversePoints * point); // BUY: price fell
      else           touched = (ask >= entry + reversePoints * point); // SELL: price rose

      if(!touched) continue;

      Print("Reversal threshold touched for ticket ", g_trades[i].ticket,
            "  Entry: ", entry, "  Dir: ", dir,
            "  RevPts: ", reversePoints);

      OpenReversalNow(i, reversePoints, point, bid, ask);

      //--- Refresh size after array may have grown
      sz = ArraySize(g_trades);
   }
}

//+------------------------------------------------------------------+
//| Open reversal at market immediately, adjust original             |
//+------------------------------------------------------------------+
void OpenReversalNow(int origIdx, double revPts, double point, double bid, double ask)
{
   int    dir    = g_trades[origIdx].direction;
   double tp_pts = g_trades[origIdx].tpPoints;

   double revEntry, revTP;
   if(dir == 1)   // triggering BUY → new hedge SELL
   {
      revEntry = bid;
      revTP    = NormalizeDouble(revEntry - tp_pts * point,
                                 (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   }
   else           // triggering SELL → new hedge BUY
   {
      revEntry = ask;
      revTP    = NormalizeDouble(revEntry + tp_pts * point,
                                 (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   }

   //--- Sum ALL open EA lots on the losing side (same direction as triggering position)
   double totalLosingLot = 0.0;
   int sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir) continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;
      totalLosingLot += PositionGetDouble(POSITION_VOLUME);
   }

   //--- New hedge volume:
   //    hedge × tp = totalLosingLot × (tp + rev)  [cover all losing-side losses to new SL]
   //               + BaseLotSize × tp             [target profit]
   //    → hedge = totalLosingLot × (tp + rev) / tp + BaseLotSize
   //    (when only 1 losing position at baseLot this reduces to baseLot×(2tp+rev)/tp)
   double adjHedgeLot = NormalizeVolume(totalLosingLot * (tp_pts + revPts) / tp_pts + BaseLotSize);

   //--- Open new hedge at market
   string revComment = TradeComment + "_" + TAG_REV;
   bool   okRev      = false;
   if(dir == 1)
      okRev = trade.Sell(adjHedgeLot, _Symbol, revEntry, 0, revTP, revComment);
   else
      okRev = trade.Buy (adjHedgeLot, _Symbol, revEntry, 0, revTP, revComment);

   if(!okRev)
   {
      Print("Reversal order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      return;
   }

   ulong revTicket = GetPositionTicketByOrder(trade.ResultOrder());
   Print("Reversal opened. Ticket: ", revTicket,
         "  Entry: ", revEntry, "  TP: ", revTP,
         "  Lot: ", adjHedgeLot, "  TotalLosingLot: ", totalLosingLot);

   //--- Move SL of ALL open losing-side positions to revTP and mark them hedged
   sz = ArraySize(g_trades);
   for(int i = 0; i < sz; i++)
   {
      if(g_trades[i].direction != dir) continue;
      if(!PositionSelectByTicket(g_trades[i].ticket)) continue;

      double existingTP = PositionGetDouble(POSITION_TP);
      if(!trade.PositionModify(g_trades[i].ticket, revTP, existingTP))
         Print("Modify SL failed for ticket ", g_trades[i].ticket, ": ", trade.ResultRetcode());
      else
         Print("SL moved to ", revTP, " for ticket ", g_trades[i].ticket);

      g_trades[i].hedged      = true;
      g_trades[i].hedgeTicket = revTicket;
   }

   //--- Register new hedge (starts unhedged so it can trigger the next level)
   TradeRec revRec;
   revRec.ticket      = revTicket;
   revRec.direction   = -dir;
   revRec.entryPrice  = revEntry;
   revRec.tpPoints    = tp_pts;
   revRec.baseLot     = BaseLotSize;
   revRec.hedged      = false;
   revRec.hedgeTicket = 0;
   revRec.barTime     = g_trades[origIdx].barTime;
   revRec.isReversal  = true;

   sz = ArraySize(g_trades);
   ArrayResize(g_trades, sz + 1);
   g_trades[sz] = revRec;
}

//+------------------------------------------------------------------+
//| Remove records for positions that are no longer open;            |
//| cancel their associated pending orders if still active          |
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
