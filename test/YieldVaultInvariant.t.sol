// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Handler con actores fijos y montos acotados, para que el fuzzer
///      explore secuencias realistas de deposit/redeem/yield sobre las
///      mismas wallets (en vez de direcciones aleatorias que casi nunca repiten).
contract YieldVaultHandler is Test {
    YieldVault public vault;
    MockUSDC public usdc;
    address public owner;

    address[] internal actors;
    uint256 internal constant USDC = 1e6;

    constructor(YieldVault _vault, MockUSDC _usdc, address _owner) {
        vault = _vault;
        usdc = _usdc;
        owner = _owner;
        for (uint256 i = 0; i < 5; i++) {
            address a = makeAddr(string(abi.encodePacked("vaultActor", i)));
            actors.push(a);
            vm.prank(a);
            usdc.approve(address(vault), type(uint256).max);
        }
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function deposit(uint256 actorSeed, uint256 amountSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 amount = bound(amountSeed, 1, 10_000 * USDC);

        usdc.mint(actor, amount);
        vm.prank(actor);
        try vault.deposit(amount, actor) {} catch {}
    }

    function redeem(uint256 actorSeed, uint256 sharesSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 balance = vault.balanceOf(actor);
        if (balance == 0) return;
        uint256 shares = bound(sharesSeed, 1, balance);

        vm.prank(actor);
        try vault.redeem(shares, actor, actor) {} catch {}
    }

    /// @dev Solo el owner puede inyectar yield; el handler simula eso mintéandole
    ///      tokens y pidiéndole que llame distributeYield.
    function distributeYield(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 1, 1_000 * USDC);
        usdc.mint(owner, amount);

        vm.startPrank(owner);
        usdc.approve(address(vault), amount);
        try vault.distributeYield(amount) {} catch {}
        vm.stopPrank();
    }
}

/// @title Invariant test — YieldVault: solvencia y precio del share nunca decrece
/// @notice Dos propiedades que DEBEN sostenerse tras cualquier secuencia de
///         deposit/redeem/distributeYield:
///
///         1. **Solvencia**: la suma de lo que el vault le "debe" en assets a
///            cada actor (`convertToAssets(balanceOf(actor))`) nunca puede superar
///            `totalAssets()` — si superara, alguien no podría cobrar lo suyo.
///         2. **Precio monotónico**: el valor de 1 share nunca BAJA. Solo puede
///            subir (yield) o quedar igual; nunca hay una operación normal que
///            le haga perder valor a quien ya tiene shares.
contract YieldVaultInvariantTest is StdInvariant, Test {
    YieldVault internal vault;
    MockUSDC internal usdc;
    YieldVaultHandler internal handler;

    uint256 internal lastSharePrice;

    function setUp() public {
        usdc = new MockUSDC();
        vault = new YieldVault(IERC20(address(usdc)), type(uint256).max);
        handler = new YieldVaultHandler(vault, usdc, address(this));

        lastSharePrice = vault.convertToAssets(10 ** vault.decimals());

        targetContract(address(handler));
    }

    function invariant_SolvencySumOfSharesValueNeverExceedsAssets() public view {
        uint256 totalOwed = 0;
        uint256 n = handler.actorsLength();
        for (uint256 i = 0; i < n; i++) {
            totalOwed += vault.convertToAssets(vault.balanceOf(handler.actorAt(i)));
        }
        assertLe(totalOwed, vault.totalAssets(), "el vault le debe mas a los actores de lo que tiene");
    }

    function invariant_SharePriceNeverDecreases() public {
        uint256 currentPrice = vault.convertToAssets(10 ** vault.decimals());
        assertGe(currentPrice, lastSharePrice, "el precio del share bajo");
        lastSharePrice = currentPrice;
    }
}
