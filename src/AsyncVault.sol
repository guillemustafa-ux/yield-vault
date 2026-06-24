// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ERC-7540 = "Asynchronous Tokenized Vaults". Extiende ERC-4626 para activos que
// NO liquidan al instante (crédito privado, treasuries tokenizados, RWA en general).
// En vez de depositar/retirar en una sola tx, el flujo es en 3 pasos:
//
//   1. REQUEST  — el usuario pide depositar/retirar; sus fondos quedan "pending".
//   2. FULFILL  — un operador (off-chain decide, on-chain ejecuta) cumple la request
//                 al precio del momento; pasa de "pending" a "claimable".
//   3. CLAIM    — el usuario reclama sus shares (o sus assets) ya fijados.
//
// Lo escribió el equipo de Centrifuge. Es el estándar que piden los jobs de RWA.
// Esta implementación usa el modelo requestId=0 (todas las requests de un mismo
// "controller" se agregan; no se trackean IDs por separado).
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title AsyncVault — vault asíncrono ERC-7540 (request → fulfill → claim)
/// @notice Construido sobre el YieldVault ERC-4626 de este repo. Mantiene la
///         protección de inflación (virtual shares) y agrega el ciclo async de RWA.
/// @dev Conceptos de Solidity que ejercita, además de los del ERC-4626:
///      - Máquina de estados pending → claimable por controller.
///      - Patrón "operator" (delegación de cuenta, como en ERC-1155/7540).
///      - Override profundo del estándar: deposit/mint/redeem/withdraw pasan a ser
///        funciones de CLAIM (no mueven fondos nuevos), y los preview* se deshabilitan
///        (el precio se fija en el fulfill, no se puede previsualizar).
///      - Contabilidad de totalAssets que separa lo "pending" de lo que está en el pool.
contract AsyncVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @dev En el modelo agregado, todas las requests viven bajo el id 0.
    uint256 public constant REQUEST_ID = 0;

    // --- Estado del ciclo de DEPÓSITO (por controller) ---
    mapping(address => uint256) public pendingDeposit; // assets pedidos, sin cumplir
    mapping(address => uint256) public claimableDepositAssets; // assets cumplidos, a reclamar
    mapping(address => uint256) public claimableDepositShares; // shares reservadas para esos assets

    // --- Estado del ciclo de RETIRO (por controller) ---
    mapping(address => uint256) public pendingRedeem; // shares pedidas, sin cumplir
    mapping(address => uint256) public claimableRedeemShares; // shares cumplidas, a reclamar
    mapping(address => uint256) public claimableRedeemAssets; // assets reservados para esas shares

    // --- Operadores: isOperator[controller][operator] ---
    mapping(address => mapping(address => bool)) public isOperator;

    // Acumuladores para que totalAssets() refleje SOLO lo que está en el pool:
    //  - los assets "pending deposit" están en el balance pero todavía son del usuario.
    //  - los assets reservados para redenciones cumplidas ya salieron del pool (shares quemadas).
    uint256 public totalPendingDepositAssets;
    uint256 public totalClaimableRedeemAssets;

    // --- Eventos del estándar ERC-7540 ---
    event DepositRequest(
        address indexed controller,
        address indexed owner,
        uint256 indexed requestId,
        address sender,
        uint256 assets
    );
    event RedeemRequest(
        address indexed controller,
        address indexed owner,
        uint256 indexed requestId,
        address sender,
        uint256 shares
    );
    event OperatorSet(address indexed controller, address indexed operator, bool approved);
    event YieldDistributed(address indexed from, uint256 amount, uint256 newTotalAssets);

    // --- Eventos propios del settlement (no son parte del EIP) ---
    event DepositFulfilled(address indexed controller, uint256 assets, uint256 shares);
    event RedeemFulfilled(address indexed controller, uint256 shares, uint256 assets);

    error NotAuthorized();
    error ZeroAmount();
    error ExceedsPending();
    error ExceedsClaimable();
    error PreviewDisabled();

    constructor(IERC20 asset_)
        ERC4626(asset_)
        ERC20("Async RWA Vault Share", "aRWA")
        Ownable(msg.sender)
    {}

    /// @dev Misma protección de inflación que el YieldVault sincrónico.
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return 6;
    }

    /// @notice El owner inyecta rendimiento (el RWA paga interés). Sube totalAssets
    ///         sin emitir shares → el precio del share sube para los holders del pool.
    function distributeYield(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        emit YieldDistributed(msg.sender, amount, totalAssets());
    }

    // ----------------------------------------------------------------------
    // totalAssets: solo cuenta lo que realmente respalda a las shares del pool.
    // ----------------------------------------------------------------------
    function totalAssets() public view override returns (uint256) {
        return
            IERC20(asset()).balanceOf(address(this)) -
            totalPendingDepositAssets -
            totalClaimableRedeemAssets;
    }

    // ----------------------------------------------------------------------
    // Operadores (un controller delega a un operador para actuar por él)
    // ----------------------------------------------------------------------
    function setOperator(address operator, bool approved) external returns (bool) {
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    // ----------------------------------------------------------------------
    // 1) REQUEST
    // ----------------------------------------------------------------------

    /// @notice Pide depositar `assets`. Los fondos salen de `owner` y quedan pending
    ///         bajo `controller`. msg.sender debe ser `owner` o su operador.
    function requestDeposit(uint256 assets, address controller, address owner)
        external
        returns (uint256 requestId)
    {
        if (assets == 0) revert ZeroAmount();
        if (msg.sender != owner && !isOperator[owner][msg.sender]) revert NotAuthorized();

        IERC20(asset()).safeTransferFrom(owner, address(this), assets);
        pendingDeposit[controller] += assets;
        totalPendingDepositAssets += assets;

        emit DepositRequest(controller, owner, REQUEST_ID, msg.sender, assets);
        return REQUEST_ID;
    }

    /// @notice Pide retirar `shares`. Las shares salen de `owner` (quedan en custodia
    ///         del vault) y quedan pending bajo `controller`.
    function requestRedeem(uint256 shares, address controller, address owner)
        external
        returns (uint256 requestId)
    {
        if (shares == 0) revert ZeroAmount();
        if (msg.sender != owner && !isOperator[owner][msg.sender]) revert NotAuthorized();

        _transfer(owner, address(this), shares); // custodia las shares hasta el claim
        pendingRedeem[controller] += shares;

        emit RedeemRequest(controller, owner, REQUEST_ID, msg.sender, shares);
        return REQUEST_ID;
    }

    // ----------------------------------------------------------------------
    // 2) FULFILL (lo ejecuta el owner del vault = el "operador" del protocolo)
    // ----------------------------------------------------------------------

    /// @notice Cumple parte (o todo) del depósito pending de `controller` al precio actual.
    function fulfillDeposit(address controller, uint256 assets)
        external
        onlyOwner
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        if (assets > pendingDeposit[controller]) revert ExceedsPending();

        // Precio actual: los `assets` pending todavía NO están en el pool (los excluye
        // totalAssets), así que convertToShares los valúa contra el pool real.
        shares = convertToShares(assets);

        pendingDeposit[controller] -= assets;
        totalPendingDepositAssets -= assets; // ahora estos assets pasan a respaldar el pool
        _mint(address(this), shares); // las shares quedan en custodia hasta el claim

        claimableDepositAssets[controller] += assets;
        claimableDepositShares[controller] += shares;

        emit DepositFulfilled(controller, assets, shares);
    }

    /// @notice Cumple parte (o todo) del retiro pending de `controller` al precio actual.
    function fulfillRedeem(address controller, uint256 shares)
        external
        onlyOwner
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();
        if (shares > pendingRedeem[controller]) revert ExceedsPending();

        assets = convertToAssets(shares);

        pendingRedeem[controller] -= shares;
        _burn(address(this), shares); // quema las shares en custodia
        totalClaimableRedeemAssets += assets; // reserva los assets fuera del pool

        claimableRedeemShares[controller] += shares;
        claimableRedeemAssets[controller] += assets;

        emit RedeemFulfilled(controller, shares, assets);
    }

    // ----------------------------------------------------------------------
    // 3) CLAIM — deposit/mint/redeem/withdraw dejan de mover fondos nuevos y
    //            pasan a entregar lo ya cumplido. (Override del ERC-4626.)
    // ----------------------------------------------------------------------

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        return deposit(assets, receiver, msg.sender);
    }

    /// @notice Reclama shares por `assets` de lo ya cumplido para `controller`.
    function deposit(uint256 assets, address receiver, address controller)
        public
        returns (uint256 shares)
    {
        if (msg.sender != controller && !isOperator[controller][msg.sender]) revert NotAuthorized();
        if (assets == 0) revert ZeroAmount();
        uint256 cAssets = claimableDepositAssets[controller];
        if (assets > cAssets) revert ExceedsClaimable();

        uint256 cShares = claimableDepositShares[controller];
        shares = assets == cAssets ? cShares : assets.mulDiv(cShares, cAssets);

        claimableDepositAssets[controller] = cAssets - assets;
        claimableDepositShares[controller] = cShares - shares;

        _transfer(address(this), receiver, shares); // entrega las shares en custodia
        emit Deposit(controller, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256) {
        return mint(shares, receiver, msg.sender);
    }

    /// @notice Reclama `shares` exactas de lo ya cumplido para `controller`.
    function mint(uint256 shares, address receiver, address controller)
        public
        returns (uint256 assets)
    {
        if (msg.sender != controller && !isOperator[controller][msg.sender]) revert NotAuthorized();
        if (shares == 0) revert ZeroAmount();
        uint256 cShares = claimableDepositShares[controller];
        if (shares > cShares) revert ExceedsClaimable();

        uint256 cAssets = claimableDepositAssets[controller];
        assets = shares == cShares ? cAssets : shares.mulDiv(cAssets, cShares, Math.Rounding.Ceil);

        claimableDepositShares[controller] = cShares - shares;
        claimableDepositAssets[controller] = cAssets - assets;

        _transfer(address(this), receiver, shares);
        emit Deposit(controller, receiver, assets, shares);
    }

    /// @notice Reclama assets quemando `shares` ya cumplidas (3er arg = controller).
    function redeem(uint256 shares, address receiver, address controller)
        public
        override
        returns (uint256 assets)
    {
        if (msg.sender != controller && !isOperator[controller][msg.sender]) revert NotAuthorized();
        if (shares == 0) revert ZeroAmount();
        uint256 cShares = claimableRedeemShares[controller];
        if (shares > cShares) revert ExceedsClaimable();

        uint256 cAssets = claimableRedeemAssets[controller];
        assets = shares == cShares ? cAssets : shares.mulDiv(cAssets, cShares);

        claimableRedeemShares[controller] = cShares - shares;
        claimableRedeemAssets[controller] = cAssets - assets;
        totalClaimableRedeemAssets -= assets;

        IERC20(asset()).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    /// @notice Reclama `assets` exactos de lo ya cumplido (3er arg = controller).
    function withdraw(uint256 assets, address receiver, address controller)
        public
        override
        returns (uint256 shares)
    {
        if (msg.sender != controller && !isOperator[controller][msg.sender]) revert NotAuthorized();
        if (assets == 0) revert ZeroAmount();
        uint256 cAssets = claimableRedeemAssets[controller];
        if (assets > cAssets) revert ExceedsClaimable();

        uint256 cShares = claimableRedeemShares[controller];
        shares = assets == cAssets ? cShares : assets.mulDiv(cShares, cAssets, Math.Rounding.Ceil);

        claimableRedeemAssets[controller] = cAssets - assets;
        claimableRedeemShares[controller] = cShares - shares;
        totalClaimableRedeemAssets -= assets;

        IERC20(asset()).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    // ----------------------------------------------------------------------
    // Vistas del estándar ERC-7540
    // ----------------------------------------------------------------------
    function pendingDepositRequest(uint256, address controller) external view returns (uint256) {
        return pendingDeposit[controller];
    }

    function claimableDepositRequest(uint256, address controller) external view returns (uint256) {
        return claimableDepositAssets[controller];
    }

    function pendingRedeemRequest(uint256, address controller) external view returns (uint256) {
        return pendingRedeem[controller];
    }

    function claimableRedeemRequest(uint256, address controller) external view returns (uint256) {
        return claimableRedeemShares[controller];
    }

    // max*: en un vault async, el máximo a "depositar/retirar" (=reclamar) es lo claimable.
    function maxDeposit(address controller) public view override returns (uint256) {
        return claimableDepositAssets[controller];
    }

    function maxMint(address controller) public view override returns (uint256) {
        return claimableDepositShares[controller];
    }

    function maxRedeem(address controller) public view override returns (uint256) {
        return claimableRedeemShares[controller];
    }

    function maxWithdraw(address controller) public view override returns (uint256) {
        return claimableRedeemAssets[controller];
    }

    // El precio se fija en el fulfill: previsualizar no tiene sentido. El EIP exige revert.
    function previewDeposit(uint256) public pure override returns (uint256) {
        revert PreviewDisabled();
    }

    function previewMint(uint256) public pure override returns (uint256) {
        revert PreviewDisabled();
    }

    function previewWithdraw(uint256) public pure override returns (uint256) {
        revert PreviewDisabled();
    }

    function previewRedeem(uint256) public pure override returns (uint256) {
        revert PreviewDisabled();
    }

    // ----------------------------------------------------------------------
    // ERC-165: anunciamos soporte de operadores + depósito async + retiro async.
    // ----------------------------------------------------------------------
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC-165
            interfaceId == 0xe3bc4e65 || // métodos de operador (ERC-7540)
            interfaceId == 0xce3bbe50 || // depósito asíncrono
            interfaceId == 0x620ee8e4; // redención asíncrona
    }
}
