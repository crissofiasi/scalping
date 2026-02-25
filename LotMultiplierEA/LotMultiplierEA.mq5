//+------------------------------------------------------------------+
//|                                             LotMultiplierEA.mq5 |
//|                                  Copyright 2026, Cris Trading   |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Cris Trading"
#property link      ""
#property version   "1.00"
#property strict

//--- Input parameters
enum ENUM_MULTIPLICATION_TYPE
{
   MULT_PROPORTIONAL = 0,  // Proportional (based on provider balance)
   MULT_CLASSIC = 1,       // Classic (simple factor)
   MULT_FIXED = 2          // Fixed volume
};

input group "=== Multiplication Settings ==="
input ENUM_MULTIPLICATION_TYPE MultiplicationType = MULT_CLASSIC;  // Multiplication Type
input double Factor = 1.0;                                         // Factor (for Proportional/Classic)
input double ProviderBalance = 10000.0;                           // Provider Balance (for Proportional)
input double FixedVolume = 0.1;                                   // Fixed Volume (for Fixed type)
input double MinNewVolume = 0.01;                                 // Minimum New Volume to Open

input group "=== Trade Settings ==="
input string ProviderComment = "CopyTrade";                       // Provider Trade Comment (to identify)
input int ProviderMagicNumber = 0;                               // Provider Magic Number (0 = any)
input int OurMagicNumber = 123456;                               // Our Magic Number
input int Slippage = 10;                                         // Slippage in points
input string TradeComment = "LotMultiplier";                     // Comment for our trades

input group "=== Risk Settings ==="
input bool UseStopLoss = false;                                  // Use Stop Loss
input double StopLossPips = 50.0;                                // Stop Loss in pips
input bool UseTakeProfit = false;                                // Use Take Profit
input double TakeProfitPips = 100.0;                             // Take Profit in pips

//--- Global variables
struct TradeInfo
{
   ulong ticket;
   double volume;
   datetime time;
};
TradeInfo processedTrades[];  // Keep track of processed provider trades

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("LotMultiplierEA initialized");
   Print("Multiplication Type: ", EnumToString(MultiplicationType));
   Print("Factor: ", Factor);
   Print("Min New Volume: ", MinNewVolume);
   
   // Initialize processed trades array
   ArrayResize(processedTrades, 0);
   
   // Check current positions on startup
   CheckExistingPositions();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("LotMultiplierEA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new provider trades on every tick for immediate detection
   CheckForNewProviderTrades();
}

//+------------------------------------------------------------------+
//| Check existing positions on startup                              |
//+------------------------------------------------------------------+
void CheckExistingPositions()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(IsProviderPosition(ticket))
         {
            // Add to processed trades
            AddProcessedTrade(ticket, PositionGetDouble(POSITION_VOLUME), (datetime)PositionGetInteger(POSITION_TIME));
            
            // Check if we need to open complementary trade
            ProcessProviderPosition(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for new provider trades                                    |
//+------------------------------------------------------------------+
void CheckForNewProviderTrades()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(IsProviderPosition(ticket))
         {
            if(!IsTradeProcessed(ticket))
            {
               Print("New provider trade detected: ", ticket);
               AddProcessedTrade(ticket, PositionGetDouble(POSITION_VOLUME), (datetime)PositionGetInteger(POSITION_TIME));
               ProcessProviderPosition(ticket);
            }
         }
      }
   }
   
   // Clean up closed positions from processed trades
   CleanupProcessedTrades();
}

//+------------------------------------------------------------------+
//| Check if position is from provider                               |
//+------------------------------------------------------------------+
bool IsProviderPosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   
   string symbol = PositionGetString(POSITION_SYMBOL);
   long magic = PositionGetInteger(POSITION_MAGIC);
   string comment = PositionGetString(POSITION_COMMENT);
   
   // If our magic number, it's our position
   if(magic == OurMagicNumber)
      return false;
   
   // Check magic number filter
   if(ProviderMagicNumber != 0 && magic != ProviderMagicNumber)
      return false;
   
   // Check comment filter
   if(ProviderComment != "" && StringFind(comment, ProviderComment) < 0)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if trade already processed                                 |
//+------------------------------------------------------------------+
bool IsTradeProcessed(ulong ticket)
{
   for(int i = 0; i < ArraySize(processedTrades); i++)
   {
      if(processedTrades[i].ticket == ticket)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Add trade to processed list                                      |
//+------------------------------------------------------------------+
void AddProcessedTrade(ulong ticket, double volume, datetime time)
{
   int size = ArraySize(processedTrades);
   ArrayResize(processedTrades, size + 1);
   processedTrades[size].ticket = ticket;
   processedTrades[size].volume = volume;
   processedTrades[size].time = time;
}

//+------------------------------------------------------------------+
//| Clean up closed positions from processed trades                  |
//+------------------------------------------------------------------+
void CleanupProcessedTrades()
{
   for(int i = ArraySize(processedTrades) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(processedTrades[i].ticket))
      {
         // Position closed, remove from array
         ArrayRemove(processedTrades, i, 1);
      }
   }
}

//+------------------------------------------------------------------+
//| Check if complementary trade already exists for provider ticket  |
//+------------------------------------------------------------------+
bool HasComplementaryTrade(ulong providerTicket)
{
   string searchComment = "[" + IntegerToString(providerTicket) + "]";
   
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         long magic = PositionGetInteger(POSITION_MAGIC);
         string comment = PositionGetString(POSITION_COMMENT);
         
         // Check if this is our complementary trade
         if(magic == OurMagicNumber && StringFind(comment, searchComment) >= 0)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Process provider position and open complementary trade           |
//+------------------------------------------------------------------+
void ProcessProviderPosition(ulong providerTicket)
{
   if(!PositionSelectByTicket(providerTicket))
   {
      Print("Error: Cannot select provider position ", providerTicket);
      return;
   }
   
   // Check if we already have a complementary trade for this provider position
   if(HasComplementaryTrade(providerTicket))
   {
      Print("Complementary trade already exists for provider ticket ", providerTicket, ". Skipping.");
      return;
   }
   
   string symbol = PositionGetString(POSITION_SYMBOL);
   double providerVolume = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE providerType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   
   // Calculate total volume based on multiplication type
   double totalVolume = CalculateTotalVolume(providerVolume);
   
   Print("Provider Volume: ", providerVolume, " Total Volume: ", totalVolume);
   
   // Calculate new volume needed
   double newVolume = totalVolume - providerVolume;
   
   Print("New Volume to open: ", newVolume);
   
   // Check minimum volume threshold
   if(MathAbs(newVolume) < MinNewVolume)
   {
      Print("New volume ", MathAbs(newVolume), " is below minimum ", MinNewVolume, ". No trade opened.");
      return;
   }
   
   // Determine direction and volume
   ENUM_ORDER_TYPE orderType;
   double volumeToOpen = MathAbs(newVolume);
   
   if(newVolume > 0)
   {
      // Same direction as provider
      orderType = (providerType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   }
   else
   {
      // Opposite direction
      orderType = (providerType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   }
   
   // Normalize volume
   volumeToOpen = NormalizeVolume(symbol, volumeToOpen);
   
   if(volumeToOpen < SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN))
   {
      Print("Volume ", volumeToOpen, " is below minimum for symbol ", symbol);
      return;
   }
   
   // Open complementary trade
   OpenTrade(symbol, orderType, volumeToOpen, providerTicket);
}

//+------------------------------------------------------------------+
//| Calculate total volume based on multiplication type              |
//+------------------------------------------------------------------+
double CalculateTotalVolume(double providerVolume)
{
   double totalVolume = 0.0;
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   switch(MultiplicationType)
   {
      case MULT_PROPORTIONAL:
         // totalVolume = providerVolume * (account balance * factor) / provider balance
         if(ProviderBalance > 0)
         {
            totalVolume = providerVolume * (accountBalance * Factor) / ProviderBalance;
         }
         else
         {
            Print("Error: Provider balance is zero or negative");
            totalVolume = providerVolume;
         }
         break;
         
      case MULT_CLASSIC:
         // totalVolume = providerVolume * factor
         totalVolume = providerVolume * Factor;
         break;
         
      case MULT_FIXED:
         // totalVolume is fixed
         totalVolume = FixedVolume;
         break;
         
      default:
         totalVolume = providerVolume;
         break;
   }
   
   return totalVolume;
}

//+------------------------------------------------------------------+
//| Normalize volume according to symbol requirements                |
//+------------------------------------------------------------------+
double NormalizeVolume(string symbol, double volume)
{
   double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   // Round to volume step
   volume = MathRound(volume / volumeStep) * volumeStep;
   
   // Clamp to min/max
   if(volume < minVolume) volume = minVolume;
   if(volume > maxVolume) volume = maxVolume;
   
   return NormalizeDouble(volume, 2);
}

//+------------------------------------------------------------------+
//| Open trade                                                        |
//+------------------------------------------------------------------+
bool OpenTrade(string symbol, ENUM_ORDER_TYPE orderType, double volume, ulong providerTicket)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.volume = volume;
   request.type = orderType;
   request.magic = OurMagicNumber;
   request.comment = TradeComment + " [" + IntegerToString(providerTicket) + "]";
   request.deviation = Slippage;
   
   // Set price
   if(orderType == ORDER_TYPE_BUY)
   {
      request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      request.type_filling = ORDER_FILLING_FOK;
      
      // Set SL/TP
      if(UseStopLoss)
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         request.sl = NormalizeDouble(request.price - StopLossPips * 10 * point, digits);
      }
      if(UseTakeProfit)
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         request.tp = NormalizeDouble(request.price + TakeProfitPips * 10 * point, digits);
      }
   }
   else
   {
      request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
      request.type_filling = ORDER_FILLING_FOK;
      
      // Set SL/TP
      if(UseStopLoss)
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         request.sl = NormalizeDouble(request.price + StopLossPips * 10 * point, digits);
      }
      if(UseTakeProfit)
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         request.tp = NormalizeDouble(request.price - TakeProfitPips * 10 * point, digits);
      }
   }
   
   // Send order
   bool sent = OrderSend(request, result);
   
   if(sent && result.retcode == TRADE_RETCODE_DONE)
   {
      Print("Trade opened successfully: ", result.order, " Volume: ", volume, " Type: ", EnumToString(orderType));
      return true;
   }
   else
   {
      Print("Error opening trade: ", result.retcode, " - ", result.comment);
      return false;
   }
}

//+------------------------------------------------------------------+
