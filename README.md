# YieldVault — Vault de rendimiento ERC-4626 (Solidity + Foundry)

Vault de rendimiento on-chain construido sobre el estándar **ERC-4626**, con
protección contra el **ataque de inflación**, cap de depósito y un mini dApp para
interactuar. Desplegado y **verificado en Sepolia**.

> Es la base de **ERC-7540** (vaults asíncronos), el estándar que usa la
> tokenización de activos del mundo real (**RWA** — Centrifuge, Ondo). Este repo
> es el on-ramp a ese tipo de trabajo.

## 🔗 En vivo

| Recurso | Link |
|---|---|
| **YieldVault** (verificado) | https://sepolia.etherscan.io/address/0xa32f9d514804084839b59972F8b43e616BB4E32b |
| **MockUSDC** (verificado) | https://sepolia.etherscan.io/address/0xc10b0e68f21c5fFf30D608Fe5179ED915A24e423 |
| **dApp** | _(ver despliegue en Vercel)_ |

## ¿Qué hace?

- Depositás `mUSDC` (un USDC de prueba, 6 decimales) y recibís **shares** del vault (ERC-4626).
- El owner inyecta rendimiento con `distributeYield`: sube `totalAssets` **sin emitir
  nuevas shares**, así cada share pasa a valer más. Quien depositó antes, gana.
- Tope de depósito (`depositCap`) con sabor RWA: los vaults institucionales casi
  siempre tienen cupo.

## Conceptos de Solidity que demuestra

1. **Herencia múltiple** (`ERC4626 + Ownable`) y paso de argumentos a constructores heredados.
2. **Override de los hooks del estándar**: `_decimalsOffset`, `maxDeposit`, `maxMint`.
3. **Contabilidad shares/assets** y **dirección de redondeo** (el vault siempre redondea a su favor).
4. **El ataque de inflación / donación** y cómo se neutraliza con *virtual shares*.

### El ataque de inflación (lo importante)

Sin protección, el primer depositante puede depositar 1 wei, **donar** una suma
grande directo al vault para inflar el precio del share, y hacer que el depósito de
la víctima **redondee a 0 shares** — robándoselo. La mitigación de OpenZeppelin
(`_decimalsOffset()` → *virtual shares*) hace que ese ataque sea antieconómico.

El test `test/InflationAttack.t.sol` lo demuestra de forma contrastada:
- **Vault ingenuo** (offset 0): la víctima recibe **0 shares** y pierde su depósito.
- **YieldVault** (offset 6): la víctima recibe shares, recupera ~99% de su depósito,
  y el ataque le sale **caro al atacante**.

## Contratos

| Archivo | Qué es |
|---|---|
| [`src/YieldVault.sol`](src/YieldVault.sol) | Vault ERC-4626 + protección de inflación + cap + yield |
| [`src/MockUSDC.sol`](src/MockUSDC.sol) | Stablecoin de prueba (6 decimales, faucet abierto) |

## Tests

```bash
export PATH="$HOME/.foundry/bin:$PATH"   # Git Bash, si forge no está en PATH
forge test -vv
```

14 tests en verde: contabilidad, `preview*`, redondeo, crecimiento por yield, cap,
control de acceso, fuzzing de round-trip y el demo de ataque de inflación.

## Deploy

```bash
cp .env.example .env   # completar SEPOLIA_RPC_URL, PRIVATE_KEY (0x...), ETHERSCAN_API_KEY
source .env
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
```

El script despliega MockUSDC + YieldVault, siembra liquidez (1.000 mUSDC) e inyecta
100 de yield para que el vault arranque con TVL y precio de share > 1.

## dApp (frontend)

```bash
cd frontend/dapp
npm install
npm run dev
```

Vite + React + ethers + Tailwind. Conectás MetaMask en Sepolia, usás el faucet para
conseguir mUSDC, y probás el flujo **approve → deposit → redeem** viendo cómo sube el
precio del share cuando entra rendimiento.

## Stack

`Solidity 0.8.24` · `Foundry` · `OpenZeppelin v5.6.1` · `ethers v6` · `React + Vite`

## Roadmap

- [x] Vault ERC-4626 con protección de inflación, cap y yield
- [x] 14 tests Foundry (incluye demo de ataque de inflación + fuzz)
- [x] Deploy + verify en Sepolia
- [x] dApp (approve → deposit → redeem)
- [ ] **v2 — ERC-7540** (vault asíncrono: request/fulfill) → estándar RWA

---

_Segunda pieza de un portfolio Web3 full-stack. La primera:
[BotPass](https://github.com/guillemustafa-ux) (suscripción on-chain como NFT)._
