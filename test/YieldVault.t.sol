// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @title Tests del YieldVault (ERC-4626)
/// @notice Cubre contabilidad shares/assets, preview*, dirección de redondeo,
///         crecimiento de rendimiento, cap de depósito y control de acceso.
contract YieldVaultTest is Test {
    MockUSDC internal usdc;
    YieldVault internal vault;

    // owner es address(this) (el contrato de test despliega todo).
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant USDC = 1e6;          // 1 mUSDC (6 decimales)
    uint256 internal constant CAP = 1_000_000 * USDC; // 1M mUSDC de cupo

    function setUp() public {
        usdc = new MockUSDC();
        vault = new YieldVault(IERC20(address(usdc)), CAP);

        // Fondear y aprobar a los usuarios.
        _fund(alice, 10_000 * USDC);
        _fund(bob, 10_000 * USDC);
        // El owner (este contrato) también necesita saldo para inyectar yield.
        usdc.mint(address(this), 100_000 * USDC);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _fund(address who, uint256 amount) internal {
        usdc.mint(who, amount);
        vm.prank(who);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ---- Estado inicial ----

    function test_InitialState() public view {
        assertEq(vault.asset(), address(usdc));
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.depositCap(), CAP);
        // shares = decimales del activo (6) + offset (6) = 12.
        assertEq(vault.decimals(), 12);
    }

    // ---- Depósito / mint ----

    function test_DepositMintsShares() public {
        uint256 assets = 100 * USDC;
        uint256 expected = vault.previewDeposit(assets);

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        assertEq(shares, expected, "shares != previewDeposit");
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), assets);
        assertGt(shares, 0);
    }

    function test_MintTakesExactAssets() public {
        uint256 sharesWanted = vault.previewDeposit(100 * USDC);
        uint256 expectedAssets = vault.previewMint(sharesWanted);

        vm.prank(bob);
        uint256 assetsPaid = vault.mint(sharesWanted, bob);

        assertEq(assetsPaid, expectedAssets, "assets != previewMint");
        assertEq(vault.balanceOf(bob), sharesWanted);
    }

    // ---- Round-trips withdraw / redeem ----

    function test_RedeemRoundTrip() public {
        uint256 assets = 250 * USDC;
        vm.startPrank(alice);
        uint256 shares = vault.deposit(assets, alice);
        uint256 got = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        // El vault redondea a su favor: nunca devuelve MÁS de lo depositado.
        assertLe(got, assets, "redeem devolvio de mas");
        // Y la perdida por redondeo es de a lo sumo 1 unidad.
        assertGe(got, assets - 1, "perdida de redondeo excesiva");
    }

    function test_WithdrawRoundTrip() public {
        uint256 assets = 250 * USDC;
        vm.startPrank(alice);
        vault.deposit(assets, alice);
        // Retirar casi todo (dejamos 1 unidad por el redondeo del round-trip).
        uint256 toWithdraw = assets - 1;
        uint256 burned = vault.withdraw(toWithdraw, alice, alice);
        vm.stopPrank();

        assertGt(burned, 0);
        assertEq(usdc.balanceOf(alice), 10_000 * USDC - assets + toWithdraw);
    }

    // ---- preview* coinciden con la ejecucion real ----

    function test_PreviewsMatchReality() public {
        // previewDeposit
        vm.prank(alice);
        uint256 sh = vault.deposit(100 * USDC, alice);
        assertEq(sh, vault.previewDeposit(100 * USDC), "preview deposit (vacio) mal");

        // Con el vault ya no vacio, previewRedeem debe igualar al redeem real.
        uint256 half = sh / 2;
        uint256 previewed = vault.previewRedeem(half);
        vm.prank(alice);
        uint256 got = vault.redeem(half, alice, alice);
        assertEq(got, previewed, "preview redeem != redeem");
    }

    // ---- Rendimiento sube el precio del share ----

    function test_YieldIncreasesSharePrice() public {
        // Alice deposita 100.
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(100 * USDC, alice);
        uint256 valueBefore = vault.convertToAssets(aliceShares);
        assertEq(valueBefore, 100 * USDC);

        // El owner inyecta 10 de rendimiento (sin emitir shares).
        vault.distributeYield(10 * USDC);

        // Las MISMAS shares de Alice ahora valen ~110.
        uint256 valueAfter = vault.convertToAssets(aliceShares);
        assertGt(valueAfter, valueBefore, "el yield no subio el valor");
        assertApproxEqAbs(valueAfter, 110 * USDC, 2);

        // Bob deposita lo mismo (100) DESPUES del yield: recibe MENOS shares,
        // porque ahora cada share es mas cara.
        vm.prank(bob);
        uint256 bobShares = vault.deposit(100 * USDC, bob);
        assertLt(bobShares, aliceShares, "bob deberia recibir menos shares");
    }

    // ---- Cap de deposito ----

    function test_DepositCapEnforced() public {
        // Cap chico para el test.
        vault.setDepositCap(150 * USDC);

        vm.prank(alice);
        vault.deposit(150 * USDC, alice); // justo al tope, OK

        assertEq(vault.maxDeposit(bob), 0, "maxDeposit deberia ser 0 en el tope");

        // Un wei mas debe revertir con el error del estandar.
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, bob, 1, 0)
        );
        vault.deposit(1, bob);
    }

    function test_MaxMint_UnlimitedWhenCapIsMax() public {
        vault.setDepositCap(type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
    }

    function test_MaxDepositReportsRemaining() public {
        vault.setDepositCap(1000 * USDC);
        vm.prank(alice);
        vault.deposit(400 * USDC, alice);
        assertEq(vault.maxDeposit(bob), 600 * USDC);
    }

    // ---- Control de acceso ----

    function test_OnlyOwnerCanDistributeYield() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice)
        );
        vault.distributeYield(1 * USDC);
    }

    function test_OnlyOwnerCanSetCap() public {
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob)
        );
        vault.setDepositCap(1);
    }

    // ---- Fuzz: round-trip nunca crea valor ----

    function testFuzz_DepositRedeemNeverCreatesValue(uint256 amount) public {
        amount = bound(amount, 1, 5_000 * USDC); // dentro del saldo de alice
        vm.startPrank(alice);
        uint256 shares = vault.deposit(amount, alice);
        uint256 got = vault.redeem(shares, alice, alice);
        vm.stopPrank();
        // El usuario nunca puede sacar mas de lo que metio (el vault gana el redondeo).
        assertLe(got, amount);
    }
}
