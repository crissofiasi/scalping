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
input double   InpMaxVolume        = 1.0;        // Maximum Trade Volume (0=disabled)
input int      InpMaxOpenPositions = 0;          // Max Open Positions Per Side (0=disabled)
input int      InpMagicNumber      = 123456;     // Magic Number
input string   InpTradeComment     = "EnvScalp"; // Trade Comment

//--- Global variables
CTrade trade;
int envelopeHandle;
double upperEnvBuffer[];
double lowerEnvBuffer[];
int lastBuyBar = 0;
int lastSellBar = 0;

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
   envelopeHandle = iEnvelopes(_Symbol, PERIOD_CURRENT, InpEnvelopePeriod, 0, 
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
   if(Bars(_Symbol, PERIOD_CURRENT) < 10)
      return;
   
   //--- Copy envelope data
   if(CopyBuffer(envelopeHandle, 0, 0, 4, upperEnvBuffer) <= 0)
      return;
   if(CopyBuffer(envelopeHandle, 1, 0, 4, lowerEnvBuffer) <= 0)
      return;
   
   //--- Get close prices for last 3 bars (completed bars only)
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1); // Most recent completed bar
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double close3 = iClose(_Symbol, PERIOD_CURRENT, 3); // Oldest bar in pattern
   
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
   //--- Check if already traded on this bar
   int currentBar = Bars(_Symbol, PERIOD_CURRENT);
   if(currentBar == lastBuyBar)
   {
      return; // Already traded Buy on this bar
   }
   
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
   
   //--- Check max open positions limit
   if(InpMaxOpenPositions > 0 && existingBuys >= InpMaxOpenPositions)
   {
      Print("Max open Buy positions reached (", InpMaxOpenPositions, "). Closing farthest position.");
      CloseFarthestBuyPosition();
      
      //--- Recalculate existing positions after closure
      existingBuys = 0;
      existingVolume = 0;
      existingOpenPrice = 0;
      totalProfit = 0;
      
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
               existingOpenPrice += posOpen * posVolume;
               totalProfit += (tp - posOpen) * posVolume;
            }
         }
      }
   }
   
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
            
            //--- If volume exceeds max, close farthest positions until it's below max
            while(InpMaxVolume > 0 && newVolume > InpMaxVolume && existingBuys > 0)
            {
               if(!CloseFarthestBuyPosition())
                  break;
               
               //--- Recalculate volume after closing position
               existingBuys = 0;
               existingVolume = 0;
               existingOpenPrice = 0;
               totalProfit = 0;
               
               for(int j = PositionsTotal() - 1; j >= 0; j--)
               {
                  if(PositionSelectByTicket(PositionGetTicket(j)))
                  {
                     if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
                        PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
                        PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                     {
                        existingBuys++;
                        double posVolume = PositionGetDouble(POSITION_VOLUME);
                        double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
                        existingVolume += posVolume;
                        existingOpenPrice += posOpen * posVolume;
                        totalProfit += (tp - posOpen) * posVolume;
                     }
                  }
               }
               
               if(existingBuys > 0)
               {
                  baseProfit = (tp - ask) * InpBaseLot;
                  requiredProfit = baseProfit - totalProfit;
                  
                  if(requiredProfit > 0 && (tp - ask) != 0)
                  {
                     newVolume = requiredProfit / (tp - ask);
                     newVolume = NormalizeLot(newVolume);
                  }
                  else
                  {
                     newVolume = InpBaseLot;
                  }
               }
               else
               {
                  newVolume = InpBaseLot;
               }
            }
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
      lastBuyBar = currentBar; // Mark this bar as traded
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
   //--- Check if already traded on this bar
   int currentBar = Bars(_Symbol, PERIOD_CURRENT);
   if(currentBar == lastSellBar)
   {
      return; // Already traded Sell on this bar
   }
   
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
   
   //--- Check max open positions limit
   if(InpMaxOpenPositions > 0 && existingSells >= InpMaxOpenPositions)
   {
      Print("Max open Sell positions reached (", InpMaxOpenPositions, "). Closing farthest position.");
      CloseFarthestSellPosition();
      
      //--- Recalculate existing positions after closure
      existingSells = 0;
      existingVolume = 0;
      existingOpenPrice = 0;
      totalProfit = 0;
      
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
               existingOpenPrice += posOpen * posVolume;
               totalProfit += (posOpen - tp) * posVolume;
            }
         }
      }
   }
   
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
            
            //--- If volume exceeds max, close farthest positions until it's below max
            while(InpMaxVolume > 0 && newVolume > InpMaxVolume && existingSells > 0)
            {
               if(!CloseFarthestSellPosition())
                  break;
               
               //--- Recalculate volume after closing position
               existingSells = 0;
               existingVolume = 0;
               existingOpenPrice = 0;
               totalProfit = 0;
               
               for(int j = PositionsTotal() - 1; j >= 0; j--)
               {
                  if(PositionSelectByTicket(PositionGetTicket(j)))
                  {
                     if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
                        PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
                        PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                     {
                        existingSells++;
                        double posVolume = PositionGetDouble(POSITION_VOLUME);
                        double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
                        existingVolume += posVolume;
                        existingOpenPrice += posOpen * posVolume;
                        totalProfit += (posOpen - tp) * posVolume;
                     }
                  }
               }
               
               if(existingSells > 0)
               {
                  baseProfit = (bid - tp) * InpBaseLot;
                  requiredProfit = baseProfit - totalProfit;
                  
                  if(requiredProfit > 0 && (bid - tp) != 0)
                  {
                     newVolume = requiredProfit / (bid - tp);
                     newVolume = NormalizeLot(newVolume);
                  }
                  else
                  {
                     newVolume = InpBaseLot;
                  }
               }
               else
               {
                  newVolume = InpBaseLot;
               }
            }
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
      lastSellBar = currentBar; // Mark this bar as traded
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
//| Close farthest Buy position (earliest opening price)            |
//+------------------------------------------------------------------+
bool CloseFarthestBuyPosition()
{
   ulong oldestTicket = 0;
   double oldestOpenPrice = 0;
   datetime oldestOpenTime = D'2099.12.31';
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(openTime < oldestOpenTime)
            {
               oldestOpenTime = openTime;
               oldestTicket = ticket;
               oldestOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            }
         }
      }
   }
   
   if(oldestTicket > 0)
   {
      if(trade.PositionClose(oldestTicket))
      {
         Print("Closed farthest Buy position #", oldestTicket, " opened at ", oldestOpenPrice);
         return true;
      }
      else
      {
         Print("Failed to close Buy position #", oldestTicket, ": ", trade.ResultRetcodeDescription());
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Close farthest Sell position (earliest opening price)           |
//+------------------------------------------------------------------+
bool CloseFarthestSellPosition()
{
   ulong oldestTicket = 0;
   double oldestOpenPrice = 0;
   datetime oldestOpenTime = D'2099.12.31';
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(openTime < oldestOpenTime)
            {
               oldestOpenTime = openTime;
               oldestTicket = ticket;
               oldestOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            }
         }
      }
   }
   
   if(oldestTicket > 0)
   {
      if(trade.PositionClose(oldestTicket))
      {
         Print("Closed farthest Sell position #", oldestTicket, " opened at ", oldestOpenPrice);
         return true;
      }
      else
      {
         Print("Failed to close Sell position #", oldestTicket, ": ", trade.ResultRetcodeDescription());
      }
   }
   
   return false;
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
