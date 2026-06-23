// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Vault "ingenuo": NO pisa _decimalsOffset, así que el offset queda en 0
///      (el default de OZ). Lo usamos solo para mostrar el ataque SIN proteccion.
contract NaiveVault is ERC4626 {
    constructor(IERC20 asset_) ERC4626(asset_) ERC20("Naive Share", "nSHARE") {}
}

/// @title Demostracion del ataque de inflacion / donacion en vaults ERC-4626
/// @notice Espeja el estilo de ReentrancyAttack.t.sol de BotPass: primero
///         reproducimos el ataque en un vault SIN proteccion (la victima pierde
///         su deposito), y despues probamos que el YieldVault con virtual shares
///         lo neutraliza (la victima recupera casi todo y el atacante pierde plata).
contract InflationAttackTest is Test {
    MockUSDC internal usdc;

    address internal attacker = makeAddr("attacker");
    address internal victim = makeAddr("victim");

    uint256 internal constant USDC = 1e6;
    uint256 internal constant DONATION = 10_000 * USDC; // lo que el atacante "regala" al vault
    uint256 internal constant VICTIM_DEPOSIT = 1 * USDC; // 1 mUSDC

    function setUp() public {
        usdc = new MockUSDC();
        usdc.mint(attacker, DONATION + 100 * USDC);
        usdc.mint(victim, 100 * USDC);
    }

    /// @notice SIN proteccion (offset 0): el ataque funciona y la victima pierde todo.
    function test_NaiveVault_VictimGetsZeroShares() public {
        NaiveVault naive = new NaiveVault(IERC20(address(usdc)));

        // 1) El atacante deposita 1 wei y recibe 1 share.
        vm.startPrank(attacker);
        usdc.approve(address(naive), type(uint256).max);
        naive.deposit(1, attacker);
        // 2) Dona una suma grande directo al vault para inflar el precio del share.
        usdc.transfer(address(naive), DONATION);
        vm.stopPrank();

        // 3) La victima deposita 1 mUSDC: su monto se divide por el precio inflado
        //    y REDONDEA A 0 shares. Pierde su deposito (queda en el pool del atacante).
        vm.startPrank(victim);
        usdc.approve(address(naive), type(uint256).max);
        uint256 victimShares = naive.deposit(VICTIM_DEPOSIT, victim);
        vm.stopPrank();

        assertEq(victimShares, 0, "sin proteccion la victima deberia recibir 0 shares");
    }

    /// @notice CON proteccion (YieldVault, offset 6): el ataque se neutraliza.
    function test_YieldVault_NeutralizesAttack() public {
        YieldVault vault = new YieldVault(IERC20(address(usdc)), type(uint256).max);

        uint256 attackerSpent = 1 + DONATION; // deposito + donacion

        // Mismo ataque, paso a paso.
        vm.startPrank(attacker);
        usdc.approve(address(vault), type(uint256).max);
        uint256 attackerShares = vault.deposit(1, attacker);
        usdc.transfer(address(vault), DONATION);
        vm.stopPrank();

        vm.startPrank(victim);
        usdc.approve(address(vault), type(uint256).max);
        uint256 victimShares = vault.deposit(VICTIM_DEPOSIT, victim);
        vm.stopPrank();

        // (a) La victima recibe shares > 0: NO la pueden zero-out.
        assertGt(victimShares, 0, "la victima quedo con 0 shares");

        // (b) La victima recupera >= 99% de su deposito.
        uint256 victimValue = vault.convertToAssets(victimShares);
        assertGe(victimValue, (VICTIM_DEPOSIT * 99) / 100, "la victima perdio demasiado");

        // (c) El ataque es ANTIECONOMICO: el atacante recupera menos de lo que gasto.
        uint256 attackerValue = vault.convertToAssets(attackerShares);
        assertLt(attackerValue, attackerSpent, "el ataque resulto rentable (no deberia)");
    }
}
