// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {AsyncVault} from "../src/AsyncVault.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Handler que ejercita el ciclo completo request→fulfill→claim (depósito
///      y retiro) sobre actores fijos, cada uno actuando como su propio
///      controller/owner/receiver (sin delegar a un operador, para mantener
///      el espacio de estados manejable).
contract AsyncVaultHandler is Test {
    AsyncVault public vault;
    MockUSDC public usdc;
    address public owner;

    address[] internal actors;
    uint256 internal constant USDC = 1e6;

    constructor(AsyncVault _vault, MockUSDC _usdc, address _owner) {
        vault = _vault;
        usdc = _usdc;
        owner = _owner;
        for (uint256 i = 0; i < 5; i++) {
            address a = makeAddr(string(abi.encodePacked("asyncActor", i)));
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

    function requestDeposit(uint256 actorSeed, uint256 amountSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 amount = bound(amountSeed, 1, 10_000 * USDC);
        usdc.mint(actor, amount);

        vm.prank(actor);
        try vault.requestDeposit(amount, actor, actor) {} catch {}
    }

    function fulfillDeposit(uint256 actorSeed, uint256 amountSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 pending = vault.pendingDeposit(actor);
        if (pending == 0) return;
        uint256 amount = bound(amountSeed, 1, pending);

        vm.prank(owner);
        try vault.fulfillDeposit(actor, amount) {} catch {}
    }

    function claimDeposit(uint256 actorSeed, uint256 amountSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 claimable = vault.claimableDepositAssets(actor);
        if (claimable == 0) return;
        uint256 amount = bound(amountSeed, 1, claimable);

        vm.prank(actor);
        try vault.deposit(amount, actor, actor) {} catch {}
    }

    function requestRedeem(uint256 actorSeed, uint256 sharesSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 balance = vault.balanceOf(actor);
        if (balance == 0) return;
        uint256 shares = bound(sharesSeed, 1, balance);

        vm.prank(actor);
        try vault.requestRedeem(shares, actor, actor) {} catch {}
    }

    function fulfillRedeem(uint256 actorSeed, uint256 sharesSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 pending = vault.pendingRedeem(actor);
        if (pending == 0) return;
        uint256 shares = bound(sharesSeed, 1, pending);

        vm.prank(owner);
        try vault.fulfillRedeem(actor, shares) {} catch {}
    }

    function claimRedeem(uint256 actorSeed, uint256 sharesSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 claimable = vault.claimableRedeemShares(actor);
        if (claimable == 0) return;
        uint256 shares = bound(sharesSeed, 1, claimable);

        vm.prank(actor);
        try vault.redeem(shares, actor, actor) {} catch {}
    }

    function distributeYield(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 1, 1_000 * USDC);
        usdc.mint(owner, amount);

        vm.startPrank(owner);
        usdc.approve(address(vault), amount);
        try vault.distributeYield(amount) {} catch {}
        vm.stopPrank();
    }
}

/// @title Invariant test — AsyncVault: los 3 buckets de assets siempre cierran
/// @notice El AsyncVault (ERC-7540) reparte el balance de tokens del contrato en
///         TRES buckets contables: lo que está en el pool (`totalAssets()`), lo
///         pending de depósito (`totalPendingDepositAssets`, todavía del usuario)
///         y lo reservado para retiros ya cumplidos (`totalClaimableRedeemAssets`,
///         ya no es del pool). Esta es LA propiedad crítica de un vault async: si
///         los tres buckets no suman exacto el balance real del token, hay
///         plata que se duplicó o se perdió en algún paso del ciclo
///         request→fulfill→claim.
///
///         También se verifica que el precio del share (para el pool activo)
///         nunca decrezca, igual que en el vault síncrono.
contract AsyncVaultInvariantTest is StdInvariant, Test {
    AsyncVault internal vault;
    MockUSDC internal usdc;
    AsyncVaultHandler internal handler;

    uint256 internal lastSharePrice;

    function setUp() public {
        usdc = new MockUSDC();
        vault = new AsyncVault(IERC20(address(usdc)));
        handler = new AsyncVaultHandler(vault, usdc, address(this));

        lastSharePrice = vault.convertToAssets(10 ** vault.decimals());

        targetContract(address(handler));
    }

    function invariant_BucketsAlwaysMatchRealBalance() public view {
        uint256 real = usdc.balanceOf(address(vault));
        uint256 accounted = vault.totalAssets() + vault.totalPendingDepositAssets() + vault.totalClaimableRedeemAssets();
        assertEq(real, accounted, "los buckets contables no cierran contra el balance real");
    }

    function invariant_SharePriceNeverDecreases() public {
        uint256 currentPrice = vault.convertToAssets(10 ** vault.decimals());
        assertGe(currentPrice, lastSharePrice, "el precio del share bajo");
        lastSharePrice = currentPrice;
    }
}
