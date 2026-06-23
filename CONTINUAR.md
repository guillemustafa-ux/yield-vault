# CONTINUAR — YieldVault (handoff entre sesiones)

> Archivo para retomar el proyecto en una sesión nueva sin perder contexto.

## Dónde estamos (2026-06-23)

Segunda pieza de portfolio Solidity (después de BotPass). **Vault ERC-4626 completo,
desplegado y verificado en Sepolia, con dApp.** ✅

- `src/MockUSDC.sol` — stablecoin de prueba (6 decimales), `mint` abierto (faucet).
- `src/YieldVault.sol` — vault ERC-4626 + `Ownable`. Claves:
  - `_decimalsOffset() = 6` → virtual shares (protección de ataque de inflación).
  - `distributeYield(amount)` only-owner → sube el precio del share sin emitir shares.
  - `depositCap` + override de `maxDeposit`/`maxMint` (cap aplicado por el estándar).
- `test/YieldVault.t.sol` (12) · `test/InflationAttack.t.sol` (2: vault ingenuo vs protegido).
  **Total: 14 tests en verde.** `forge test -vv`.
- `script/Deploy.s.sol` — despliega ambos + siembra liquidez/yield. Probado en anvil y en Sepolia.
- `frontend/dapp/` — Vite + React + ethers + Tailwind (copiado del template de BotPass).
  Hook `useVault.ts`, componente `VaultCard.tsx`, flujo approve→deposit→redeem.
- Entorno: forge 1.7.1, OZ v5.6.1, forge-std v1.16.1.

### ✅ DESPLEGADO Y VERIFICADO EN SEPOLIA (2026-06-23)

- **YieldVault:** `0xa32f9d514804084839b59972F8b43e616BB4E32b`
  https://sepolia.etherscan.io/address/0xa32f9d514804084839b59972f8b43e616bb4e32b
- **MockUSDC:** `0xc10b0e68f21c5fFf30D608Fe5179ED915A24e423`
  https://sepolia.etherscan.io/address/0xc10b0e68f21c5fff30d608fe5179ed915a24e423
- Wallet de deploy: `0x40b282c45EE5667fB72b4D37a676A0110cEe36d5` (misma que BotPass).
- Estado al deploy: TVL 1.100 mUSDC, precio del share ≈ 1.099999, cap 1.000.000 mUSDC.

## Cómo correr / desplegar

```bash
export PATH="$HOME/.foundry/bin:$PATH"
cd /c/Users/Cript/yield-vault
forge test -vv
# deploy (con .env completo, PRIVATE_KEY con prefijo 0x):
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
```

## Próximo paso (v2): ERC-7540 — vault ASÍNCRONO

Es el estándar que piden los jobs de **RWA** (lo escribió Centrifuge). Es
ERC-4626 + flujos `requestDeposit` / `requestRedeem` que se cumplen en 2 pasos
(T+1/T+2), porque el activo del mundo real no es líquido al instante.

- Implementar `IERC7540` (request/fulfill de depósito y redención).
- Rol de "operator" que cumple las requests.
- Tests del ciclo request → fulfill → claim.
- Sería la pieza que pega directo con los leads RWA (ver memoria del usuario).

## Roadmap

- [x] Vault ERC-4626 (offset anti-inflación, cap, yield) + 14 tests
- [x] Deploy + verify Sepolia
- [x] dApp approve→deposit→redeem
- [ ] v2 — ERC-7540 async (RWA)

## Cómo retomar en sesión nueva

> Retomemos el proyecto YieldVault de Solidity. Está en C:\Users\Cript\yield-vault.
> Leé CONTINUAR.md y seguimos desde el próximo paso (v2 ERC-7540).
