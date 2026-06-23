// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Deploy — despliega MockUSDC + YieldVault y deja el vault "vivo" para el demo
/// @notice Pasos:
///   1. Despliega MockUSDC (stablecoin de prueba, 6 decimales).
///   2. Mintea un lote al deployer (para sembrar liquidez y para repartir en el demo).
///   3. Despliega YieldVault con un cap de 1.000.000 mUSDC.
///   4. Siembra: el deployer deposita 1.000 mUSDC e inyecta 100 de yield, de modo
///      que el vault arranca con TVL y precio de share > 1 (mas lindo para mostrar).
///
/// Local (anvil):   forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
/// Sepolia + verify: forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
contract Deploy is Script {
    uint256 internal constant USDC = 1e6;
    uint256 internal constant CAP = 1_000_000 * USDC;
    uint256 internal constant SEED_DEPOSIT = 1_000 * USDC;
    uint256 internal constant SEED_YIELD = 100 * USDC;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        MockUSDC usdc = new MockUSDC();
        usdc.mint(deployer, 100_000 * USDC);

        YieldVault vault = new YieldVault(IERC20(address(usdc)), CAP);

        // Sembrar liquidez + un poco de rendimiento para que el demo no arranque vacio.
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(SEED_DEPOSIT, deployer);
        vault.distributeYield(SEED_YIELD);

        vm.stopBroadcast();

        console2.log("MockUSDC :", address(usdc));
        console2.log("YieldVault:", address(vault));
        console2.log("deployer :", deployer);
        console2.log("TVL (assets):", vault.totalAssets());
        console2.log("share price x1e6:", vault.convertToAssets(10 ** vault.decimals()));
    }
}
