# EnvelopeSMA EA – XAUUSD Daily

## Strategy Logic

### Indicators (Daily Timeframe)
| Indicator | Setting |
|-----------|---------|
| Envelopes | Period 20 · Deviation 4% · Method SMA · Price Median · Shift 1 |
| SMA | Period 20 · Price Median · Shift 1 |

### Entry – SMA Cross (real-time)
- **BUY**: Price crosses *above* D1 SMA → enter at market, TP = upper envelope
- **SELL**: Price crosses *below* D1 SMA → enter at market, TP = lower envelope
- Detected on every tick; no waiting for bar close

### Entry – SMA Bounce (real-time)
- Price enters the zone within `BounceThresholdPct` % of the SMA, then exits back on the **same side** it arrived from
- **BUY**: Bounces above → enter at market, TP = upper envelope
- **SELL**: Bounces below → enter at market, TP = lower envelope
- Both cross and bounce share the same **one trade per direction per day** limit

### Daily TP Refresh
On every new daily bar all open positions have their TP updated to the fresh envelope (or SMA) level.

### TP Hit → Counter Trade
| Closed Position | Counter Trade | Counter TP |
|----------------|---------------|------------|
| BUY hit upper envelope | SELL at market | SMA |
| SELL hit lower envelope | BUY at market | SMA |

Counter trade volume = `previous volume × VolumeFactor`.  
Counter TPs are also refreshed daily to the current SMA.

### Price Closes Outside Envelope
- Close above upper envelope → BUY positions' TP redirected from envelope to SMA  
- Close below lower envelope → SELL positions' TP redirected from envelope to SMA  

**Volume adjustment** when the new SMA TP puts a position at a loss:
- If the count of *winning* positions on that side would **change** → close & reopen with `volume × VolumeFactor`  
- If the winning count stays the **same** → keep current volume (no adjustment)

---

## Input Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TradeSymbol` | XAUUSD | Symbol to trade |
| `EnvPeriod` | 20 | Envelope MA period |
| `EnvDeviation` | 4.0 | Envelope deviation % |
| `SmaPeriod` | 20 | SMA period |
| `IndicatorShift` | 1 | Both indicators' shift |
| `InitialLotSize` | 0.01 | Starting lot |
| `BounceThresholdPct` | 0.10 | SMA bounce zone size (% of SMA price) |
| `VolumeFactor` | 1.5 | Volume multiplier on adjustments |
| `MagicNumber` | 88888 | EA magic number |
| `Slippage` | 50 | Max slippage points |
| `TradeComment` | EnvSMA | Comment prefix |
| `MaxLotSize` | 10.0 | Hard lot cap |

---

## Position Comment Tags
The EA embeds a tag in every position comment so it can identify its own trades:

| Tag | Meaning |
|-----|---------|
| `EnvBUY` | Initial BUY, TP at upper envelope |
| `EnvSELL` | Initial SELL, TP at lower envelope |
| `SMABUY` | Counter BUY, TP at SMA |
| `SMASELL` | Counter SELL, TP at SMA |

---

## Installation
1. Copy `EnvelopeSMA_EA.mq5` to `MQL5/Experts/` in your MT5 data folder  
2. Compile in MetaEditor  
3. Attach to any XAUUSD daily chart  
4. No need to set the chart timeframe – the EA reads D1 data internally  
