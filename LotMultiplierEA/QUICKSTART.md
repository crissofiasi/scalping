# Quick Start Guide - Lot Multiplier EA

## Setup Steps

### 1. Installation
- Copy `LotMultiplierEA.mq5` to: `C:\Users\[YourUser]\AppData\Roaming\MetaQuotes\Terminal\[TerminalID]\MQL5\Experts\`
- Open in MetaEditor and compile (F7)
- Load preset file from: `File → Open Data Folder → MQL5 → Profiles → Templates`

### 2. Configuration

Choose a preset based on your strategy:

#### **Classic Mode** (Recommended for beginners)
```
Use: LotMultiplierEA_Classic.set
Perfect for: Simple multiplication of provider trades
Example: Provider trades 0.1 lot → You trade 0.2 lot total (Factor = 2.0)
```

#### **Proportional Mode** (Best for different account sizes)
```
Use: LotMultiplierEA_Proportional.set
Perfect for: Matching provider's risk percentage
Example: Provider has $10k, trades 0.1 lot
         You have $5k → You trade 0.05 lot total (Factor = 1.0)
```

#### **Fixed Mode** (For consistent lot sizes)
```
Use: LotMultiplierEA_Fixed.set
Perfect for: Always using same lot size regardless of provider
Example: Always trade 0.1 lot total, no matter what provider does
```

### 3. Key Parameters to Adjust

#### **Identifying Provider Trades**
```
ProviderComment = "CopyTrade"  // Set to your copy service's comment
ProviderMagicNumber = 0        // Set to provider's magic (0 = any)
```

#### **Volume Control**
```
Factor = 2.0                   // Multiply provider volume by 2
MinNewVolume = 0.01           // Ignore if new volume < 0.01 lots
```

#### **Provider Balance** (Proportional mode only)
```
ProviderBalance = 10000       // Provider's account balance
```
You need to know the provider's actual balance for accurate scaling.

## Usage Examples

### Example 1: Amplify Provider Trades (2x)
**Settings:**
- Mode: Classic
- Factor: 2.0
- MinNewVolume: 0.01

**Scenario:**
- Provider opens: 0.10 lot BUY EURUSD
- Total desired: 0.10 × 2.0 = 0.20 lots
- New volume: 0.20 - 0.10 = **0.10 lot**
- **EA opens: 0.10 lot BUY EURUSD** ✓

### Example 2: Reduce Exposure (50%)
**Settings:**
- Mode: Classic
- Factor: 0.5
- MinNewVolume: 0.01

**Scenario:**
- Provider opens: 0.20 lot BUY EURUSD
- Total desired: 0.20 × 0.5 = 0.10 lots
- New volume: 0.10 - 0.20 = **-0.10 lot**
- **EA opens: 0.10 lot SELL EURUSD** (HEDGE!) ✓

### Example 3: Scale with Smaller Account
**Settings:**
- Mode: Proportional
- Factor: 1.0
- ProviderBalance: 10000
- Your balance: 5000

**Scenario:**
- Provider opens: 0.10 lot BUY GBPUSD
- Total desired: 0.10 × (5000 × 1.0) / 10000 = 0.05 lots
- New volume: 0.05 - 0.10 = **-0.05 lot**
- **EA opens: 0.05 lot SELL GBPUSD** (HEDGE because your account is smaller) ✓

### Example 4: Below Minimum Threshold
**Settings:**
- Mode: Classic
- Factor: 1.1
- MinNewVolume: 0.01

**Scenario:**
- Provider opens: 0.01 lot BUY USDJPY
- Total desired: 0.01 × 1.1 = 0.011 lots
- New volume: 0.011 - 0.01 = **0.001 lot**
- 0.001 < 0.01 (minimum)
- **EA does nothing** ✓

## Understanding the Logic

```
newVolume = totalVolume - providerVolume

IF |newVolume| < MinNewVolume:
    → Do nothing (too small)

IF newVolume > 0:
    → Open SAME direction (complement)
    
IF newVolume < 0:
    → Open OPPOSITE direction (hedge)
```

## Common Issues

### Problem: EA doesn't detect provider trades
**Solution:**
- Check `ProviderComment` matches your copy service
- Try setting `ProviderMagicNumber = 0` (detects all trades)
- Check Expert log for "New provider trade detected" messages

### Problem: Trades open in wrong direction
**Solution:**
- Check your Factor setting
- If Factor < 1.0, EA will hedge (opposite direction)
- Review calculation: totalVolume vs providerVolume

### Problem: No trades opening
**Solution:**
- Check `MinNewVolume` - might be too high
- Verify calculated volume meets broker minimum (usually 0.01)
- Check margin requirements

## Best Practices

1. **Test in Demo First**: Always test configuration in demo account
2. **Start Small**: Use small Factor values initially (1.1 - 1.5)
3. **Monitor Margin**: Ensure sufficient margin for complementary trades
4. **Check Logs**: Review Expert log regularly for errors
5. **One Symbol per Chart**: Not required but helps monitoring
6. **Set Correct Balance**: For Proportional mode, get exact provider balance

## Next Steps

1. Load EA on any chart (symbol doesn't matter)
2. Enable AutoTrading button
3. Wait for provider to open trade
4. Check if complementary trade opens
5. Monitor Expert log for details

## Support & Logs

Check MetaTrader 5 → Experts tab for detailed logs including:
- Provider trade detection
- Volume calculations
- Trade execution results
- Error messages
