// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AsyncVault} from "../src/AsyncVault.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title DeployAsync — despliega el AsyncVault (ERC-7540) y corre el ciclo async on-chain
/// @notice Reusa el MockUSDC ya desplegado para el YieldVault (un solo token de prueba
///         para los dos vaults). Como demo, el deployer hace request → fulfill → claim
///         y deja un poco de yield, para que el vault arranque con TVL real.
///
/// Sepolia + verify:
///   forge script script/DeployAsync.s.sol --rpc-url sepolia --broadcast --verify
contract DeployAsync is Script {
    uint256 internal constant USDC = 1e6;
    // MockUSDC desplegado junto al YieldVault (ver README / CONTINUAR).
    address internal constant ASSET = 0xc10b0e68f21c5fFf30D608Fe5179ED915A24e423;
    uint256 internal constant SEED = 1_000 * USDC;
    uint256 internal constant SEED_YIELD = 100 * USDC;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        MockUSDC usdc = MockUSDC(ASSET);
        usdc.mint(deployer, 10_000 * USDC); // faucet abierto: aseguramos saldo

        AsyncVault vault = new AsyncVault(IERC20(ASSET));
        usdc.approve(address(vault), type(uint256).max);

        // Ciclo async completo, hecho por el deployer (que además es el owner/operador).
        vault.requestDeposit(SEED, deployer, deployer);
        vault.fulfillDeposit(deployer, SEED);
        vault.deposit(SEED, deployer, deployer); // claim
        vault.distributeYield(SEED_YIELD);

        vm.stopBroadcast();

        console2.log("AsyncVault:", address(vault));
        console2.log("asset (MockUSDC):", ASSET);
        console2.log("deployer:", deployer);
        console2.log("TVL (assets):", vault.totalAssets());
        console2.log("deployer shares:", vault.balanceOf(deployer));
    }
}
