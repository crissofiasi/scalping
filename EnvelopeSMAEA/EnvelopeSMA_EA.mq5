//+------------------------------------------------------------------+
//|                                            EnvelopeSMA_EA.mq5   |
//|                                  Copyright 2026, Cris Trading   |
//|                                                                  |
//|  Strategy: XAUUSD Daily                                         |
//|  - Envelopes(20, 4%, SMA, Median, shift 1)                     |
//|  - SMA(20, Median, shift 1)                                     |
//|  - Entry on SMA cross, TP at envelope                           |
//|  - Daily TP refresh to new envelope levels                      |
//|  - TP hit → counter trade (vol × Factor), TP at SMA            |
//|  - Close outside envelope → TP → SMA; vol × Factor if at loss  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Cris Trading"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Input parameters
input group "=== Symbol & Timeframe ==="
input string   TradeSymbol       = "XAUUSD";      // Symbol

input group "=== Indicator Settings ==="
input int      EnvPeriod         = 20;            // Envelope Period
input double   EnvDeviation      = 4.0;           // Envelope Deviation (%)
input int      SmaPeriod         = 20;            // SMA Period
input int      IndicatorShift    = 1;             // Indicator Shift

input group "=== Trade Settings ==="
input double   InitialLotSize    = 0.01;          // Initial Lot Size
input double   BounceThresholdPct = 0.10;         // SMA Bounce Zone (% of SMA price)
input double   VolumeFactor      = 1.5;           // Volume Adjustment Factor
input long     MagicNumber       = 88888;         // Magic Number
input int      Slippage          = 50;            // Slippage (points)
input string   TradeComment      = "EnvSMA";      // Trade Comment Base

input group "=== Risk Settings ==="
input double   MaxLotSize        = 10.0;          // Maximum Lot Size

//--- TP type tags used inside comments
#define TAG_ENV_BUY   "EnvBUY"
#define TAG_ENV_SELL  "EnvSELL"
#define TAG_SMA_BUY   "SMABUY"
#define TAG_SMA_SELL  "SMASELL"

//--- Global objects
CTrade  trade;

//--- Indicator handles (daily)
int     g_envHandle  = INVALID_HANDLE;
int     g_smaHandle  = INVALID_HANDLE;

//--- Bar tracking
datetime g_lastBarTime = 0;

//--- Records of trades opened today (to enforce max 1 per direction per day)
datetime g_lastBuyDay  = 0;
datetime g_lastSellDay = 0;

//--- Store the tickets of positions we just detected a TP hit on (avoid double processing)
ulong    g_lastClosedTicket = 0;

//--- Real-time SMA cross state (per tick)
//    1 = price above SMA, -1 = price below SMA, 0 = not yet initialised
int      g_crossState = 0;

//--- SMA bounce detection state
bool     g_nearSMA           = false;  // price is currently inside bounce zone
int      g_bounceApproachSide = 0;     // side from which price entered zone (1=above, -1=below)

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!SymbolSelect(TradeSymbol, true))
   {
      Print("Symbol not available: ", TradeSymbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   //--- Create indicator handles on D1
   g_envHandle = iEnvelopes(TradeSymbol, PERIOD_D1,
                             EnvPeriod, IndicatorShift,
                             MODE_SMA, PRICE_MEDIAN, EnvDeviation);

   g_smaHandle = iMA(TradeSymbol, PERIOD_D1,
                     SmaPeriod, IndicatorShift,
                     MODE_SMA, PRICE_MEDIAN);

   if(g_envHandle == INVALID_HANDLE || g_smaHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles. Error: ", GetLastError());
      return INIT_FAILED;
   }

   Print("EnvelopeSMA EA initialized on ", TradeSymbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_envHandle != INVALID_HANDLE) IndicatorRelease(g_envHandle);
   if(g_smaHandle != INVALID_HANDLE) IndicatorRelease(g_smaHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Immediately detect SMA cross on every tick
   CheckTickCross();

   //--- Detect SMA bounce on every tick
   CheckTickBounce();

   //--- Daily TP refresh – trigger once per new D1 bar
   datetime barTime[];
   if(CopyTime(TradeSymbol, PERIOD_D1, 0, 1, barTime) >= 1)
   {
      if(barTime[0] != g_lastBarTime)
      {
         g_lastBarTime = barTime[0];
         OnNewDailyBar();
      }
   }
}

//+------------------------------------------------------------------+
//| Trade transaction handler – detect TP hits                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest    &request,
                        const MqlTradeResult     &result)
{
   //--- We care about position closes (deal_out)
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   //--- Fetch the deal
   if(!HistoryDealSelect(trans.deal))
      return;

   //--- Only process deals belonging to our magic number
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber)
      return;

   //--- Only interested in position exits via TP
   ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
   ENUM_DEAL_ENTRY  entry  = (ENUM_DEAL_ENTRY) HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   if(entry != DEAL_ENTRY_OUT)
      return;

   if(reason != DEAL_REASON_TP)
      return;

   //--- Avoid double processing
   ulong closedTicket = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(closedTicket == g_lastClosedTicket)
      return;
   g_lastClosedTicket = closedTicket;

   //--- Get deal details
   string   comment  = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   double   closedVol = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);

   Print("TP HIT detected – deal: ", trans.deal,
         "  comment: ", comment,
         "  vol: ", closedVol,
         "  type: ", EnumToString(dealType));

   //--- Calculate new counter-trade volume
   double newVolume = NormalizeVolume(closedVol * VolumeFactor);

   //--- Read current indicator levels
   double smaVal    = GetSMA(1);
   double envUpper  = GetEnvUpper(1);
   double envLower  = GetEnvLower(1);

   if(smaVal == 0.0 || envUpper == 0.0 || envLower == 0.0)
   {
      Print("Could not read indicator values for counter-trade. Aborting.");
      return;
   }

   //--- Determine counter direction based on which tag was in the closed position
   if(StringFind(comment, TAG_ENV_BUY) >= 0)
   {
      //--- BUY was TP'd at upper envelope → open counter SELL with TP at SMA
      double tp = smaVal;
      double price = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
      string newComment = TradeComment + "_" + TAG_SMA_SELL;
      if(trade.Sell(newVolume, TradeSymbol, price, 0, tp, newComment))
      {
         Print("Counter SELL opened. Vol: ", newVolume, " TP: ", tp);
         g_lastSellDay = TimeCurrent();
      }
      else
         Print("Counter SELL failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
   else if(StringFind(comment, TAG_ENV_SELL) >= 0)
   {
      //--- SELL was TP'd at lower envelope → open counter BUY with TP at SMA
      double tp = smaVal;
      double price = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
      string newComment = TradeComment + "_" + TAG_SMA_BUY;
      if(trade.Buy(newVolume, TradeSymbol, price, 0, tp, newComment))
      {
         Print("Counter BUY opened. Vol: ", newVolume, " TP: ", tp);
         g_lastBuyDay = TimeCurrent();
      }
      else
         Print("Counter BUY failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
   //--- SMA counter trades that hit TP: we do NOT open further counters
   //    (chain stops at SMA level)
}

//+------------------------------------------------------------------+
//| Real-time SMA bounce detection (called on every tick)           |
//| Price enters the zone around SMA then exits on the same side    |
//| → trade in that direction with TP at the envelope               |
//+------------------------------------------------------------------+
void CheckTickBounce()
{
   double sma = GetSMA(0);
   if(sma == 0.0 || BounceThresholdPct <= 0.0) return;

   double bid = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
   double mid = (bid + ask) * 0.5;

   double distPct = MathAbs(mid - sma) / sma * 100.0;
   bool   inZone  = (distPct <= BounceThresholdPct);
   int    curSide = (mid >= sma) ? 1 : -1;

   if(!g_nearSMA)
   {
      if(inZone)   // just entered zone – record approach side
      {
         g_nearSMA            = true;
         g_bounceApproachSide = curSide;
      }
      return;
   }

   //--- Was inside zone
   if(inZone) return;  // still inside, wait

   //--- Exited zone
   g_nearSMA = false;

   //--- Exit on OPPOSITE side = cross, handled by CheckTickCross – ignore here
   if(curSide != g_bounceApproachSide)
   {
      g_bounceApproachSide = 0;
      return;
   }

   //--- Exit on SAME side = bounce confirmed
   double envUpper = GetEnvUpper(0);
   double envLower = GetEnvLower(0);
   g_bounceApproachSide = 0;

   if(envUpper == 0.0 || envLower == 0.0) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime todayMidnight = StructToTime(dt);

   if(curSide == 1)   // bounced above SMA → BUY
   {
      Print("SMA bounce UP (tick) – price: ", mid, "  SMA: ", sma);
      if(g_lastBuyDay < todayMidnight)
      {
         OpenEnvelopeTrade(ORDER_TYPE_BUY, envUpper);
         g_lastBuyDay = TimeCurrent();
      }
      else
         Print("BUY already opened today (bounce), skipping.");
   }
   else               // bounced below SMA → SELL
   {
      Print("SMA bounce DOWN (tick) – price: ", mid, "  SMA: ", sma);
      if(g_lastSellDay < todayMidnight)
      {
         OpenEnvelopeTrade(ORDER_TYPE_SELL, envLower);
         g_lastSellDay = TimeCurrent();
      }
      else
         Print("SELL already opened today (bounce), skipping.");
   }
}

//+------------------------------------------------------------------+
//| Real-time SMA cross detection (called on every tick)            |
//+------------------------------------------------------------------+
void CheckTickCross()
{
   //--- Use D1 SMA[0] (shift already baked into the handle)
   double sma = GetSMA(0);
   if(sma == 0.0) return;

   //--- Mid-price for cross comparison
   double bid = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
   double mid = (bid + ask) * 0.5;

   int newState = (mid >= sma) ? 1 : -1;

   if(g_crossState == 0)          // first tick – just record state
   {
      g_crossState = newState;
      return;
   }

   if(newState == g_crossState)   // no cross yet
      return;

   //--- Cross detected – read current envelope levels
   double envUpper = GetEnvUpper(0);
   double envLower = GetEnvLower(0);

   if(envUpper == 0.0 || envLower == 0.0)
   {
      g_crossState = newState;
      return;
   }

   //--- Day boundary for the per-day limit
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime todayMidnight = StructToTime(dt);

   if(newState == 1)   // crossed above SMA → BUY
   {
      Print("SMA cross UP (tick) – price: ", mid, "  SMA: ", sma);
      if(g_lastBuyDay < todayMidnight)
      {
         OpenEnvelopeTrade(ORDER_TYPE_BUY, envUpper);
         g_lastBuyDay = TimeCurrent();
      }
      else
         Print("BUY already opened today, skipping.");
   }
   else                // crossed below SMA → SELL
   {
      Print("SMA cross DOWN (tick) – price: ", mid, "  SMA: ", sma);
      if(g_lastSellDay < todayMidnight)
      {
         OpenEnvelopeTrade(ORDER_TYPE_SELL, envLower);
         g_lastSellDay = TimeCurrent();
      }
      else
         Print("SELL already opened today, skipping.");
   }

   g_crossState = newState;
}

//+------------------------------------------------------------------+
//| Called once per new daily bar – TP refresh only                  |
//+------------------------------------------------------------------+
void OnNewDailyBar()
{
   double smaToday      = GetSMA(1);
   double envUpperToday = GetEnvUpper(1);
   double envLowerToday = GetEnvLower(1);

   if(smaToday == 0.0 || envUpperToday == 0.0 || envLowerToday == 0.0)
   {
      Print("Indicator data not ready yet.");
      return;
   }

   double closeYest = iClose(TradeSymbol, PERIOD_D1, 1);

   Print("New Day – SMA: ", smaToday,
         "  EnvUp: ", envUpperToday,
         "  EnvLo: ", envLowerToday,
         "  CloseYest: ", closeYest);

   //--- Update TPs of existing positions to fresh daily levels
   UpdateExistingPositionTPs(smaToday, envUpperToday, envLowerToday, closeYest);
}

//+------------------------------------------------------------------+
//| Update TPs of open positions on each new day                     |
//+------------------------------------------------------------------+
void UpdateExistingPositionTPs(double sma, double envUpper, double envLower, double closePrice)
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != TradeSymbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)  != MagicNumber) continue;

      string  comment  = PositionGetString(POSITION_COMMENT);
      double  openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double  currentTP = PositionGetDouble(POSITION_TP);
      double  sl        = PositionGetDouble(POSITION_SL);

      bool isEnvBuy    = StringFind(comment, TAG_ENV_BUY)   >= 0;
      bool isEnvSell   = StringFind(comment, TAG_ENV_SELL)  >= 0;
      bool isSmaBuy    = StringFind(comment, TAG_SMA_BUY)   >= 0;
      bool isSmaSell   = StringFind(comment, TAG_SMA_SELL)  >= 0;

      double newTP = 0.0;

      //--- Envelope TP positions: refresh to today's envelope levels
      if(isEnvBuy)
      {
         //--- Check if price closed OUTSIDE envelope (above upper)
         if(closePrice > envUpper)
         {
            //--- Redirect TP to SMA — check if this puts position at a loss
            newTP = sma;
            AdjustTPWithVolumeCheck(ticket, posType, comment, openPrice, newTP, sma,
                                    TAG_ENV_BUY, TAG_SMA_BUY);
         }
         else
         {
            newTP = envUpper;
            ModifyPositionTP(ticket, sl, newTP);
            Print("EnvBUY TP updated to upper envelope: ", newTP);
         }
      }
      else if(isEnvSell)
      {
         //--- Check if price closed OUTSIDE envelope (below lower)
         if(closePrice < envLower)
         {
            //--- Redirect TP to SMA — check if this puts position at a loss
            newTP = sma;
            AdjustTPWithVolumeCheck(ticket, posType, comment, openPrice, newTP, sma,
                                    TAG_ENV_SELL, TAG_SMA_SELL);
         }
         else
         {
            newTP = envLower;
            ModifyPositionTP(ticket, sl, newTP);
            Print("EnvSELL TP updated to lower envelope: ", newTP);
         }
      }
      //--- SMA TP positions: refresh to today's SMA level
      else if(isSmaBuy)
      {
         newTP = sma;
         if(MathAbs(newTP - currentTP) > SymbolInfoDouble(TradeSymbol, SYMBOL_POINT))
         {
            ModifyPositionTP(ticket, sl, newTP);
            Print("SmaBUY TP updated to SMA: ", newTP);
         }
      }
      else if(isSmaSell)
      {
         newTP = sma;
         if(MathAbs(newTP - currentTP) > SymbolInfoDouble(TradeSymbol, SYMBOL_POINT))
         {
            ModifyPositionTP(ticket, sl, newTP);
            Print("SmaSELL TP updated to SMA: ", newTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Adjust TP to SMA with optional volume adjustment                 |
//| Called when an envelope position's TP moves to SMA              |
//+------------------------------------------------------------------+
void AdjustTPWithVolumeCheck(ulong   ticket,
                              ENUM_POSITION_TYPE posType,
                              string  comment,
                              double  openPrice,
                              double  newTP,
                              double  sma,
                              string  oldTag,
                              string  newTag)
{
   double sl          = PositionGetDouble(POSITION_SL);
   double currentVol  = PositionGetDouble(POSITION_VOLUME);
   string sym         = PositionGetString(POSITION_SYMBOL);
   double bid         = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask         = SymbolInfoDouble(sym, SYMBOL_ASK);

   bool posAtLoss = (posType == POSITION_TYPE_BUY  && newTP < openPrice) ||
                    (posType == POSITION_TYPE_SELL  && newTP > openPrice);

   if(!posAtLoss)
   {
      //--- simply update TP and tag
      ModifyPositionTP(ticket, sl, newTP);
      Print("TP moved to SMA (no loss): ", newTP);
      return;
   }

   //--- Position is at a loss at the new TP.
   //--- Count current winning positions on same side to decide volume adjustment.
   int winningCount = CountWinningSidePositions(posType, oldTag, newTP);
   int prevWinCount = winningCount; // before this position's adjustment

   //--- If winning count would remain the same (i.e. this losing pos does not
   //    change the overall win count on the side), skip volume adjustment.
   //    The logic: winning count on the side excluding this ticket.
   int winningExcluding = CountWinningSidePositionsExcluding(posType, oldTag, newTP, ticket);
   if(winningExcluding == winningCount)
   {
      //--- Winning order count unchanged – skip volume adjustment
      ModifyPositionTP(ticket, sl, newTP);
      Print("TP moved to SMA (at loss) – vol unchanged, win count stable. TP: ", newTP);
      return;
   }

   //--- Volume adjustment needed: increase by factor
   double newVol = NormalizeVolume(currentVol * VolumeFactor);
   Print("Position at loss, adjusting volume from ", currentVol, " to ", newVol,
         " NewTP: ", newTP);

   //--- Close current position and re-open with new volume and new TP
   if(!trade.PositionClose(ticket))
   {
      Print("Failed to close position for volume adjustment: ", trade.ResultRetcode());
      return;
   }

   Sleep(200); // small pause for server to process

   string newComment = TradeComment + "_" + newTag;
   if(posType == POSITION_TYPE_BUY)
   {
      double price = SymbolInfoDouble(sym, SYMBOL_ASK);
      trade.Buy(newVol, sym, price, 0, newTP, newComment);
      Print("Reopened BUY with adjusted volume ", newVol, " TP: ", newTP);
   }
   else
   {
      double price = SymbolInfoDouble(sym, SYMBOL_BID);
      trade.Sell(newVol, sym, price, 0, newTP, newComment);
      Print("Reopened SELL with adjusted volume ", newVol, " TP: ", newTP);
   }
}

//+------------------------------------------------------------------+
//| Open an initial envelope TP trade                                |
//+------------------------------------------------------------------+
void OpenEnvelopeTrade(ENUM_ORDER_TYPE orderType, double tpLevel)
{
   double volume = NormalizeVolume(InitialLotSize);

   if(orderType == ORDER_TYPE_BUY)
   {
      double price   = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
      string comment = TradeComment + "_" + TAG_ENV_BUY;
      if(trade.Buy(volume, TradeSymbol, price, 0, tpLevel, comment))
         Print("Envelope BUY opened. Vol: ", volume, " TP: ", tpLevel);
      else
         Print("Envelope BUY failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
   else
   {
      double price   = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
      string comment = TradeComment + "_" + TAG_ENV_SELL;
      if(trade.Sell(volume, TradeSymbol, price, 0, tpLevel, comment))
         Print("Envelope SELL opened. Vol: ", volume, " TP: ", tpLevel);
      else
         Print("Envelope SELL failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Modify position TP (keep SL unchanged)                           |
//+------------------------------------------------------------------+
bool ModifyPositionTP(ulong ticket, double sl, double newTP)
{
   if(!trade.PositionModify(ticket, sl, newTP))
   {
      Print("ModifyPositionTP failed for ticket ", ticket,
            " retcode: ", trade.ResultRetcode(),
            " msg: ", trade.ResultRetcodeDescription());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Count winning positions on a side at a given TP level            |
//| "Winning" means TP is in profit direction from current price     |
//+------------------------------------------------------------------+
int CountWinningSidePositions(ENUM_POSITION_TYPE side, string tag, double tpLevel)
{
   return CountWinningSidePositionsExcluding(side, tag, tpLevel, 0);
}

int CountWinningSidePositionsExcluding(ENUM_POSITION_TYPE side, string tag,
                                        double tpLevel, ulong excludeTicket)
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != TradeSymbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)  != MagicNumber) continue;
      if(ticket == excludeTicket) continue;

      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(pt != side) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, tag) < 0) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      //--- A position is "winning at tpLevel" if TP is in profit relative to open
      bool winning = (side == POSITION_TYPE_BUY  && tpLevel > openPrice) ||
                     (side == POSITION_TYPE_SELL && tpLevel < openPrice);
      if(winning) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Normalize volume to symbol constraints                           |
//+------------------------------------------------------------------+
double NormalizeVolume(double volume)
{
   double minVol  = SymbolInfoDouble(TradeSymbol, SYMBOL_VOLUME_MIN);
   double maxVol  = SymbolInfoDouble(TradeSymbol, SYMBOL_VOLUME_MAX);
   double volStep = SymbolInfoDouble(TradeSymbol, SYMBOL_VOLUME_STEP);

   volume = MathRound(volume / volStep) * volStep;
   volume = MathMax(volume, minVol);
   volume = MathMin(volume, MathMin(maxVol, MaxLotSize));

   return NormalizeDouble(volume, 2);
}

//+------------------------------------------------------------------+
//| Helper – get SMA value at bar index                              |
//+------------------------------------------------------------------+
double GetSMA(int barIndex)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_smaHandle, 0, 0, barIndex + 1, buf) < barIndex + 1)
      return 0.0;
   return buf[barIndex];
}

//+------------------------------------------------------------------+
//| Helper – get Envelope upper band at bar index                    |
//+------------------------------------------------------------------+
double GetEnvUpper(int barIndex)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_envHandle, UPPER_LINE, 0, barIndex + 1, buf) < barIndex + 1)
      return 0.0;
   return buf[barIndex];
}

//+------------------------------------------------------------------+
//| Helper – get Envelope lower band at bar index                    |
//+------------------------------------------------------------------+
double GetEnvLower(int barIndex)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_envHandle, LOWER_LINE, 0, barIndex + 1, buf) < barIndex + 1)
      return 0.0;
   return buf[barIndex];
}
//+------------------------------------------------------------------+
