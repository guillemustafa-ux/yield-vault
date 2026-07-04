# YieldVault — Vault de rendimiento ERC-4626 (Solidity + Foundry)

Vault de rendimiento on-chain construido sobre el estándar **ERC-4626**, con
protección contra el **ataque de inflación**, cap de depósito y un mini dApp para
interactuar. Desplegado y **verificado en Sepolia**.

> Es la base de **ERC-7540** (vaults asíncronos), el estándar que usa la
> tokenización de activos del mundo real (**RWA** — Centrifuge, Ondo). Este repo
> es el on-ramp a ese tipo de trabajo.

| | |
|---|---|
| **Tooling** | Foundry (forge), OpenZeppelin v5.6.1, SafeERC20 |
| **Tests** | 45 passing — unit, fuzz, 4 stateful invariants |
| **Coverage** | 100% funciones en YieldVault y AsyncVault |
| **CI** | GitHub Actions — build, test suite completo, gas snapshot, coverage |

## 🔗 En vivo

| Recurso | Link |
|---|---|
| **YieldVault** (ERC-4626, verificado) | https://sepolia.etherscan.io/address/0xa32f9d514804084839b59972F8b43e616BB4E32b |
| **AsyncVault** (ERC-7540, verificado) | https://sepolia.etherscan.io/address/0xA4bf32Fa9a2E8d952a4d5bB08cd5d4C05dD11Bac |
| **MockUSDC** (verificado) | https://sepolia.etherscan.io/address/0xc10b0e68f21c5fFf30D608Fe5179ED915A24e423 |
| **dApp** | https://yield-vault-botpassfrontenddapp.vercel.app |

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
| [`src/AsyncVault.sol`](src/AsyncVault.sol) | Vault asíncrono **ERC-7540** (request → fulfill → claim + operadores) — el estándar RWA |
| [`src/MockUSDC.sol`](src/MockUSDC.sol) | Stablecoin de prueba (6 decimales, faucet abierto) |

### v2 — AsyncVault (ERC-7540): el estándar de RWA

Los activos del mundo real (crédito privado, treasuries tokenizados) **no liquidan al
instante**. Por eso ERC-7540 parte el flujo en 3 pasos:

1. **REQUEST** — el usuario pide depositar/retirar; sus fondos quedan `pending`.
2. **FULFILL** — un operador cumple la request **al precio del momento**; pasa a `claimable`.
3. **CLAIM** — el usuario reclama sus shares (o assets) ya fijados.

`AsyncVault` implementa el modelo `requestId=0` (agrega las requests por `controller`),
el patrón **operator** (delegación de cuenta), y reescribe `deposit/mint/redeem/withdraw`
para que sean funciones de **claim** (los `preview*` se deshabilitan: el precio se fija
en el fulfill, no se puede previsualizar). Hereda la protección de inflación del v1.

## Tests

```bash
export PATH="$HOME/.foundry/bin:$PATH"   # Git Bash, si forge no está en PATH
forge test -vv                            # 45 tests (unit + fuzz + invariant)
forge coverage --report summary           # 100% funciones en YieldVault y AsyncVault
forge snapshot --no-match-contract Invariant   # regenerar .gas-snapshot tras un cambio
```

45 tests en verde:
- **YieldVault** (12, 100% líneas/statements/branches/funciones): contabilidad, `preview*`, redondeo, crecimiento por yield, cap, control de acceso, fuzz.
- **AsyncVault** (28, 100% líneas/funciones): ciclo request→fulfill→claim completo (depósito Y retiro, incluidos `mint`/`withdraw` como rutas de claim), precio fijado en el fulfill, operadores, autorización, fulfill parcial, `preview*` deshabilitados, ERC-165.
- **InflationAttack** (2): vault ingenuo (víctima pierde) vs protegido (neutralizado).
- **4 invariant tests** (ver abajo): 256 secuencias aleatorias × 50 pasos cada una, 0 reverts.

## Stateful invariant testing

Unit tests prueban un escenario a la vez; los **invariantes** corren cientos de
*secuencias* aleatorias de llamadas (vía un "handler" con actores fijos) y verifican
que una propiedad se sostenga **después de cada una**:

- [`test/YieldVaultInvariant.t.sol`](test/YieldVaultInvariant.t.sol):
  - **Solvencia**: `sum(convertToAssets(balanceOf(actor)))` nunca supera `totalAssets()`
    — el vault nunca puede deberle a los actores más de lo que tiene.
  - **Precio monotónico**: el valor de 1 share nunca baja (solo sube con yield o queda igual).
- [`test/AsyncVaultInvariant.t.sol`](test/AsyncVaultInvariant.t.sol):
  - **Los 3 buckets de assets siempre cierran**: `balanceOf(vault) == totalAssets() +
    totalPendingDepositAssets + totalClaimableRedeemAssets`. Esta es LA propiedad
    crítica de un vault async — si los buckets no suman exacto el balance real del
    token, hay plata que se duplicó o se perdió en algún paso del ciclo.
  - **Precio monotónico** (mismo criterio que en YieldVault).

`forge test` corre 256 secuencias de hasta 50 llamadas cada una (`foundry.toml`,
tuneado para que CI termine en segundos; se validó primero con profundidad completa
localmente antes de bajarla).

## Deploy

```bash
cp .env.example .env   # completar SEPOLIA_RPC_URL, PRIVATE_KEY (0x...), ETHERSCAN_API_KEY
source .env
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
```

El script despliega MockUSDC + YieldVault, siembra liquidez (1.000 mUSDC) e inyecta
100 de yield para que el vault arranque con TVL y precio de share > 1.

Para el AsyncVault (ERC-7540), que reusa el mismo MockUSDC y corre el ciclo
request→fulfill→claim on-chain como demo:

```bash
forge script script/DeployAsync.s.sol --rpc-url sepolia --broadcast --verify
```

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
- [x] Deploy + verify en Sepolia + dApp (approve → deposit → redeem)
- [x] **v2 — ERC-7540** (vault asíncrono: request/fulfill/claim + operadores) → estándar RWA, desplegado + verificado
- [x] **F0 hardening**: 45 tests (100% funciones), 4 invariant tests, gas snapshot, CI en GitHub Actions
- [ ] v3 — `authorizeOperator` con firma EIP-712 + dApp del flujo async

---

_Segunda pieza de un portfolio Web3 full-stack. La primera:
[BotPass](https://github.com/guillemustafa-ux) (suscripción on-chain como NFT)._
