//+------------------------------------------------------------------+
//|                                        EnvelopeScalperSmart.mq5 |
//|                                  Smart Envelope Scalping EA     |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Scalping EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Envelope Settings ==="
input int      InpEnvelopePeriod    = 15;        // Envelope Period
input double   InpEnvelopeDeviation = 0.05;      // Envelope Deviation (%)
input ENUM_MA_METHOD InpEnvelopeMethod = MODE_EMA; // Envelope MA Method

input group "=== Signal Settings ==="
input double   InpMaxInsideDistance = 0.0010;    // Max distance between inside closes (in price)

input group "=== Trading Settings ==="
input double   InpBaseLot          = 0.01;       // Base Lot Size
input int      InpMagicNumber      = 123456;     // Magic Number
input string   InpTradeComment     = "EnvScalp"; // Trade Comment

//--- Global variables
CTrade trade;
int envelopeHandle;
double upperEnvBuffer[];
double lowerEnvBuffer[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set trade parameters
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);
   
   //--- Create Envelopes indicator
   envelopeHandle = iEnvelopes(_Symbol, PERIOD_M1, InpEnvelopePeriod, 0, 
                                InpEnvelopeMethod, PRICE_CLOSE, InpEnvelopeDeviation);
   
   if(envelopeHandle == INVALID_HANDLE)
   {
      Print("Error creating Envelopes indicator: ", GetLastError());
      return(INIT_FAILED);
   }
   
   //--- Set buffer arrays as series
   ArraySetAsSeries(upperEnvBuffer, true);
   ArraySetAsSeries(lowerEnvBuffer, true);
   
   Print("EnvelopeScalperSmart initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handle
   if(envelopeHandle != INVALID_HANDLE)
      IndicatorRelease(envelopeHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check if we have enough bars
   if(Bars(_Symbol, PERIOD_M1) < 10)
      return;
   
   //--- Copy envelope data
   if(CopyBuffer(envelopeHandle, 0, 0, 4, upperEnvBuffer) <= 0)
      return;
   if(CopyBuffer(envelopeHandle, 1, 0, 4, lowerEnvBuffer) <= 0)
      return;
   
   //--- Get close prices for last 3 bars (completed bars only)
   double close1 = iClose(_Symbol, PERIOD_M1, 1); // Most recent completed bar
   double close2 = iClose(_Symbol, PERIOD_M1, 2);
   double close3 = iClose(_Symbol, PERIOD_M1, 3); // Oldest bar in pattern
   
   //--- Check for signal
   int signal = CheckSignal(close3, close2, close1);
   
   if(signal == 1) // Buy signal
   {
      ExecuteBuyTrade();
   }
   else if(signal == -1) // Sell signal
   {
      ExecuteSellTrade();
   }
}

//+------------------------------------------------------------------+
//| Check for trading signal                                         |
//| Returns: 1 = Buy, -1 = Sell, 0 = No signal                      |
//+------------------------------------------------------------------+
int CheckSignal(double close3, double close2, double close1)
{
   //--- Check if bar3 was outside envelope
   bool bar3Outside = (close3 > upperEnvBuffer[3]) || (close3 < lowerEnvBuffer[3]);
   if(!bar3Outside)
      return 0;
   
   //--- Check if bar2 and bar1 are inside envelope
   bool bar2Inside = (close2 <= upperEnvBuffer[2]) && (close2 >= lowerEnvBuffer[2]);
   bool bar1Inside = (close1 <= upperEnvBuffer[1]) && (close1 >= lowerEnvBuffer[1]);
   
   if(!bar2Inside || !bar1Inside)
      return 0;
   
   //--- Check distance between inside closes
   double distance = MathAbs(close2 - close1);
   if(distance > InpMaxInsideDistance)
      return 0;
   
   //--- Determine signal direction
   if(close3 < lowerEnvBuffer[3]) // Was below, now reverting up -> Buy
      return 1;
   else if(close3 > upperEnvBuffer[3]) // Was above, now reverting down -> Sell
      return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| Execute Buy Trade                                                |
//+------------------------------------------------------------------+
void ExecuteBuyTrade()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tp = upperEnvBuffer[0]; // TP at opposite (upper) level
   
   //--- Get existing buy positions
   int existingBuys = 0;
   double existingVolume = 0;
   double existingOpenPrice = 0;
   double totalProfit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            existingBuys++;
            double posVolume = PositionGetDouble(POSITION_VOLUME);
            double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
            existingVolume += posVolume;
            
            //--- Calculate profit at new TP
            double profitAtNewTP = (tp - posOpen) * posVolume;
            totalProfit += profitAtNewTP;
            
            //--- Store for average calculation
            existingOpenPrice += posOpen * posVolume;
         }
      }
   }
   
   double newVolume = InpBaseLot;
   
   //--- Apply smart martingale if there are existing positions
   if(existingBuys > 0)
   {
      double avgOpenPrice = existingOpenPrice / existingVolume;
      
      //--- Check if existing positions are losing at new TP
      double avgProfitAtTP = (tp - avgOpenPrice) * existingVolume;
      
      if(avgProfitAtTP < 0 || totalProfit < 0)
      {
         //--- Calculate required volume so total profit = base lot profit
         double baseProfit = (tp - ask) * InpBaseLot;
         double requiredProfit = baseProfit - totalProfit;
         
         if(requiredProfit > 0 && (tp - ask) != 0)
         {
            newVolume = requiredProfit / (tp - ask);
            newVolume = NormalizeLot(newVolume);
         }
      }
      
      //--- Adjust all existing TPs to new TP
      AdjustBuyTakeProfits(tp);
   }
   
   //--- Normalize volume
   newVolume = NormalizeLot(newVolume);
   
   //--- Open position
   if(trade.Buy(newVolume, _Symbol, ask, 0, tp, InpTradeComment))
   {
      Print("Buy order executed: Volume=", newVolume, " TP=", tp);
   }
   else
   {
      Print("Buy order failed: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Execute Sell Trade                                               |
//+------------------------------------------------------------------+
void ExecuteSellTrade()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tp = lowerEnvBuffer[0]; // TP at opposite (lower) level
   
   //--- Get existing sell positions
   int existingSells = 0;
   double existingVolume = 0;
   double existingOpenPrice = 0;
   double totalProfit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            existingSells++;
            double posVolume = PositionGetDouble(POSITION_VOLUME);
            double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
            existingVolume += posVolume;
            
            //--- Calculate profit at new TP
            double profitAtNewTP = (posOpen - tp) * posVolume;
            totalProfit += profitAtNewTP;
            
            //--- Store for average calculation
            existingOpenPrice += posOpen * posVolume;
         }
      }
   }
   
   double newVolume = InpBaseLot;
   
   //--- Apply smart martingale if there are existing positions
   if(existingSells > 0)
   {
      double avgOpenPrice = existingOpenPrice / existingVolume;
      
      //--- Check if existing positions are losing at new TP
      double avgProfitAtTP = (avgOpenPrice - tp) * existingVolume;
      
      if(avgProfitAtTP < 0 || totalProfit < 0)
      {
         //--- Calculate required volume so total profit = base lot profit
         double baseProfit = (bid - tp) * InpBaseLot;
         double requiredProfit = baseProfit - totalProfit;
         
         if(requiredProfit > 0 && (bid - tp) != 0)
         {
            newVolume = requiredProfit / (bid - tp);
            newVolume = NormalizeLot(newVolume);
         }
      }
      
      //--- Adjust all existing TPs to new TP
      AdjustSellTakeProfits(tp);
   }
   
   //--- Normalize volume
   newVolume = NormalizeLot(newVolume);
   
   //--- Open position
   if(trade.Sell(newVolume, _Symbol, bid, 0, tp, InpTradeComment))
   {
      Print("Sell order executed: Volume=", newVolume, " TP=", tp);
   }
   else
   {
      Print("Sell order failed: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Adjust all Buy positions' Take Profit                           |
//+------------------------------------------------------------------+
void AdjustBuyTakeProfits(double newTP)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            double currentTP = PositionGetDouble(POSITION_TP);
            if(MathAbs(currentTP - newTP) > _Point) // Only modify if different
            {
               double sl = PositionGetDouble(POSITION_SL);
               trade.PositionModify(ticket, sl, newTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Adjust all Sell positions' Take Profit                          |
//+------------------------------------------------------------------+
void AdjustSellTakeProfits(double newTP)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            double currentTP = PositionGetDouble(POSITION_TP);
            if(MathAbs(currentTP - newTP) > _Point) // Only modify if different
            {
               double sl = PositionGetDouble(POSITION_SL);
               trade.PositionModify(ticket, sl, newTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Normalize lot size                                              |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   lot = MathRound(lot / stepLot) * stepLot;
   
   return lot;
}
//+------------------------------------------------------------------+
