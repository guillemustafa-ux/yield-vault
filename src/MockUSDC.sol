// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ERC20 ya hecho y auditado de OpenZeppelin. Heredamos todo (transfer, approve,
// allowance, balanceOf...) y solo ajustamos decimales + agregamos un faucet.
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC — stablecoin de PRUEBA para usar como activo subyacente del vault
/// @notice Imita a USDC: 6 decimales (no 18 como el ETH). Tiene un `mint` ABIERTO
///         a propósito, para que cualquiera que pruebe el dApp en testnet pueda
///         conseguir tokens y depositar. NUNCA usar este patrón en mainnet.
/// @dev Que el activo tenga 6 decimales es clave: combinado con el offset del vault,
///      es lo que ejercita la contabilidad de shares/assets de ERC-4626.
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USD Coin", "mUSDC") {}

    /// @dev USDC real usa 6 decimales. ERC20 base devuelve 18, así que lo pisamos.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Faucet de testnet: cualquiera mintea para sí mismo y prueba el vault.
    ///         (En un token real esto estaría protegido con onlyOwner o no existiría.)
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
