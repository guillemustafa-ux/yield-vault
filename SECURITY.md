# Security

Security notes for the YieldVault / AsyncVault contracts: trust model, adversarial
review, and static-analysis triage. Written for a reviewer.

- **Scope:** [`src/YieldVault.sol`](src/YieldVault.sol) (ERC-4626 with inflation
  defense + deposit cap) and [`src/AsyncVault.sol`](src/AsyncVault.sol) (ERC-7540
  async request→fulfill→claim on top of the same base). `MockUSDC` is a test asset.
  Dependencies (`lib/`) are out of scope.
- **Last reviewed:** F1 pass, 2026-07-08.
- **Prior hardening:** F0 added 4 invariants, 100% coverage on `YieldVault` and full
  line/function coverage on `AsyncVault`, plus a dedicated inflation-attack test.

> ⚠️ **Portfolio / testnet posture.** The vault `owner` (operator) is trusted to
> distribute yield and, in `AsyncVault`, to fulfill requests fairly. Not audited for
> mainnet value.

## Verification performed

| Check | Result |
|---|---|
| `forge test` | **45 passed, 0 failed** (unit + fuzz + 4 invariants + inflation attack) |
| Slither (solc via foundry) | 6 results, **none actionable** — triage below |
| Manual adversarial review | No High/Medium |

## Adversarial review

- **Inflation / donation attack.** Neutralized by `_decimalsOffset() = 6` (OZ virtual
  shares/assets). A first-depositor cannot round a victim's deposit to zero shares
  without donating ~1e6× the victim's amount. Covered by `InflationAttack.t.sol`.
- **`totalAssets()` accounting (AsyncVault).** Excludes `totalPendingDepositAssets`
  (still the depositor's) and `totalClaimableRedeemAssets` (already left the pool via
  burned shares), so a fulfilled redeem can't inflate remaining holders' price-per-share
  and pending deposits can't dilute the pool early. The raw subtraction cannot underflow:
  physical asset balance always ≥ the two reserved sums (assets only leave via a claim
  that decrements the same reserve) — this is one of the enforced invariants.
- **Rounding.** Settlement floors both directions; partial claims round the *consumed*
  side up and the *paid-out* side down, so a claimable bucket depletes at least as fast
  as proportional and no dust is extractable. The `== cAssets`/`== cShares` exact-claim
  branches settle the remainder exactly, preventing rounding residue from stranding.
- **Reentrancy.** AsyncVault has no explicit guard but follows checks-effects-
  interactions on every value-out path (state updated before the ERC-20 transfer), so a
  hook-bearing asset cannot double-claim. (The later flagship `RwaVault` adds an explicit
  guard as defense-in-depth.)
- **Access control.** `distributeYield` / `fulfill*` are `onlyOwner`; requests and
  claims are gated by the ERC-7540 operator model (`msg.sender == owner/controller ||
  isOperator[...]`).
- **Deposit cap.** Enforced by overriding `maxDeposit`/`maxMint`, which the standard
  `deposit`/`mint` consult and revert against — `maxMint` floors so the cap can't be
  exceeded via the shares path.

## Static analysis (Slither)

6 results, **all non-actionable**:

| Detector | Verdict |
|---|---|
| `arbitrary-send-erc20` (`AsyncVault.requestDeposit` `transferFrom(owner,…)`) | **False positive.** ERC-7540 operator model: `owner` is authorized by the `require` immediately above the transfer — not an arbitrary `from`. |
| `incorrect-equality` (`assets == cAssets`, `shares == cShares`, `maxAssets == type(uint256).max`) | **False positive.** Exact-claim branch selectors and the "no cap" sentinel — intentional strict equality, not exactness comparison of manipulable balances. |

## Residual risks (known, accepted)

1. **Operator trust** — `owner` sets the yield injected and (AsyncVault) the fulfill
   price/timing. Bounds on this are stronger in the flagship `rwa-yield-protocol`
   (NAV deviation band + liquidity cap); here it is a trusted role by design.

## Reporting

Personal portfolio project — open an issue or contact the author rather than disclosing
publicly.
