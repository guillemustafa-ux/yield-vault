# CONTINUAR — YieldVault (handoff entre sesiones)

> Archivo para retomar el proyecto en una sesión nueva sin perder contexto.

## Dónde estamos (2026-06-23)

Segunda pieza de portfolio Solidity (después de BotPass). **Vault ERC-4626 (v1) + vault
asíncrono ERC-7540 (v2), ambos desplegados y verificados en Sepolia, con dApp del v1.** ✅

- `src/MockUSDC.sol` — stablecoin de prueba (6 decimales), `mint` abierto (faucet).
- `src/YieldVault.sol` — vault ERC-4626 + `Ownable`. Claves:
  - `_decimalsOffset() = 6` → virtual shares (protección de ataque de inflación).
  - `distributeYield(amount)` only-owner → sube el precio del share sin emitir shares.
  - `depositCap` + override de `maxDeposit`/`maxMint` (cap aplicado por el estándar).
- `src/AsyncVault.sol` — **v2, ERC-7540** sobre ERC-4626. Claves:
  - Ciclo `requestDeposit/requestRedeem` → `fulfillDeposit/fulfillRedeem` (onlyOwner) → claim.
  - `deposit/mint/redeem/withdraw` reescritos como CLAIM; `preview*` revierten.
  - Patrón operator (`setOperator`/`isOperator`), modelo `requestId=0`, ERC-165.
  - `totalAssets()` excluye pending-deposit y claimable-redeem (contabilidad correcta).
- `test/YieldVault.t.sol` (12) · `test/AsyncVault.t.sol` (10) · `test/InflationAttack.t.sol` (2).
  **Total: 24 tests en verde.** `forge test -vv`.
- `script/Deploy.s.sol` (v1) y `script/DeployAsync.s.sol` (v2). Probados en anvil/simulación y en Sepolia.
- `frontend/dapp/` — Vite + React + ethers + Tailwind (dApp del v1 sincrónico).
  Hook `useVault.ts`, componente `VaultCard.tsx`, flujo approve→deposit→redeem.
- Entorno: forge 1.7.1, OZ v5.6.1, forge-std v1.16.1.

### ✅ DESPLEGADO Y VERIFICADO EN SEPOLIA (2026-06-23)

- **YieldVault (v1, ERC-4626):** `0xa32f9d514804084839b59972F8b43e616BB4E32b`
  https://sepolia.etherscan.io/address/0xa32f9d514804084839b59972f8b43e616bb4e32b
- **AsyncVault (v2, ERC-7540):** `0xA4bf32Fa9a2E8d952a4d5bB08cd5d4C05dD11Bac`
  https://sepolia.etherscan.io/address/0xa4bf32fa9a2e8d952a4d5bb08cd5d4c05dd11bac
- **MockUSDC (compartido):** `0xc10b0e68f21c5fFf30D608Fe5179ED915A24e423`
  https://sepolia.etherscan.io/address/0xc10b0e68f21c5fff30d608fe5179ed915a24e423
- Wallet de deploy: `0x40b282c45EE5667fB72b4D37a676A0110cEe36d5` (misma que BotPass).
- Estado: YieldVault TVL 1.100 mUSDC (share ≈ 1.0999). AsyncVault TVL 1.100 mUSDC (ciclo async corrido on-chain).

## Cómo correr / desplegar

```bash
export PATH="$HOME/.foundry/bin:$PATH"
cd /c/Users/Cript/yield-vault
forge test -vv
# deploy (con .env completo, PRIVATE_KEY con prefijo 0x):
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
```

## Próximo paso (v3)

El v2 ERC-7540 ya está hecho. Opciones para seguir:
- **`authorizeOperator` con firma EIP-712** (el EIP-7540 lo incluye): delegar operador
  con una firma off-chain en vez de una tx. Ejercita EIP-712/typed data.
- **dApp del flujo async**: UI request → (botón fulfill del owner) → claim. Muestra el
  ciclo de RWA en vivo, muy vendible para los leads RWA.
- **requestId no-cero** (modelo de requests individuales, tipo NFT) en vez de agregado.

## Roadmap

- [x] Vault ERC-4626 (offset anti-inflación, cap, yield) + dApp approve→deposit→redeem
- [x] v2 — ERC-7540 async (request/fulfill/claim + operadores) — desplegado + verificado
- [x] 24 tests Foundry en verde
- [ ] v3 — EIP-712 authorizeOperator / dApp async / requestId no-cero

## Cómo retomar en sesión nueva

> Retomemos el proyecto YieldVault de Solidity. Está en C:\Users\Cript\yield-vault.
> Leé CONTINUAR.md y seguimos desde el próximo paso (v2 ERC-7540).
