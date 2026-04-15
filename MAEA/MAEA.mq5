//+------------------------------------------------------------------+
//|                                                       MAEA.mq5   |
//|                                  Copyright 2026, Cris Trading    |
//|                                                                  |
//|  Strategy:                                                       |
//|  1. MA cross entry: when a bar closes on the other side of the   |
//|     MA, open a position in that direction (above MA = BUY,       |
//|     below MA = SELL). Both directions allowed simultaneously.    |
//|  2. On each new bar, close positions that are in profit.         |
//|  3. SL is fixed in points.                                       |
//|  4. Martingale: after a loss, increase lot by LotIncreaseFactor; |
//|     after a profit, decrease lot by LotDecreaseFactor.           |
//|     Lot capped between BaseLotSize and MaxLotSize.               |
//|  5. MagicNumber auto-calculated from Symbol + Timeframe.         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Cris Trading"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input parameters -----------------------------------------------
input group "=== MA Signal ==="
input int              MA_Period   = 20;          // MA period
input ENUM_MA_METHOD   MA_Method   = MODE_EMA;    // MA method (EMA, SMA, SMMA, LWMA)
input ENUM_TIMEFRAMES  TimeFrame   = PERIOD_CURRENT; // Timeframe for MA

input group "=== Trade Settings ==="
input double BaseLotSize    = 0.01;    // Base (minimum) lot size
input double BaseEquity     = 0.0;     // Equity reference for lot scaling (0 = off)
input double FixedSL        = 300.0;   // Fixed SL in points
input int    Slippage       = 50;      // Slippage in points
input string TradeComment   = "MAEA";  // Trade comment

input group "=== Martingale ==="
input bool   EnableMartingale    = true;   // Enable martingale lot sizing
input double LotIncreaseFactor   = 1.5;    // Multiply lot by this after a loss
input double LotDecreaseFactor   = 0.75;   // Multiply lot by this after a profit
input double MaxLotSize          = 1.0;    // Maximum lot size cap

//--- Globals --------------------------------------------------------
int      g_maHandle     = INVALID_HANDLE;
datetime g_lastBarTime  = 0;
long     g_magicNumber  = 0;
CTrade   trade;

//+------------------------------------------------------------------+
//| Generate a unique magic number from Symbol + Timeframe           |
//+------------------------------------------------------------------+
long CalcMagicNumber()
{
   string seed = _Symbol + IntegerToString((int)TimeFrame);
   long hash = 0;
   for(int i = 0; i < StringLen(seed); i++)
   {
      hash = hash * 31 + (long)StringGetCharacter(seed, i);
   }
   // Ensure positive and within int range
   if(hash < 0) hash = -hash;
   return hash % 2147483647;
}

//+------------------------------------------------------------------+
//| Normalize volume to symbol constraints                           |
//+------------------------------------------------------------------+
double NormalizeVolume(double vol)
{
   double minVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(stepVol <= 0) stepVol = 0.01;
   vol = MathFloor(vol / stepVol) * stepVol;
   vol = MathMax(vol, minVol);
   vol = MathMin(vol, maxVol);
   vol = MathMin(vol, MaxLotSize);
   return NormalizeDouble(vol, 2);
}

//+------------------------------------------------------------------+
//| Calculate scaled lot based on equity                             |
//+------------------------------------------------------------------+
double CalcScaledLot()
{
   if(BaseEquity <= 0.0) return BaseLotSize;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double scaled = BaseLotSize * equity / BaseEquity;
   return MathMax(scaled, BaseLotSize);
}

//+------------------------------------------------------------------+
//| Get the next lot size based on the last closed trade (any dir)   |
//| Uses the most recent closed order regardless of direction.       |
//+------------------------------------------------------------------+
double GetMartingaleLot()
{
   double baseLot = CalcScaledLot();

   if(!EnableMartingale)
      return NormalizeVolume(baseLot);

   // Search history for most recent closed trade (any direction)
   if(!HistorySelect(0, TimeCurrent()))
      return NormalizeVolume(baseLot);

   int total = HistoryDealsTotal();
   // Walk backwards to find last closed deal matching magic
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      long dealMagic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(dealMagic != g_magicNumber) continue;

      string dealSymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      if(dealSymbol != _Symbol) continue;

      long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT) continue;

      // Found the last closed deal
      double prevLot    = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double dealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                        + HistoryDealGetDouble(ticket, DEAL_SWAP)
                        + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      double newLot;
      if(dealProfit < 0.0)
         newLot = prevLot * LotIncreaseFactor;    // loss → increase
      else
         newLot = prevLot * LotDecreaseFactor;    // profit → decrease

      // Clamp
      newLot = MathMax(newLot, baseLot);
      newLot = MathMin(newLot, MaxLotSize);
      return NormalizeVolume(newLot);
   }

   // No history found → use base lot
   return NormalizeVolume(baseLot);
}

//+------------------------------------------------------------------+
//| Count open positions for a given direction (1=BUY, -1=SELL)      |
//+------------------------------------------------------------------+
int CountPositions(int direction)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != g_magicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long posType = PositionGetInteger(POSITION_TYPE);
      if(direction == 1  && posType == POSITION_TYPE_BUY)  count++;
      if(direction == -1 && posType == POSITION_TYPE_SELL) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Close all profitable positions                                   |
//+------------------------------------------------------------------+
void CloseAllProfitablePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != g_magicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double profit = PositionGetDouble(POSITION_PROFIT)
                    + PositionGetDouble(POSITION_SWAP);
      if(profit > 0.0)
      {
         trade.PositionClose(ticket, Slippage);
         Print("Closed profitable position #", ticket, " profit=", DoubleToString(profit, 2));
      }
   }
}

//+------------------------------------------------------------------+
//| Open a position: dir = 1 (BUY) or -1 (SELL)                     |
//+------------------------------------------------------------------+
bool OpenPosition(int dir)
{
   double lot   = GetMartingaleLot();
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) point = 0.00001;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double price, sl;
   ENUM_ORDER_TYPE orderType;

   if(dir == 1) // BUY
   {
      price     = ask;
      sl        = NormalizeDouble(price - FixedSL * point, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      orderType = ORDER_TYPE_BUY;
   }
   else // SELL
   {
      price     = bid;
      sl        = NormalizeDouble(price + FixedSL * point, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      orderType = ORDER_TYPE_SELL;
   }

   string comment = TradeComment + (dir == 1 ? "_BUY" : "_SELL");

   bool result = trade.PositionOpen(_Symbol, orderType, lot, price, sl, 0.0, comment);
   if(result)
      Print("Opened ", (dir == 1 ? "BUY" : "SELL"), " lot=", DoubleToString(lot, 2),
            " price=", DoubleToString(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
            " SL=", DoubleToString(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)));
   else
      Print("Failed to open ", (dir == 1 ? "BUY" : "SELL"), " error=", GetLastError());

   return result;
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_magicNumber = CalcMagicNumber();
   trade.SetExpertMagicNumber(g_magicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   ENUM_TIMEFRAMES tf = (TimeFrame == PERIOD_CURRENT) ? _Period : TimeFrame;

   g_maHandle = iMA(_Symbol, tf, MA_Period, 0, MA_Method, PRICE_CLOSE);
   if(g_maHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create MA indicator handle.");
      return INIT_FAILED;
   }

   Print("MAEA initialized.  Symbol=", _Symbol,
         "  TF=", EnumToString(tf),
         "  MA=", MA_Period, " ", EnumToString(MA_Method),
         "  SL=", FixedSL, " pts",
         "  Magic=", g_magicNumber,
         "  Martingale=", EnableMartingale ? "ON" : "OFF");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_maHandle != INVALID_HANDLE)
      IndicatorRelease(g_maHandle);
}

//+------------------------------------------------------------------+
//| Expert tick                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Detect new bar on the chosen timeframe
   ENUM_TIMEFRAMES tf = (TimeFrame == PERIOD_CURRENT) ? _Period : TimeFrame;

   datetime barTimes[];
   if(CopyTime(_Symbol, tf, 0, 2, barTimes) < 2) return;

   datetime currentBarTime = barTimes[1]; // last CLOSED bar time

   if(currentBarTime == g_lastBarTime) return; // same bar, skip
   g_lastBarTime = currentBarTime;

   //--- 1. Close all profitable positions on new bar
   CloseAllProfitablePositions();

   //--- 2. Read MA value for the last closed bar
   double maValues[];
   if(CopyBuffer(g_maHandle, 0, 1, 1, maValues) < 1) return;
   double maValue = maValues[0];

   //--- 3. Read close of last completed bar
   double closes[];
   if(CopyClose(_Symbol, tf, 1, 1, closes) < 1) return;
   double barClose = closes[0];

   //--- 4. Determine signal
   int signal = 0;
   if(barClose > maValue) signal = 1;   // closed above MA → BUY
   if(barClose < maValue) signal = -1;  // closed below MA → SELL

   if(signal == 0) return; // close exactly on MA → no trade

   //--- 5. Open position if none in that direction
   if(CountPositions(signal) == 0)
   {
      OpenPosition(signal);
   }
}
//+------------------------------------------------------------------+
