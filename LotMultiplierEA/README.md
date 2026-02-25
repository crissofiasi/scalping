# Lot Multiplier EA

Expert Advisor that monitors copied trades from a provider and opens complementary positions based on configurable lot multiplication strategies.

## Features

- **Three Multiplication Types**:
  1. **Proportional**: Scales volume based on account balance ratio
  2. **Classic**: Simple factor multiplication
  3. **Fixed**: Fixed volume regardless of provider

- **Smart Volume Management**:
  - Opens complementary trades in the same direction when multiplier > 1
  - Opens hedging trades in opposite direction when multiplier < 1
  - Minimum volume threshold to avoid micro-trades

- **Flexible Provider Identification**:
  - Filter by magic number
  - Filter by comment pattern
  - Tracks processed trades to avoid duplicates

## Input Parameters

### Multiplication Settings
- **Multiplication Type**: Choose between Proportional, Classic, or Fixed
- **Factor**: Multiplier for Proportional/Classic types
- **Provider Balance**: Provider's account balance (for Proportional calculation)
- **Fixed Volume**: Fixed lot size (for Fixed type)
- **Min New Volume**: Minimum volume threshold to open new trade

### Trade Settings
- **Provider Comment**: Comment pattern to identify provider trades
- **Provider Magic Number**: Filter provider trades by magic number (0 = any)
- **Our Magic Number**: Magic number for our complementary trades
- **Slippage**: Maximum price slippage in points
- **Trade Comment**: Comment for our trades

### Risk Settings
- **Use Stop Loss/Take Profit**: Enable/disable protective orders
- **Stop Loss/Take Profit Pips**: Distance in pips

## Volume Calculation Logic

### 1. Proportional Mode
```
totalVolume = providerVolume * (accountBalance * factor) / providerBalance
```
Example: Provider has 10,000 balance with 0.1 lot. Your account has 5,000 with factor 1.0:
- totalVolume = 0.1 * (5000 * 1.0) / 10000 = 0.05 lots

### 2. Classic Mode
```
totalVolume = providerVolume * factor
```
Example: Provider trades 0.1 lot with factor 2.0:
- totalVolume = 0.1 * 2.0 = 0.2 lots

### 3. Fixed Mode
```
totalVolume = fixedVolume
```
Always opens the specified fixed volume regardless of provider volume.

## New Volume Calculation

```
newVolume = totalVolume - providerVolume
```

- **newVolume > 0**: Opens additional position in SAME direction
- **newVolume < 0**: Opens position in OPPOSITE direction (hedge)
- **|newVolume| < minNewVolume**: Does nothing (below threshold)

## Example Scenarios

### Scenario 1: Amplify Provider Trades (Classic, Factor = 2.0)
- Provider opens: 0.1 lot BUY
- totalVolume = 0.1 * 2.0 = 0.2 lots
- newVolume = 0.2 - 0.1 = 0.1 lots
- **Action**: Open 0.1 lot BUY

### Scenario 2: Reduce Exposure (Classic, Factor = 0.5)
- Provider opens: 0.2 lot BUY
- totalVolume = 0.2 * 0.5 = 0.1 lots
- newVolume = 0.1 - 0.2 = -0.1 lots
- **Action**: Open 0.1 lot SELL (opposite direction)

### Scenario 3: Proportional Scaling
- Provider: 10,000 balance, 0.1 lot BUY
- Your account: 5,000 balance, Factor = 1.0
- totalVolume = 0.1 * (5000 * 1.0) / 10000 = 0.05 lots
- newVolume = 0.05 - 0.1 = -0.05 lots
- **Action**: Open 0.05 lot SELL (smaller account = hedge)

## Installation

1. Copy `LotMultiplierEA.mq5` to your MT5 `Experts` folder
2. Compile in MetaEditor
3. Configure input parameters
4. Attach to any chart (symbol doesn't matter as EA monitors all positions)

## Important Notes

- EA monitors entire account for provider trades
- Tracks positions by ticket to avoid duplicate processing
- Automatically cleans up closed positions from tracking
- Works with any broker that supports copy trading
- Ensure sufficient margin for complementary trades
- Test in demo account first

## Safety Features

- Volume normalization according to symbol requirements
- Minimum volume threshold to avoid micro-trades
- Adjustable slippage tolerance
- Optional stop loss and take profit
- Position tracking to prevent duplicate orders

## Support

For issues or questions, check the logs in MetaTrader 5 Expert tab.
