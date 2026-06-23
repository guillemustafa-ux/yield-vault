// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ERC4626 = el estándar de "vaults" (bóvedas) que generan rendimiento. Define una
// API común: depositás un activo (assets) y recibís "shares" (acciones del vault).
// El precio de cada share sube a medida que entra rendimiento. Lo usan Aave, Morpho,
// Yearn... y es la base de ERC-7540 (vaults async) que piden los jobs de RWA.
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title YieldVault — vault ERC-4626 con protección de inflación y cap de depósito
/// @notice Depositás mUSDC y recibís shares (bpvUSDC). El owner inyecta rendimiento
///         con `distributeYield`, lo que sube el valor de cada share sin emitir nuevas.
///         Así, quien depositó antes gana: sus mismas shares valen más assets.
/// @dev Tres conceptos de Solidity que ejercita este contrato:
///      1. Herencia múltiple (ERC4626 + Ownable) y paso de args al constructor.
///      2. Override de hooks del estándar (_decimalsOffset, maxDeposit, maxMint).
///      3. El ataque de inflación/donación de vaults y cómo se neutraliza.
contract YieldVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Tope de assets totales que el vault acepta. Sabor "RWA": los vaults
    ///         de activos del mundo real casi siempre tienen un cupo. type(uint256).max = sin tope.
    uint256 public depositCap;

    event YieldDistributed(address indexed from, uint256 amount, uint256 newTotalAssets);
    event DepositCapSet(uint256 newCap);

    /// @dev El constructor alimenta a los 3 constructores que heredamos:
    ///      - ERC4626 quiere SABER cuál es el activo subyacente (asset_).
    ///      - ERC20 quiere nombre y símbolo del token de shares.
    ///      - Ownable quiere el dueño inicial (quien despliega).
    constructor(IERC20 asset_, uint256 cap_)
        ERC4626(asset_)
        ERC20("BotPass Yield Vault Share", "bpvUSDC")
        Ownable(msg.sender)
    {
        depositCap = cap_;
        emit DepositCapSet(cap_);
    }

    // ----------------------------------------------------------------------
    // Protección contra el ATAQUE DE INFLACIÓN (a.k.a. donation attack)
    // ----------------------------------------------------------------------
    // El ataque clásico: el atacante es el PRIMER depositante. Deposita 1 wei,
    // recibe 1 share, y después "dona" (transfiere directo al vault) una suma
    // grande. Eso infla el precio del share. Cuando una víctima deposita, su
    // monto se divide por un precio enorme y REDONDEA A 0 shares: pierde su plata
    // y el atacante se la queda.
    //
    // Mitigación de OpenZeppelin: "virtual shares". `_decimalsOffset()` agrega
    // 10**offset shares virtuales y +1 asset virtual al cálculo. Eso hace que el
    // precio nunca se pueda inflar barato: para zero-out una víctima, el atacante
    // tendría que donar ~10**offset veces el depósito de la víctima — absurdo.
    // Devolvemos 6: con el activo de 6 decimales, las shares quedan en 12 decimales.

    /// @dev override del hook de OZ. Sin esto el offset sería 0 (vault vulnerable).
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return 6;
    }

    // ----------------------------------------------------------------------
    // Cap de depósito: override de los hooks maxDeposit / maxMint del estándar.
    // ERC4626.deposit()/mint() consultan estos máximos y revierten si se exceden,
    // así que con solo pisarlos el cupo queda aplicado automáticamente.
    // ----------------------------------------------------------------------

    /// @notice Cuántos assets más se pueden depositar antes de llegar al cap.
    function maxDeposit(address) public view override returns (uint256) {
        uint256 cap = depositCap;
        if (cap == type(uint256).max) return type(uint256).max; // sin tope
        uint256 assets = totalAssets();
        return assets >= cap ? 0 : cap - assets;
    }

    /// @notice Lo mismo que maxDeposit pero expresado en shares (para mint()).
    function maxMint(address receiver) public view override returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (maxAssets == type(uint256).max) return type(uint256).max;
        // Redondeo Floor: nunca dejamos mintear de más respecto al cupo en assets.
        return _convertToShares(maxAssets, Math.Rounding.Floor);
    }

    // ----------------------------------------------------------------------
    // Rendimiento e administración
    // ----------------------------------------------------------------------

    /// @notice El owner inyecta rendimiento: transfiere `amount` de asset al vault.
    ///         No se emiten shares nuevas, así que totalAssets sube y cada share
    ///         pasa a valer más. (En un vault real, este "yield" vendría de prestar
    ///         el activo, de un RWA que paga interés, etc.)
    /// @dev SafeERC20 soporta tokens no estándar (USDT real no devuelve bool).
    function distributeYield(uint256 amount) external onlyOwner {
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        emit YieldDistributed(msg.sender, amount, totalAssets());
    }

    /// @notice Cambiar el cupo (p. ej. ampliarlo a medida que crece la confianza).
    function setDepositCap(uint256 newCap) external onlyOwner {
        depositCap = newCap;
        emit DepositCapSet(newCap);
    }
}
