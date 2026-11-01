# ValenceSwap

[![CI](https://github.com/ZengLLQ/valence-swap/actions/workflows/ci.yml/badge.svg)](https://github.com/ZengLLQ/valence-swap/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-363636.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-Framework-orange.svg)](https://getfoundry.sh/)
[![EIP-1153](https://img.shields.io/badge/EVM-Transient%20Storage%20(EIP--1153)-8C8C8C.svg)](https://eips.ethereum.org/EIPS/eip-1153)

**ValenceSwap** is an advanced Uniswap v4 Dynamic Fee Hook and concentrated liquidity AMM protocol leveraging **EIP-1153 Transient Storage** (`tstore` / `tload` on Cancun EVM) to mitigate **Loss-Versus-Rebalancing (LVR)** and achieve zero-storage gas reentrancy protection.

---

## Architecture & Lifecycle

```mermaid
sequenceDiagram
    autonumber
    actor Trader as Swapper / Arb Bot
    participant Pool as ValencePool (AMM)
    participant Hook as ValenceHook (v4 Hook)
    participant Transient as EIP-1153 Transient Storage

    Trader->>Pool: swap(zeroForOne, amountIn)
    Pool->>Hook: beforeSwap(key, params)
    Hook->>Transient: tstore(REENTRANCY_SLOT, 1) [Zero SSTORE gas]
    Hook->>Hook: calculateDynamicFee(poolVolatility, gamma)
    Hook-->>Pool: return (selector, 0, dynamicFee)
    
    Pool->>Pool: Deduct Dynamic Fee & Execute x * y = k
    Pool->>Pool: Compute New Price Tick (currentTick += Δtick)
    
    Pool->>Hook: afterSwap(key, params, delta, hookData(newTick))
    Hook->>Hook: Update Volatility EMA: σ²_t = α · (Δtick)² + (1 - α) · σ²_{t-1}
    Hook->>Transient: tstore(REENTRANCY_SLOT, 0)
    Hook-->>Pool: return (selector, 0)
    
    Pool-->>Trader: Transfer amountOut (LVR Protected)
```

---

## Mathematical Formulations

### 1. Exponential Moving Average (EMA) Realized Volatility

To defend liquidity providers against arbitrage extraction (LVR), `ValenceHook` dynamically tracks tick displacement variance $\sigma^2_t$:
$$\sigma^2_t = \frac{\alpha \cdot (\Delta \text{tick})^2 + (1000 - \alpha) \cdot \sigma^2_{t-1}}{1000}$$
where $\alpha = 200$ (20% smoothing factor weight per swap).

### 2. Dynamic Fee Curve

The fee charged to traders automatically scales with instantaneous realized market volatility:
$$\text{fee}(\sigma) = \text{baseFee} + \min\left(\text{maxFee} - \text{baseFee}, \gamma \cdot \sqrt{\sigma^2_t}\right)$$

- **Base Fee**: $5 \text{ bps}$ ($500$ in hundredths of bps) during quiet regimes.
- **Max Fee**: $100 \text{ bps}$ ($10,000$) during severe market turbulence / arbitrage shocks.
- **Gamma ($\gamma$)**: Configurable sensitivity multiplier compensating LPs for adverse selection.

### 3. EIP-1153 Transient Storage Comparison

| Operation | Standard Storage (`sstore`/`sload`) | Transient Storage (`tstore`/`tload`) | Gas Reduction |
| :--- | :--- | :--- | :--- |
| **Reentrancy Lock Write** | 20,000 gas (cold) / 5,000 (warm) | **100 gas** | **98% savings** |
| **Lock Release Reset** | 2,900 gas (with refund) | **100 gas** | **96% savings** |
| **Session Delta Settlement** | 20,000 gas per token write | **100 gas** | **99% savings** |

---

## Contract Size & Gas Metrics

```text
╭-------------------+------------------+-------------------+--------------------+---------------------╮
| Contract          | Runtime Size (B) | Initcode Size (B) | Runtime Margin (B) | Initcode Margin (B) |
+=====================================================================================================+
| ValenceHook       | 2,323            | 2,377             | 22,253             | 46,775              |
| ValencePool       | 2,625            | 2,964             | 21,951             | 46,188              |
╰-------------------+------------------+-------------------+--------------------+---------------------╯
```

---

## Testing & Verification

```bash
# Run unit and fuzz tests with Cancun EVM
forge test -vvv --fuzz-runs 256

# Check bytecode size margins
forge build --sizes
```

---

## License

MIT License. See [LICENSE](LICENSE) for full details.
