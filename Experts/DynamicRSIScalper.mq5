//+------------------------------------------------------------------+
//|                                          DynamicRSIScalper.mq5   |
//|                                    Advanced Scalping EA with     |
//|                                    Zero Hardcoding Architecture  |
//+------------------------------------------------------------------+
#property copyright "Dynamic RSI Scalper"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_CURVE_TYPE
{
   CURVE_LINEAR,      // Linear
   CURVE_EXPONENTIAL, // Exponential
   CURVE_LOGARITHMIC  // Logarithmic
};

enum ENUM_DISTANCE_CALC
{
   DISTANCE_NEAREST,  // Nearest Edge
   DISTANCE_FARTHEST, // Farthest Edge
   DISTANCE_CENTER    // Basket Center
};

enum ENUM_NEWS_IMPACT
{
   NEWS_IMPACT_LOW,    // Low Impact
   NEWS_IMPACT_MEDIUM, // Medium Impact
   NEWS_IMPACT_HIGH    // High Impact
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - ZERO HARDCODING ARCHITECTURE                  |
//+------------------------------------------------------------------+

//--- 1. General & Identification
input group "═══════════ General & Identification ═══════════"
input string             Input_Symbol = "XAUUSD";                      // Symbol to Trade
input int                Input_Magic_Number = 20240520;                // Magic Number (Unique ID)
input string             Input_Comment = "RSI_Grid_Dyn";               // Order Comment
input bool               Input_Enable_EA = true;                       // Master EA Enable Switch

//--- 2. Strategy & Signal Logic
input group "═══════════ Strategy & Signal Logic ═══════════"
input ENUM_TIMEFRAMES    Input_Timeframe = PERIOD_M1;                  // Signal Timeframe
input bool               Input_Use_Signal = true;                      // Enable RSI Signal Logic
input int                Input_RSI_Fast_Period = 5;                    // RSI Fast Period
input int                Input_RSI_Slow_Period = 30;                   // RSI Slow Period
input ENUM_APPLIED_PRICE Input_RSI_Price_Type = PRICE_CLOSE;           // RSI Price Type
input double             Input_RSI_Trend_Level = 50.0;                 // RSI Trend Level
input int                Input_Signal_Bar_Shift = 1;                   // Signal Bar Shift (0=current, 1=closed)

//--- 3. Money Management (Base & Martingale)
input group "═══════════ Money Management ═══════════"
input double             Input_Base_Lot_Size = 0.01;                   // Base Lot Size
input bool               Input_Use_Martingale = true;                  // Enable Martingale
input double             Input_Martingale_Multiplier = 1.3;            // Fixed Multiplier (if Dynamic off)
input int                Input_Max_Layers_Per_Side = 5;                // Max Layers Per Side
input int                Input_Lot_Step_Decimals = 2;                  // Lot Decimals (2=0.01, 3=0.001)
input int                Input_Allowed_Slippage_Points = 30;           // Allowed Slippage (Points)

//--- 4. Dynamic Volume Multiplier
input group "═══════════ Dynamic Volume Multiplier ═══════════"
input bool               Input_Use_Dynamic_Multiplier = false;         // Enable Dynamic Multiplier
input double             Input_Multiplier_Min = 1.2;                   // Minimum Multiplier
input double             Input_Multiplier_Max = 1.8;                   // Maximum Multiplier
input double             Input_Distance_Reference_USD = 10.00;         // Reference Distance (USD)
input ENUM_DISTANCE_CALC Input_Distance_Calculation = DISTANCE_NEAREST;// Distance Calculation Method
input ENUM_CURVE_TYPE    Input_Multiplier_Curve = CURVE_LINEAR;        // Interpolation Curve Type

//--- 5. Price Filters & Grid Protection
input group "═══════════ Price Filters & Grid Protection ═══════════"
input bool               Input_Use_Price_Filter = true;                // Enable Price Filter
input double             Input_Min_Distance_USD = 3.00;                // Min Distance from Basket Edge (USD)
input double             Input_Max_Basket_Width_USD = 25.00;           // Max Basket Width (USD)
input double             Input_Max_Total_Lots = 0.50;                  // Max Total Open Lots

//--- 6. Exit Logic & Take Profit
input group "═══════════ Exit Logic & Take Profit ═══════════"
input bool               Input_Close_Opposite_If_Profitable = true;    // Close Opposite on Signal
input double             Input_Min_Profit_To_Close_USD = 0.01;         // Min Profit to Close Opposite (USD)
input bool               Input_Close_Own_If_Profitable = true;         // Close Own on Opposite Signal
input bool               Input_Use_Trailing_Stop = false;              // Enable Trailing Stop
input double             Input_Trailing_Start_USD = 5.00;              // Trailing Start (USD)
input double             Input_Trailing_Step_USD = 2.00;               // Trailing Step (USD)

//--- 7. Risk Management & Circuit Breakers
input group "═══════════ Risk Management & Circuit Breakers ═══════════"
input bool               Input_Use_Equity_Stop = true;                 // Enable Equity Stop
input double             Input_Equity_Stop_Percent = 10.0;             // Equity Stop Percent
input bool               Input_Use_Floating_Loss_Pause = true;         // Enable Floating Loss Pause
input double             Input_Floating_Loss_Pause_Percent = 3.0;      // Floating Loss Pause Percent
input bool               Input_Use_Daily_Loss_Limit = true;            // Enable Daily Loss Limit
input double             Input_Daily_Loss_Limit_USD = 500.00;          // Daily Loss Limit (USD)
input bool               Input_Use_Max_Drawdown_Pause = false;         // Enable Max Drawdown Pause
input double             Input_Max_Drawdown_Pause_Percent = 15.0;      // Max Drawdown Pause Percent

//--- 8. Trading Filters (Time, Spread, News)
input group "═══════════ Trading Filters ═══════════"
input bool               Input_Use_Max_Spread_Filter = true;           // Enable Spread Filter
input double             Input_Max_Spread_USD = 0.50;                  // Max Spread (USD)
input bool               Input_Use_News_Filter = true;                 // Enable News Filter
input int                Input_News_Filter_Minutes = 60;               // News Filter Minutes Before/After
input ENUM_NEWS_IMPACT   Input_News_Impact_Level = NEWS_IMPACT_HIGH;   // News Impact Level to Filter
input bool               Input_Use_Weekend_Close = true;               // Enable Weekend Close
input int                Input_Weekend_Close_Day = 5;                  // Weekend Close Day (0=Sun, 5=Fri)
input int                Input_Weekend_Close_Hour = 21;                // Weekend Close Hour
input bool               Input_Use_Trading_Hours = false;              // Enable Trading Hours
input int                Input_Trading_Start_Hour = 0;                 // Trading Start Hour
input int                Input_Trading_End_Hour = 23;                  // Trading End Hour

//--- 9. Advanced & Debugging
input group "═══════════ Advanced & Debugging ═══════════"
input bool               Input_Debug_Mode = false;                     // Enable Debug Mode
input double             Input_Broker_Min_Lot = 0.01;                  // Broker Min Lot (0=Auto)
input double             Input_Broker_Max_Lot = 0.00;                  // Broker Max Lot (0=Auto)
input double             Input_Broker_Lot_Step = 0.01;                 // Broker Lot Step (0=Auto)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         m_trade;
datetime       m_last_bar_time = 0;
double         m_start_balance = 0.0;
double         m_daily_realized_loss = 0.0;
datetime       m_daily_loss_reset_time = 0;
bool           m_trading_disabled = false;
int            m_rsi_fast_handle = INVALID_HANDLE;
int            m_rsi_slow_handle = INVALID_HANDLE;

//--- Max Drawdown tracking
double         m_max_balance = 0.0;
double         m_max_drawdown_percent = 0.0;

//--- Broker parameters (auto-detected or manual)
double         m_broker_min_lot = 0.0;
double         m_broker_max_lot = 0.0;
double         m_broker_lot_step = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate input parameters (8.1)
   if(!ValidateInputParameters())
   {
      Print("ERROR: Input parameter validation failed");
      return INIT_FAILED;
   }
   
   //--- Initialize broker parameters
   InitializeBrokerParameters();
   
   //--- Use Input_Symbol instead of _Symbol
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   //--- Initialize indicators
   m_rsi_fast_handle = iRSI(symbol, Input_Timeframe, Input_RSI_Fast_Period, Input_RSI_Price_Type);
   m_rsi_slow_handle = iRSI(symbol, Input_Timeframe, Input_RSI_Slow_Period, Input_RSI_Price_Type);
   
   if(m_rsi_fast_handle == INVALID_HANDLE || m_rsi_slow_handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create RSI indicators");
      return INIT_FAILED;
   }
   
   //--- Initialize trade object
   m_trade.SetExpertMagicNumber(Input_Magic_Number);
   m_trade.SetDeviationInPoints(Input_Allowed_Slippage_Points);
   m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   //--- Store starting balance and max balance
   m_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_max_balance = m_start_balance;
   m_daily_loss_reset_time = TimeCurrent();
   
   //--- Initialize bar time
   m_last_bar_time = iTime(symbol, Input_Timeframe, 0);
   
   Print("DynamicRSIScalper initialized successfully");
   Print("Symbol: ", symbol, " | Magic: ", Input_Magic_Number);
   Print("Start Balance: ", m_start_balance);
   Print("EA Enabled: ", Input_Enable_EA);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   if(m_rsi_fast_handle != INVALID_HANDLE)
      IndicatorRelease(m_rsi_fast_handle);
   if(m_rsi_slow_handle != INVALID_HANDLE)
      IndicatorRelease(m_rsi_slow_handle);
   
   Print("DynamicRSIScalper deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check master EA enable switch
   if(!Input_Enable_EA)
      return;
   
   //--- 6.1 Check risk management on every tick
   if(!CheckRiskManagement())
      return;
   
   //--- 6.5 Weekend close check
   if(Input_Use_Weekend_Close)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == Input_Weekend_Close_Day && dt.hour >= Input_Weekend_Close_Hour)
      {
         CloseAllOrders("Weekend close");
         return;
      }
   }
   
   //--- 3.1-3.2 Check for new bar on specified timeframe
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   datetime current_bar_time = iTime(symbol, Input_Timeframe, 0);
   if(current_bar_time != m_last_bar_time)
   {
      m_last_bar_time = current_bar_time;
      ProcessNewBar();
   }
   
   //--- 5.6 Update trailing stops on every tick
   if(Input_Use_Trailing_Stop)
      UpdateTrailingStops();
}

//+------------------------------------------------------------------+
//| Process new bar event                                             |
//+------------------------------------------------------------------+
void ProcessNewBar()
{
   //--- Check if trading is disabled
   if(m_trading_disabled)
      return;
   
   //--- Check trading hours (6.7)
   if(Input_Use_Trading_Hours && !IsWithinTradingHours())
      return;
   
   //--- Check spread filter (5.8)
   if(Input_Use_Max_Spread_Filter && !IsSpreadAcceptable())
      return;
   
   //--- Check news filter (6.6)
   if(Input_Use_News_Filter && IsNewsTime())
      return;
   
   //--- 3.3-3.5 Generate signals
   int signal = WRONG_VALUE;
   if(Input_Use_Signal)
      signal = GetSignal();
   
   //--- 5.2 Decoupled Entry/Exit Logic
   if(signal == ORDER_TYPE_BUY)
   {
      //--- 5.2.1 Exit Check: Check if SELL basket should be closed
      if(Input_Close_Opposite_If_Profitable)
      {
         double sell_profit = CalculateBasketProfit(ORDER_TYPE_SELL);
         if(sell_profit >= Input_Min_Profit_To_Close_USD)
         {
            CloseBasket(ORDER_TYPE_SELL, "Opposite signal profitable");
         }
      }
      
      //--- Exit Check: Check if own BUY basket should be closed on opposite signal
      if(Input_Close_Own_If_Profitable)
      {
         double buy_profit = CalculateBasketProfit(ORDER_TYPE_BUY);
         if(buy_profit >= Input_Min_Profit_To_Close_USD)
         {
            CloseBasket(ORDER_TYPE_BUY, "Own basket profitable on opposite signal");
         }
      }
      
      //--- 5.2.2 Entry Check: Evaluate BUY basket entry
      TryOpenOrder(ORDER_TYPE_BUY);
   }
   else if(signal == ORDER_TYPE_SELL)
   {
      //--- 5.2.1 Exit Check: Check if BUY basket should be closed
      if(Input_Close_Opposite_If_Profitable)
      {
         double buy_profit = CalculateBasketProfit(ORDER_TYPE_BUY);
         if(buy_profit >= Input_Min_Profit_To_Close_USD)
         {
            CloseBasket(ORDER_TYPE_BUY, "Opposite signal profitable");
         }
      }
      
      //--- Exit Check: Check if own SELL basket should be closed on opposite signal
      if(Input_Close_Own_If_Profitable)
      {
         double sell_profit = CalculateBasketProfit(ORDER_TYPE_SELL);
         if(sell_profit >= Input_Min_Profit_To_Close_USD)
         {
            CloseBasket(ORDER_TYPE_SELL, "Own basket profitable on opposite signal");
         }
      }
      
      //--- 5.2.2 Entry Check: Evaluate SELL basket entry
      TryOpenOrder(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Get trading signal (3.3-3.5)                                      |
//+------------------------------------------------------------------+
int GetSignal()
{
   double rsi_fast[], rsi_slow[];
   ArraySetAsSeries(rsi_fast, true);
   ArraySetAsSeries(rsi_slow, true);
   
   //--- Copy RSI values
   if(CopyBuffer(m_rsi_fast_handle, 0, 0, Input_Signal_Bar_Shift + 2, rsi_fast) <= 0)
      return WRONG_VALUE;
   if(CopyBuffer(m_rsi_slow_handle, 0, 0, Input_Signal_Bar_Shift + 2, rsi_slow) <= 0)
      return WRONG_VALUE;
   
   //--- Get signal bar and previous bar values
   double rsi_fast_current = rsi_fast[Input_Signal_Bar_Shift];
   double rsi_fast_previous = rsi_fast[Input_Signal_Bar_Shift + 1];
   double rsi_slow_current = rsi_slow[Input_Signal_Bar_Shift];
   double rsi_slow_previous = rsi_slow[Input_Signal_Bar_Shift + 1];
   
   //--- 3.4 Buy Signal: Fast crosses above Slow AND above trend level
   if(rsi_fast_previous <= rsi_slow_previous && rsi_fast_current > rsi_slow_current)
   {
      if(rsi_fast_current > Input_RSI_Trend_Level)
         return ORDER_TYPE_BUY;
   }
   
   //--- 3.5 Sell Signal: Fast crosses below Slow AND below trend level
   if(rsi_fast_previous >= rsi_slow_previous && rsi_fast_current < rsi_slow_current)
   {
      if(rsi_fast_current < Input_RSI_Trend_Level)
         return ORDER_TYPE_SELL;
   }
   
   return WRONG_VALUE;
}

//+------------------------------------------------------------------+
//| Try to open order with all filters                               |
//+------------------------------------------------------------------+
void TryOpenOrder(ENUM_ORDER_TYPE order_type)
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   //--- 5.4 Check max layers
   int current_layers = CountLayers(order_type);
   if(current_layers >= Input_Max_Layers_Per_Side)
   {
      if(Input_Debug_Mode)
         Print("Max layers reached for ", EnumToString(order_type));
      return;
   }
   
   //--- 5.5 Check max total lots
   double total_lots = CalculateTotalLots();
   if(total_lots >= Input_Max_Total_Lots)
   {
      Print("Max total lots reached: ", total_lots);
      return;
   }
   
   //--- 5.3 Check price filter
   if(Input_Use_Price_Filter)
   {
      if(!PassesPriceFilter(order_type))
      {
         Print("Price filter not passed for ", EnumToString(order_type));
         return;
      }
   }
   
   //--- Calculate volume (4.0 Dynamic Volume Calculation)
   double volume = CalculateOrderVolume(order_type);
   if(volume < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("Calculated volume below minimum: ", volume);
      return;
   }
   
   //--- Execute order
   double price = (order_type == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
   
   bool success = false;
   ulong ticket = 0;
   
   if(order_type == ORDER_TYPE_BUY)
   {
      if(m_trade.Buy(volume, symbol, price, 0, 0, Input_Comment))
      {
         ticket = m_trade.ResultOrder();
         success = true;
         Print("BUY order opened: ", volume, " lots at ", price, " | Ticket: ", ticket);
      }
      else
      {
         Print("ERROR: Failed to open BUY order. Error: ", GetLastError());
      }
   }
   else
   {
      if(m_trade.Sell(volume, symbol, price, 0, 0, Input_Comment))
      {
         ticket = m_trade.ResultOrder();
         success = true;
         Print("SELL order opened: ", volume, " lots at ", price, " | Ticket: ", ticket);
      }
      else
      {
         Print("ERROR: Failed to open SELL order. Error: ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate order volume (4.0 Module)                              |
//+------------------------------------------------------------------+
double CalculateOrderVolume(ENUM_ORDER_TYPE order_type)
{
   //--- Get streak (number of current orders)
   int streak = CountLayers(order_type);
   
   //--- 4.1 Calculate dynamic multiplier
   double multiplier = Calculate_Dynamic_Multiplier(order_type);
   
   //--- 4.8 Calculate final volume
   double volume = Input_Base_Lot_Size;
   if(Input_Use_Martingale && streak > 0)
   {
      volume = Input_Base_Lot_Size * MathPow(multiplier, streak);
   }
   
   //--- 4.9 Round to lot decimals
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   double lot_step = m_broker_lot_step;
   volume = NormalizeDouble(volume / lot_step, 0) * lot_step;
   volume = NormalizeDouble(volume, Input_Lot_Step_Decimals);
   
   //--- 4.10 Validate against broker limits
   double min_lot = m_broker_min_lot;
   double max_lot = m_broker_max_lot;
   
   if(volume < min_lot)
      volume = min_lot;
   if(volume > max_lot)
      volume = max_lot;
   
   return volume;
}

//+------------------------------------------------------------------+
//| Calculate dynamic multiplier (4.1-4.7)                           |
//+------------------------------------------------------------------+
double Calculate_Dynamic_Multiplier(ENUM_ORDER_TYPE order_type)
{
   //--- 4.2 If dynamic multiplier disabled, return fixed multiplier
   if(!Input_Use_Dynamic_Multiplier)
      return Input_Martingale_Multiplier;
   
   //--- 4.3 Calculate distance based on method
   double distance_usd = CalculateBasketDistance(order_type);
   
   //--- 4.7 If distance is zero or negative, return minimum
   if(distance_usd <= 0.0)
      return Input_Multiplier_Min;
   
   //--- 4.6 If distance exceeds reference, return maximum
   if(distance_usd >= Input_Distance_Reference_USD)
      return Input_Multiplier_Max;
   
   //--- 4.4-4.5 Interpolate multiplier based on curve type
   double ratio = distance_usd / Input_Distance_Reference_USD;
   double multiplier = Input_Multiplier_Min;
   
   switch(Input_Multiplier_Curve)
   {
      case CURVE_LINEAR:
         multiplier = Input_Multiplier_Min + (Input_Multiplier_Max - Input_Multiplier_Min) * ratio;
         break;
         
      case CURVE_EXPONENTIAL:
         multiplier = Input_Multiplier_Min + (Input_Multiplier_Max - Input_Multiplier_Min) * MathPow(ratio, 2.0);
         break;
         
      case CURVE_LOGARITHMIC:
         if(ratio > 0.0)
            multiplier = Input_Multiplier_Min + (Input_Multiplier_Max - Input_Multiplier_Min) * MathLog10(1.0 + 9.0 * ratio);
         break;
   }
   
   //--- Clamp to min/max
   if(multiplier < Input_Multiplier_Min)
      multiplier = Input_Multiplier_Min;
   if(multiplier > Input_Multiplier_Max)
      multiplier = Input_Multiplier_Max;
   
   return multiplier;
}

//+------------------------------------------------------------------+
//| Calculate basket distance (4.3)                                  |
//+------------------------------------------------------------------+
double CalculateBasketDistance(ENUM_ORDER_TYPE order_type)
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   double current_price = (order_type == ORDER_TYPE_BUY) ? 
                          SymbolInfoDouble(symbol, SYMBOL_ASK) : 
                          SymbolInfoDouble(symbol, SYMBOL_BID);
   
   double nearest_price = 0.0;
   double farthest_price = 0.0;
   double sum_prices = 0.0;
   double sum_lots = 0.0;
   int count = 0;
   
   //--- Loop through positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number &&
            PositionGetInteger(POSITION_TYPE) == order_type)
         {
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double lots = PositionGetDouble(POSITION_VOLUME);
            
            if(count == 0)
            {
               nearest_price = open_price;
               farthest_price = open_price;
            }
            else
            {
               if(order_type == ORDER_TYPE_BUY)
               {
                  if(open_price < current_price && MathAbs(current_price - open_price) < MathAbs(current_price - nearest_price))
                     nearest_price = open_price;
                  if(MathAbs(current_price - open_price) > MathAbs(current_price - farthest_price))
                     farthest_price = open_price;
               }
               else
               {
                  if(open_price > current_price && MathAbs(open_price - current_price) < MathAbs(nearest_price - current_price))
                     nearest_price = open_price;
                  if(MathAbs(open_price - current_price) > MathAbs(farthest_price - current_price))
                     farthest_price = open_price;
               }
            }
            
            sum_prices += open_price * lots;
            sum_lots += lots;
            count++;
         }
      }
   }
   
   if(count == 0)
      return 0.0;
   
   double distance_price = 0.0;
   
   switch(Input_Distance_Calculation)
   {
      case DISTANCE_NEAREST:
         distance_price = MathAbs(current_price - nearest_price);
         break;
         
      case DISTANCE_FARTHEST:
         distance_price = MathAbs(current_price - farthest_price);
         break;
         
      case DISTANCE_CENTER:
         double center_price = sum_prices / sum_lots;
         distance_price = MathAbs(current_price - center_price);
         break;
   }
   
   //--- Convert to USD (8.5)
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double distance_usd = (distance_price / tick_size) * tick_value;
   
   return distance_usd;
}

//+------------------------------------------------------------------+
//| Check if price passes filter (5.3)                               |
//+------------------------------------------------------------------+
bool PassesPriceFilter(ENUM_ORDER_TYPE order_type)
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   double current_price = (order_type == ORDER_TYPE_BUY) ? 
                          SymbolInfoDouble(symbol, SYMBOL_ASK) : 
                          SymbolInfoDouble(symbol, SYMBOL_BID);
   
   double min_price = DBL_MAX;
   double max_price = -DBL_MAX;
   double last_price = 0.0;
   bool has_positions = false;
   
   //--- Find basket boundaries
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number &&
            PositionGetInteger(POSITION_TYPE) == order_type)
         {
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            
            if(open_price < min_price)
               min_price = open_price;
            if(open_price > max_price)
               max_price = open_price;
            
            last_price = open_price;
            has_positions = true;
         }
      }
   }
   
   //--- If no positions, filter passes
   if(!has_positions)
      return true;
   
   //--- Check if price is inside basket range
   if(current_price >= min_price && current_price <= max_price)
   {
      Print("Price inside basket range - filter failed");
      return false;
   }
   
   //--- Check minimum distance from last order
   double distance_price = MathAbs(current_price - last_price);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double distance_usd = (distance_price / tick_size) * tick_value;
   
   if(distance_usd < Input_Min_Distance_USD)
   {
      Print("Distance too small: ", distance_usd, " USD");
      return false;
   }
   
   //--- Check basket width
   double basket_width_price = max_price - min_price;
   double new_basket_width_price = MathMax(max_price, current_price) - MathMin(min_price, current_price);
   double new_basket_width_usd = (new_basket_width_price / tick_size) * tick_value;
   
   if(new_basket_width_usd > Input_Max_Basket_Width_USD)
   {
      Print("Basket width would exceed maximum: ", new_basket_width_usd, " USD");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Count layers for specific order type (5.4)                       |
//+------------------------------------------------------------------+
int CountLayers(ENUM_ORDER_TYPE order_type)
{
   int count = 0;
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number &&
            PositionGetInteger(POSITION_TYPE) == order_type)
         {
            count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Calculate total open lots (5.5)                                  |
//+------------------------------------------------------------------+
double CalculateTotalLots()
{
   double total = 0.0;
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number)
         {
            total += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
   
   return total;
}

//+------------------------------------------------------------------+
//| Calculate basket profit (5.2.1)                                  |
//+------------------------------------------------------------------+
double CalculateBasketProfit(ENUM_ORDER_TYPE order_type)
{
   double profit = 0.0;
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number &&
            PositionGetInteger(POSITION_TYPE) == order_type)
         {
            profit += PositionGetDouble(POSITION_PROFIT);
            profit += PositionGetDouble(POSITION_SWAP);
         }
      }
   }
   
   return profit;
}

//+------------------------------------------------------------------+
//| Close basket (5.2.1)                                             |
//+------------------------------------------------------------------+
void CloseBasket(ENUM_ORDER_TYPE order_type, string reason)
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   Print("Closing ", EnumToString(order_type), " basket. Reason: ", reason);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number &&
            PositionGetInteger(POSITION_TYPE) == order_type)
         {
            if(!m_trade.PositionClose(ticket))
            {
               Print("ERROR: Failed to close position ", ticket, ". Error: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all orders (6.5)                                           |
//+------------------------------------------------------------------+
void CloseAllOrders(string reason)
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   Print("Closing all orders. Reason: ", reason);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number)
         {
            if(!m_trade.PositionClose(ticket))
            {
               Print("ERROR: Failed to close position ", ticket, ". Error: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update trailing stops (5.6)                                      |
//+------------------------------------------------------------------+
void UpdateTrailingStops()
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number)
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            //--- Check if profit exceeds trailing start
            if(profit >= Input_Trailing_Start_USD)
            {
               double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
               double sl = PositionGetDouble(POSITION_SL);
               ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               
               double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
               double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
               double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
               
               //--- Convert USD to price
               double trailing_step_price = (Input_Trailing_Step_USD / tick_value) * tick_size;
               
               double new_sl = 0.0;
               
               if(pos_type == POSITION_TYPE_BUY)
               {
                  double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
                  new_sl = bid - trailing_step_price;
                  
                  if(new_sl > sl || sl == 0.0)
                  {
                     if(m_trade.PositionModify(ticket, new_sl, 0))
                     {
                        Print("Trailing stop updated for BUY ", ticket, " to ", new_sl);
                     }
                  }
               }
               else
               {
                  double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
                  new_sl = ask + trailing_step_price;
                  
                  if(new_sl < sl || sl == 0.0)
                  {
                     if(m_trade.PositionModify(ticket, new_sl, 0))
                     {
                        Print("Trailing stop updated for SELL ", ticket, " to ", new_sl);
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check risk management (6.1-6.7)                                  |
//+------------------------------------------------------------------+
bool CheckRiskManagement()
{
   //--- Update max balance and calculate drawdown
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(current_balance > m_max_balance)
      m_max_balance = current_balance;
   
   double current_drawdown_percent = 0.0;
   if(m_max_balance > 0.0)
      current_drawdown_percent = ((m_max_balance - current_balance) / m_max_balance) * 100.0;
   
   if(current_drawdown_percent > m_max_drawdown_percent)
      m_max_drawdown_percent = current_drawdown_percent;
   
   //--- Check max drawdown pause
   if(Input_Use_Max_Drawdown_Pause)
   {
      if(current_drawdown_percent > Input_Max_Drawdown_Pause_Percent)
      {
         if(Input_Debug_Mode)
            Print("Max drawdown pause active: ", current_drawdown_percent, "%");
         return false;
      }
   }
   
   //--- 6.2 Equity stop check
   if(Input_Use_Equity_Stop)
   {
      double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double stop_level = m_start_balance * (1.0 - Input_Equity_Stop_Percent / 100.0);
      
      if(current_equity < stop_level)
      {
         CloseAllOrders("Equity stop triggered");
         m_trading_disabled = true;
         Print("CRITICAL: Equity stop triggered. Trading disabled.");
         return false;
      }
   }
   
   //--- 6.3 Floating loss pause check
   if(Input_Use_Floating_Loss_Pause)
   {
      double floating_pl = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number)
            {
               floating_pl += PositionGetDouble(POSITION_PROFIT);
               floating_pl += PositionGetDouble(POSITION_SWAP);
            }
         }
      }
      
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double floating_loss_percent = 0.0;
      if(balance > 0.0)
         floating_loss_percent = (-floating_pl / balance) * 100.0;
      
      if(floating_loss_percent > Input_Floating_Loss_Pause_Percent)
      {
         if(Input_Debug_Mode)
            Print("Floating loss pause active: ", floating_loss_percent, "%");
         return false;
      }
   }
   
   //--- 6.4 Daily loss limit check
   if(Input_Use_Daily_Loss_Limit)
   {
      //--- Reset daily loss at start of new day
      MqlDateTime dt_current, dt_reset;
      TimeToStruct(TimeCurrent(), dt_current);
      TimeToStruct(m_daily_loss_reset_time, dt_reset);
      
      if(dt_current.day != dt_reset.day)
      {
         m_daily_realized_loss = 0.0;
         m_daily_loss_reset_time = TimeCurrent();
         Print("Daily loss counter reset");
      }
      
      //--- Calculate daily loss from history
      CalculateDailyLoss();
      
      if(m_daily_realized_loss > Input_Daily_Loss_Limit_USD)
      {
         Print("Daily loss limit reached: ", m_daily_realized_loss, " USD");
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate daily realized loss                                    |
//+------------------------------------------------------------------+
void CalculateDailyLoss()
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   m_daily_realized_loss = 0.0;
   
   MqlDateTime dt_today;
   TimeToStruct(TimeCurrent(), dt_today);
   dt_today.hour = 0;
   dt_today.min = 0;
   dt_today.sec = 0;
   datetime today_start = StructToTime(dt_today);
   
   //--- Get deals from history
   HistorySelect(today_start, TimeCurrent());
   
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Input_Magic_Number &&
            HistoryDealGetString(ticket, DEAL_SYMBOL) == symbol &&
            HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
            double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            
            double net_result = profit + swap + commission;
            if(net_result < 0.0)
               m_daily_realized_loss += MathAbs(net_result);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if within trading hours (6.7)                              |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   if(Input_Trading_Start_Hour <= Input_Trading_End_Hour)
   {
      if(dt.hour >= Input_Trading_Start_Hour && dt.hour <= Input_Trading_End_Hour)
         return true;
   }
   else
   {
      //--- Handle overnight trading (e.g., 22:00 to 02:00)
      if(dt.hour >= Input_Trading_Start_Hour || dt.hour <= Input_Trading_End_Hour)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable (5.8)                              |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double spread_price = ask - bid;
   
   //--- Convert to USD
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double spread_usd = (spread_price / tick_size) * tick_value;
   
   if(spread_usd > Input_Max_Spread_USD)
   {
      Print("Spread too high: ", spread_usd, " USD");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if news time (6.6)                                         |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   //--- Use MQL5 Economic Calendar
   MqlCalendarValue values[];
   datetime start_time = TimeCurrent();
   datetime end_time = start_time + Input_News_Filter_Minutes * 60;
   
   if(CalendarValueHistory(values, start_time, end_time))
   {
      for(int i = 0; i < ArraySize(values); i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            //--- Check impact level
            bool impact_match = false;
            
            switch(Input_News_Impact_Level)
            {
               case NEWS_IMPACT_HIGH:
                  impact_match = (event.importance == CALENDAR_IMPORTANCE_HIGH);
                  break;
               case NEWS_IMPACT_MEDIUM:
                  impact_match = (event.importance == CALENDAR_IMPORTANCE_MODERATE || 
                                 event.importance == CALENDAR_IMPORTANCE_HIGH);
                  break;
               case NEWS_IMPACT_LOW:
                  impact_match = true; // All levels
                  break;
            }
            
            if(impact_match)
            {
               datetime news_time = (datetime)values[i].time;
               datetime filter_start = news_time - Input_News_Filter_Minutes * 60;
               datetime filter_end = news_time + Input_News_Filter_Minutes * 60;
               
               if(TimeCurrent() >= filter_start && TimeCurrent() <= filter_end)
               {
                  if(Input_Debug_Mode)
                     Print("News filter active: ", event.name, " at ", TimeToString(news_time));
                  return true;
               }
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Validate input parameters (8.1)                                  |
//+------------------------------------------------------------------+
bool ValidateInputParameters()
{
   bool valid = true;
   
   //--- RSI periods
   if(Input_RSI_Fast_Period <= 0 || Input_RSI_Slow_Period <= 0)
   {
      Print("ERROR: RSI periods must be positive");
      valid = false;
   }
   
   if(Input_RSI_Fast_Period >= Input_RSI_Slow_Period)
   {
      Print("ERROR: RSI Fast must be less than RSI Slow");
      valid = false;
   }
   
   //--- Symbol
   if(Input_Symbol == "")
   {
      Print("WARNING: Empty symbol, using chart symbol");
   }
   
   //--- Base lot
   if(Input_Base_Lot_Size <= 0.0)
   {
      Print("ERROR: Base lot must be positive");
      valid = false;
   }
   
   //--- Martingale multiplier
   if(Input_Martingale_Multiplier < 1.0)
   {
      Print("ERROR: Martingale multiplier must be >= 1.0");
      valid = false;
   }
   
   //--- Dynamic multiplier parameters
   if(Input_Use_Dynamic_Multiplier)
   {
      if(Input_Multiplier_Min <= 0.0 || Input_Multiplier_Max <= 0.0)
      {
         Print("ERROR: Multiplier min/max must be positive");
         valid = false;
      }
      
      if(Input_Multiplier_Min >= Input_Multiplier_Max)
      {
         Print("ERROR: Multiplier Min must be less than Multiplier Max");
         valid = false;
      }
      
      if(Input_Distance_Reference_USD <= 0.0)
      {
         Print("ERROR: Distance Reference must be positive");
         valid = false;
      }
   }
   
   //--- Max layers
   if(Input_Max_Layers_Per_Side <= 0)
   {
      Print("ERROR: Max layers must be positive");
      valid = false;
   }
   
   //--- Price filter
   if(Input_Use_Price_Filter)
   {
      if(Input_Min_Distance_USD < 0.0)
      {
         Print("ERROR: Min distance cannot be negative");
         valid = false;
      }
      
      if(Input_Max_Basket_Width_USD <= 0.0)
      {
         Print("ERROR: Max basket width must be positive");
         valid = false;
      }
   }
   
   //--- Max total lots
   if(Input_Max_Total_Lots <= 0.0)
   {
      Print("ERROR: Max total lots must be positive");
      valid = false;
   }
   
   //--- Exit logic
   if(Input_Min_Profit_To_Close_USD < 0.0)
   {
      Print("ERROR: Min profit to close cannot be negative");
      valid = false;
   }
   
   //--- Trailing stop
   if(Input_Use_Trailing_Stop)
   {
      if(Input_Trailing_Start_USD <= 0.0 || Input_Trailing_Step_USD <= 0.0)
      {
         Print("ERROR: Trailing parameters must be positive");
         valid = false;
      }
   }
   
   //--- Risk management
   if(Input_Use_Equity_Stop && (Input_Equity_Stop_Percent <= 0.0 || Input_Equity_Stop_Percent >= 100.0))
   {
      Print("ERROR: Equity stop percent must be between 0 and 100");
      valid = false;
   }
   
   if(Input_Use_Floating_Loss_Pause && (Input_Floating_Loss_Pause_Percent <= 0.0 || Input_Floating_Loss_Pause_Percent >= 100.0))
   {
      Print("ERROR: Floating loss pause percent must be between 0 and 100");
      valid = false;
   }
   
   if(Input_Use_Daily_Loss_Limit && Input_Daily_Loss_Limit_USD <= 0.0)
   {
      Print("ERROR: Daily loss limit must be positive");
      valid = false;
   }
   
   //--- Filters
   if(Input_Use_Max_Spread_Filter && Input_Max_Spread_USD <= 0.0)
   {
      Print("ERROR: Max spread must be positive");
      valid = false;
   }
   
   if(Input_Use_News_Filter && Input_News_Filter_Minutes <= 0)
   {
      Print("ERROR: News filter minutes must be positive");
      valid = false;
   }
   
   if(Input_Trading_Start_Hour < 0 || Input_Trading_Start_Hour > 23)
   {
      Print("ERROR: Trading start hour must be 0-23");
      valid = false;
   }
   
   if(Input_Trading_End_Hour < 0 || Input_Trading_End_Hour > 23)
   {
      Print("ERROR: Trading end hour must be 0-23");
      valid = false;
   }
   
   //--- Magic number
   if(Input_Magic_Number <= 0)
   {
      Print("ERROR: Magic number must be positive");
      valid = false;
   }
   
   return valid;
}

//+------------------------------------------------------------------+
//| Initialize broker parameters                                     |
//+------------------------------------------------------------------+
void InitializeBrokerParameters()
{
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   //--- Get broker parameters (auto-detect or use manual override)
   if(Input_Broker_Min_Lot > 0.0)
      m_broker_min_lot = Input_Broker_Min_Lot;
   else
      m_broker_min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   
   if(Input_Broker_Max_Lot > 0.0)
      m_broker_max_lot = Input_Broker_Max_Lot;
   else
      m_broker_max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   
   if(Input_Broker_Lot_Step > 0.0)
      m_broker_lot_step = Input_Broker_Lot_Step;
   else
      m_broker_lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   Print("Broker Parameters: Min=", m_broker_min_lot, " Max=", m_broker_max_lot, " Step=", m_broker_lot_step);
}

//+------------------------------------------------------------------+
//| Calculate total floating P/L for all positions                   |
//+------------------------------------------------------------------+
double CalculateTotalFloatingPL()
{
   double total_pl = 0.0;
   string symbol = (Input_Symbol == "") ? _Symbol : Input_Symbol;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == Input_Magic_Number)
         {
            total_pl += PositionGetDouble(POSITION_PROFIT);
            total_pl += PositionGetDouble(POSITION_SWAP);
         }
      }
   }
   
   return total_pl;
}

//+------------------------------------------------------------------+
