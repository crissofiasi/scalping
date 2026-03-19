//+------------------------------------------------------------------+
//|                                     NRTRScalpingEA_Flip.mq5     |
//|                                  Copyright 2026, Cris Trading  |
//|                                                                  |
//|  Flip-to-flip NRTR EA:                                           |
//|  - Uses NRTR Channel (iCustom) trend buffer (1/-1)              |
//|  - On trend flip, closes existing EA trades and opens opposite  |
//|  - Martingale: after loss multiply by FactorUp; after profit     |
//|    divide by FactorDown                                          |
//|  - No SL/TP                                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Cris Trading"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//--- Inputs ---------------------------------------------------------
input group "=== NRTR Settings ==="
input string         NRTRPath         = "Indicators\\Free Indicators\\NRTR Channel"; // iCustom path
input int            NRTR_ATRPeriod   = 14;    // inpATRPeriod
input double         NRTR_KATR        = 2.0;   // inpKATR
input int            TrendBufferIndex = 0;     // buffer with 1/-1 trend
input int            FlipShift        = 1;     // 0=current bar, 1=closed bar

input group "=== Trade Settings ==="
input double StartLot    = 0.01; // Minimum lot size
input double FactorUp    = 1.5;  // Multiply lot after loss
input double FactorDown  = 1.5;  // Divide lot after profit
input double MaxLot      = 10.0; // Max lot cap
input long   MagicNumber = 88901;
input int    Slippage    = 50;
input string TradeComment = "NRTRFlip";

//--- State
int    g_nrtrHandle = INVALID_HANDLE;
CTrade trade;

double g_nextLot = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_nrtrHandle = iCustom(_Symbol, _Period, NRTRPath, NRTR_ATRPeriod, NRTR_KATR);
   if(g_nrtrHandle == INVALID_HANDLE)
   {
      Print("NRTR handle failed: ", GetLastError());
      return INIT_FAILED;
   }

   g_nextLot = NormalizeVolume(StartLot);

   double vol = GetOpenPositionVolume();
   if(vol > 0.0)
      g_nextLot = NormalizeVolume(vol);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_nrtrHandle != INVALID_HANDLE)
      IndicatorRelease(g_nrtrHandle);
}

//+------------------------------------------------------------------+
//| Expert tick                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   int dirNow = 0;
   int dirPrev = 0;
   if(!GetTrendAtShift(FlipShift, dirNow)) return;
   if(!GetTrendAtShift(FlipShift + 1, dirPrev)) return;

   if(dirNow == 0 || dirPrev == 0) return;
   if(dirNow == dirPrev) return;

   //--- Flip detected: close existing and open new in dirNow
   double realized = CloseAllEATrades();
   UpdateNextLot(realized);

   OpenTradeInDir(dirNow);
}

//+------------------------------------------------------------------+
//| Read NRTR trend (1/-1) from buffer                               |
//+------------------------------------------------------------------+
bool GetTrendAtShift(int shift, int &dir)
{
   if(g_nrtrHandle == INVALID_HANDLE) return false;
   double buf[];
   if(CopyBuffer(g_nrtrHandle, TrendBufferIndex, shift, 1, buf) != 1)
      return false;

   double v = buf[0];
   if(v > 0.0) dir = 1;
   else if(v < 0.0) dir = -1;
   else dir = 0;

   return true;
}

//+------------------------------------------------------------------+
//| Open trade in direction (1=BUY, -1=SELL)                         |
//+------------------------------------------------------------------+
void OpenTradeInDir(int dir)
{
   double vol = NormalizeVolume(g_nextLot);
   if(vol < StartLot) vol = NormalizeVolume(StartLot);
   if(MaxLot > 0.0 && vol > MaxLot) vol = NormalizeVolume(MaxLot);

   bool ok = (dir == 1)
             ? trade.Buy(vol, _Symbol, 0, 0, 0, TradeComment)
             : trade.Sell(vol, _Symbol, 0, 0, 0, TradeComment);

   if(!ok)
      Print("Open failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Close all EA trades and return realized P/L                      |
//+------------------------------------------------------------------+
double CloseAllEATrades()
{
   double realized = 0.0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t))                        continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;

      double pl = PositionGetDouble(POSITION_PROFIT)
                + PositionGetDouble(POSITION_SWAP)
                + PositionGetDouble(POSITION_COMMISSION);

      if(!trade.PositionClose(t, Slippage))
         Print("Close failed ticket ", t, ": ", trade.ResultRetcode());
      else
         realized += pl;
   }
   return realized;
}

//+------------------------------------------------------------------+
//| Update next lot based on realized P/L                            |
//+------------------------------------------------------------------+
void UpdateNextLot(double realized)
{
   if(realized < 0.0)
      g_nextLot = g_nextLot * FactorUp;
   else if(realized > 0.0)
      g_nextLot = g_nextLot / FactorDown;

   if(g_nextLot < StartLot) g_nextLot = StartLot;
   if(MaxLot > 0.0 && g_nextLot > MaxLot) g_nextLot = MaxLot;

   g_nextLot = NormalizeVolume(g_nextLot);
}

//+------------------------------------------------------------------+
//| Get volume of any open EA position                               |
//+------------------------------------------------------------------+
double GetOpenPositionVolume()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t))                        continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;

      return PositionGetDouble(POSITION_VOLUME);
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| Normalize lot to symbol step / min / max                         |
//+------------------------------------------------------------------+
double NormalizeVolume(double vol)
{
   double minVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(volStep > 0.0)
      vol = MathRound(vol / volStep) * volStep;

   vol = MathMax(vol, minVol);
   if(MaxLot > 0.0)
      maxVol = MathMin(maxVol, MaxLot);
   vol = MathMin(vol, maxVol);

   return NormalizeDouble(vol, 2);
}
//+------------------------------------------------------------------+
