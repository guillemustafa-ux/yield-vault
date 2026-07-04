// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AsyncVault} from "../src/AsyncVault.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Tests del AsyncVault (ERC-7540)
/// @notice Cubre el ciclo completo request → fulfill → claim de depósito y retiro,
///         el precio fijado en el fulfill, operadores, autorización y los preview
///         deshabilitados.
contract AsyncVaultTest is Test {
    MockUSDC internal usdc;
    AsyncVault internal vault;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal operator = makeAddr("operator");

    uint256 internal constant USDC = 1e6;

    function setUp() public {
        usdc = new MockUSDC();
        vault = new AsyncVault(IERC20(address(usdc)));
        _fund(alice, 10_000 * USDC);
        _fund(bob, 10_000 * USDC);
        usdc.mint(address(this), 100_000 * USDC); // el owner inyecta yield
        usdc.approve(address(vault), type(uint256).max);
    }

    function _fund(address who, uint256 amount) internal {
        usdc.mint(who, amount);
        vm.prank(who);
        usdc.approve(address(vault), type(uint256).max);
    }

    // Helper: lleva a `who` a tener shares vía el ciclo async completo.
    function _depositFor(address who, uint256 assets) internal returns (uint256 shares) {
        vm.prank(who);
        vault.requestDeposit(assets, who, who);
        vault.fulfillDeposit(who, assets); // owner cumple
        uint256 before = vault.balanceOf(who);
        vm.prank(who);
        vault.deposit(assets, who, who); // claim
        shares = vault.balanceOf(who) - before;
    }

    // ---- Ciclo de depósito ----

    function test_DepositLifecycle() public {
        // 1) REQUEST
        vm.prank(alice);
        vault.requestDeposit(100 * USDC, alice, alice);

        assertEq(vault.pendingDeposit(alice), 100 * USDC);
        assertEq(vault.pendingDepositRequest(0, alice), 100 * USDC);
        assertEq(vault.totalPendingDepositAssets(), 100 * USDC);
        // Lo pending NO cuenta como pool todavía:
        assertEq(vault.totalAssets(), 0);
        assertEq(usdc.balanceOf(address(vault)), 100 * USDC);

        // 2) FULFILL (owner)
        uint256 shares = vault.fulfillDeposit(alice, 100 * USDC);
        assertEq(vault.pendingDeposit(alice), 0);
        assertEq(vault.claimableDepositAssets(alice), 100 * USDC);
        assertEq(vault.claimableDepositShares(alice), shares);
        assertGt(shares, 0);
        // Ahora sí cuenta en el pool, y las shares están en custodia del vault:
        assertEq(vault.totalAssets(), 100 * USDC);
        assertEq(vault.balanceOf(address(vault)), shares);

        // 3) CLAIM
        vm.prank(alice);
        uint256 claimed = vault.deposit(100 * USDC, alice, alice);
        assertEq(claimed, shares);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.claimableDepositAssets(alice), 0);
        assertEq(vault.balanceOf(address(vault)), 0); // ya entregó la custodia
    }

    // ---- Ciclo de retiro ----

    function test_RedeemLifecycle() public {
        uint256 shares = _depositFor(alice, 100 * USDC);
        uint256 balBefore = usdc.balanceOf(alice);

        // 1) REQUEST redeem
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        assertEq(vault.pendingRedeem(alice), shares);
        assertEq(vault.balanceOf(alice), 0); // shares en custodia
        assertEq(vault.balanceOf(address(vault)), shares);

        // 2) FULFILL (owner)
        uint256 assets = vault.fulfillRedeem(alice, shares);
        assertEq(vault.pendingRedeem(alice), 0);
        assertEq(vault.claimableRedeemShares(alice), shares);
        assertEq(vault.claimableRedeemAssets(alice), assets);
        assertEq(vault.totalSupply(), 0); // shares quemadas

        // 3) CLAIM
        vm.prank(alice);
        uint256 got = vault.redeem(shares, alice, alice);
        assertEq(got, assets);
        assertApproxEqAbs(usdc.balanceOf(alice), balBefore + 100 * USDC, 1);
        assertEq(vault.claimableRedeemShares(alice), 0);
    }

    // ---- El precio se fija en el FULFILL, no en el request ----

    function test_PriceFixedAtFulfill() public {
        // Alice entra primera al precio base.
        uint256 aliceShares = _depositFor(alice, 100 * USDC);

        // Entra rendimiento → el share vale más.
        vault.distributeYield(20 * USDC);

        // Bob pide lo mismo DESPUÉS del yield: recibe menos shares (precio más alto).
        uint256 bobShares = _depositFor(bob, 100 * USDC);
        assertLt(bobShares, aliceShares, "bob deberia recibir menos shares tras el yield");
    }

    // ---- Operadores ----

    function test_OperatorActsForController() public {
        // Alice habilita a `operator` para actuar por ella.
        vm.prank(alice);
        vault.setOperator(operator, true);
        assertTrue(vault.isOperator(alice, operator));

        // El operador pide el depósito por cuenta de alice (los fondos salen de alice).
        vm.prank(operator);
        vault.requestDeposit(100 * USDC, alice, alice);
        assertEq(vault.pendingDeposit(alice), 100 * USDC);

        vault.fulfillDeposit(alice, 100 * USDC);

        // El operador reclama hacia la propia alice.
        vm.prank(operator);
        vault.deposit(100 * USDC, alice, alice);
        assertGt(vault.balanceOf(alice), 0);
    }

    function test_RevertUnauthorizedRequest() public {
        // Bob (no operador de alice) intenta mover fondos de alice → revert.
        vm.prank(bob);
        vm.expectRevert(AsyncVault.NotAuthorized.selector);
        vault.requestDeposit(100 * USDC, bob, alice);
    }

    function test_RevertUnauthorizedClaim() public {
        vm.prank(alice);
        vault.requestDeposit(100 * USDC, alice, alice);
        vault.fulfillDeposit(alice, 100 * USDC);

        // Bob intenta reclamar el depósito de alice → revert.
        vm.prank(bob);
        vm.expectRevert(AsyncVault.NotAuthorized.selector);
        vault.deposit(100 * USDC, bob, alice);
    }

    // ---- Fulfill parcial ----

    function test_PartialFulfill() public {
        vm.prank(alice);
        vault.requestDeposit(100 * USDC, alice, alice);

        // El owner cumple solo 40.
        vault.fulfillDeposit(alice, 40 * USDC);
        assertEq(vault.pendingDeposit(alice), 60 * USDC);
        assertEq(vault.claimableDepositAssets(alice), 40 * USDC);

        // No se puede cumplir más de lo pending.
        vm.expectRevert(AsyncVault.ExceedsPending.selector);
        vault.fulfillDeposit(alice, 61 * USDC);

        // Alice reclama los 40 disponibles.
        vm.prank(alice);
        vault.deposit(40 * USDC, alice, alice);
        assertEq(vault.claimableDepositAssets(alice), 0);

        // El resto se cumple después.
        vault.fulfillDeposit(alice, 60 * USDC);
        assertEq(vault.pendingDeposit(alice), 0);
    }

    // ---- preview deshabilitados (precio se fija en fulfill) ----

    function test_PreviewsRevert() public {
        vm.expectRevert(AsyncVault.PreviewDisabled.selector);
        vault.previewDeposit(1);
        vm.expectRevert(AsyncVault.PreviewDisabled.selector);
        vault.previewMint(1);
        vm.expectRevert(AsyncVault.PreviewDisabled.selector);
        vault.previewWithdraw(1);
        vm.expectRevert(AsyncVault.PreviewDisabled.selector);
        vault.previewRedeem(1);
    }

    // ---- ERC-165 ----

    function test_SupportsInterface() public view {
        assertTrue(vault.supportsInterface(0x01ffc9a7)); // ERC-165
        assertTrue(vault.supportsInterface(0xe3bc4e65)); // operadores
        assertTrue(vault.supportsInterface(0xce3bbe50)); // depósito async
        assertTrue(vault.supportsInterface(0x620ee8e4)); // retiro async
        assertFalse(vault.supportsInterface(0xdeadbeef));
    }

    // ---- maxDeposit/maxRedeem reflejan lo claimable ----

    function test_MaxReflectsClaimable() public {
        vm.prank(alice);
        vault.requestDeposit(100 * USDC, alice, alice);
        assertEq(vault.maxDeposit(alice), 0); // todavía nada cumplido
        vault.fulfillDeposit(alice, 100 * USDC);
        assertEq(vault.maxDeposit(alice), 100 * USDC);
        assertEq(vault.maxMint(alice), vault.claimableDepositShares(alice));
    }

    // ---- claim vía mint() (shares exactas) ----

    function test_MintClaimsExactShares() public {
        vm.prank(alice);
        vault.requestDeposit(100 * USDC, alice, alice);
        uint256 shares = vault.fulfillDeposit(alice, 100 * USDC);

        vm.prank(alice);
        uint256 assetsPaid = vault.mint(shares, alice, alice);

        assertEq(assetsPaid, 100 * USDC);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.claimableDepositShares(alice), 0);
        assertEq(vault.claimableDepositAssets(alice), 0);
    }

    function test_Mint_TwoArgOverload_UsesMsgSenderAsController() public {
        vm.prank(alice);
        vault.requestDeposit(100 * USDC, alice, alice);
        uint256 shares = vault.fulfillDeposit(alice, 100 * USDC);

        vm.prank(alice);
        vault.mint(shares, alice); // overload de 2 args = controller implícito msg.sender

        assertEq(vault.balanceOf(alice), shares);
    }

    function test_Mint_RevertsIfExceedsClaimable() public {
        vm.prank(alice);
        vault.requestDeposit(100 * USDC, alice, alice);
        uint256 shares = vault.fulfillDeposit(alice, 100 * USDC);

        vm.prank(alice);
        vm.expectRevert(AsyncVault.ExceedsClaimable.selector);
        vault.mint(shares + 1, alice, alice);
    }

    // ---- claim vía withdraw() (assets exactos) ----

    function test_WithdrawClaimsExactAssets() public {
        uint256 shares = _depositFor(alice, 100 * USDC);
        uint256 balBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        vault.fulfillRedeem(alice, shares);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(100 * USDC, alice, alice);

        assertEq(sharesBurned, shares);
        assertEq(usdc.balanceOf(alice), balBefore + 100 * USDC);
        assertEq(vault.claimableRedeemAssets(alice), 0);
    }

    function test_Withdraw_RevertsIfExceedsClaimable() public {
        uint256 shares = _depositFor(alice, 100 * USDC);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        vault.fulfillRedeem(alice, shares);

        vm.prank(alice);
        vm.expectRevert(AsyncVault.ExceedsClaimable.selector);
        vault.withdraw(100 * USDC + 1, alice, alice);
    }

    function test_Withdraw_RevertsIfUnauthorized() public {
        uint256 shares = _depositFor(alice, 100 * USDC);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        vault.fulfillRedeem(alice, shares);

        vm.prank(bob);
        vm.expectRevert(AsyncVault.NotAuthorized.selector);
        vault.withdraw(100 * USDC, bob, alice);
    }

    // ---- overload de 2 args de deposit() ----

    function test_Deposit_TwoArgOverload_UsesMsgSenderAsController() public {
        vm.prank(alice);
        vault.requestDeposit(100 * USDC, alice, alice);
        vault.fulfillDeposit(alice, 100 * USDC);

        vm.prank(alice);
        uint256 shares = vault.deposit(100 * USDC, alice); // controller implícito

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    // ---- vistas restantes del estándar ERC-7540 ----

    function test_ViewGetters_ReflectState() public {
        vm.prank(alice);
        vault.requestDeposit(100 * USDC, alice, alice);
        vault.fulfillDeposit(alice, 100 * USDC);
        assertEq(vault.claimableDepositRequest(0, alice), 100 * USDC);

        // Reclamamos el depósito para tener shares y poder pedir un redeem.
        vm.prank(alice);
        vault.deposit(100 * USDC, alice, alice);
        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        assertEq(vault.pendingRedeemRequest(0, alice), shares);

        vault.fulfillRedeem(alice, shares);
        assertEq(vault.claimableRedeemRequest(0, alice), shares);
        assertEq(vault.maxRedeem(alice), shares);
        assertEq(vault.maxWithdraw(alice), vault.claimableRedeemAssets(alice));
    }

    // ---- guard clauses (ZeroAmount / ExceedsPending / ExceedsClaimable / NotAuthorized) ----
    // Cada función del ciclo repite las mismas 4 validaciones; se cubre una vez
    // por guard en el punto donde primero aparece, no exhaustivamente en las 8
    // funciones (serían ~25 tests casi idénticos por poco valor adicional).

    function test_RequestDeposit_RevertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(AsyncVault.ZeroAmount.selector);
        vault.requestDeposit(0, alice, alice);
    }

    function test_RequestRedeem_RevertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(AsyncVault.ZeroAmount.selector);
        vault.requestRedeem(0, alice, alice);
    }

    function test_FulfillDeposit_RevertsOnZeroAmount() public {
        vm.prank(alice);
        vault.requestDeposit(100 * USDC, alice, alice);
        vm.expectRevert(AsyncVault.ZeroAmount.selector);
        vault.fulfillDeposit(alice, 0);
    }

    function test_FulfillRedeem_RevertsIfExceedsPending() public {
        uint256 shares = _depositFor(alice, 100 * USDC);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);

        vm.expectRevert(AsyncVault.ExceedsPending.selector);
        vault.fulfillRedeem(alice, shares + 1);
    }

    function test_Deposit_RevertsOnZeroAmount() public {
        vm.prank(alice);
        vault.requestDeposit(100 * USDC, alice, alice);
        vault.fulfillDeposit(alice, 100 * USDC);

        vm.prank(alice);
        vm.expectRevert(AsyncVault.ZeroAmount.selector);
        vault.deposit(0, alice, alice);
    }

    function test_Redeem_RevertsOnZeroAmount() public {
        uint256 shares = _depositFor(alice, 100 * USDC);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        vault.fulfillRedeem(alice, shares);

        vm.prank(alice);
        vm.expectRevert(AsyncVault.ZeroAmount.selector);
        vault.redeem(0, alice, alice);
    }

    function test_Redeem_RevertsIfUnauthorized() public {
        uint256 shares = _depositFor(alice, 100 * USDC);
        vm.prank(alice);
        vault.requestRedeem(shares, alice, alice);
        vault.fulfillRedeem(alice, shares);

        vm.prank(bob);
        vm.expectRevert(AsyncVault.NotAuthorized.selector);
        vault.redeem(shares, bob, alice);
    }

    function test_Mint_RevertsIfUnauthorized() public {
        vm.prank(alice);
        vault.requestDeposit(100 * USDC, alice, alice);
        uint256 shares = vault.fulfillDeposit(alice, 100 * USDC);

        vm.prank(bob);
        vm.expectRevert(AsyncVault.NotAuthorized.selector);
        vault.mint(shares, bob, alice);
    }
}
