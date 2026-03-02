// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {NectarPool} from "../src/NectarPool.sol";
import {NectarVault} from "../src/NectarVault.sol";
import {NectarFactory} from "../src/NectarFactory.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {MockAavePool} from "../src/mocks/MockAavePool.sol";
import {MockSwapRouter} from "../src/mocks/MockSwapRouter.sol";
import {MockVRFModule} from "../src/mocks/MockVRFModule.sol";
import {MockGoodDollarIdentity} from "../src/MockGoodDollarIdentity.sol";

/// @title Deploy
/// @notice Deploys the full Nectar Protocol to Celo Sepolia testnet with mock infrastructure.
///
/// Usage:
///   # Dry-run (no gas spent):
///   forge script script/Deploy.s.sol --rpc-url celo_sepolia
///
///   # Broadcast (actual deploy):
///   source .env && forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));

        if (deployerKey != 0) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }

        address deployer = msg.sender;

        console.log("=== Nectar Protocol Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        // ─── Step 1: Deploy Mock Tokens ──────────────────────────────────────
        MockERC20 usdc = new MockERC20("Test USDC", "USDC");
        console.log("MockERC20 (USDC):", address(usdc));

        MockERC20 gDollar = new MockERC20("Test GoodDollar", "G$");
        console.log("MockERC20 (G$):", address(gDollar));

        // ─── Step 2: Deploy Mock Infrastructure ──────────────────────────────
        MockAavePool aavePool = new MockAavePool();
        console.log("MockAavePool:", address(aavePool));

        MockSwapRouter swapRouter = new MockSwapRouter();
        console.log("MockSwapRouter:", address(swapRouter));

        MockGoodDollarIdentity identity = new MockGoodDollarIdentity();
        console.log("MockGoodDollarIdentity:", address(identity));

        // ─── Step 3: Deploy NectarPool Blueprint ─────────────────────────────
        NectarPool poolBlueprint = new NectarPool();
        console.log("NectarPool Blueprint:", address(poolBlueprint));

        // ─── Step 4: Deploy Core Contracts ───────────────────────────────────
        // Factory first (vault is settable via setVault)
        NectarFactory factory = new NectarFactory(
            address(poolBlueprint),
            address(0), // vault — set after vault deployment
            address(0), // vrfModule — set after VRF deployment
            address(identity),
            deployer // treasury = deployer for testnet
        );
        console.log("NectarFactory:", address(factory));

        // Vault with real Factory address
        NectarVault vault = new NectarVault(
            address(factory),
            address(aavePool),
            address(swapRouter),
            address(usdc)
        );
        console.log("NectarVault:", address(vault));

        // VRF Module with real Vault address
        MockVRFModule vrfModule = new MockVRFModule(address(vault));
        console.log("MockVRFModule:", address(vrfModule));

        // ─── Step 5: Wire up Factory ─────────────────────────────────────────
        factory.setVault(address(vault));
        factory.setVrfModule(address(vrfModule));

        console.log("");
        console.log("=== Wiring Complete ===");
        console.log("Factory.vault:", factory.vault());
        console.log("Factory.vrfModule:", factory.vrfModule());

        // ─── Step 6: Mint test tokens ────────────────────────────────────────
        usdc.mint(deployer, 10_000e18); // 10,000 USDC
        gDollar.mint(deployer, 10_000e18); // 10,000 G$

        // Fund mocks with USDC to cover yield payouts and swaps
        usdc.mint(address(aavePool), 1_000e18);
        usdc.mint(address(swapRouter), 1_000e18);

        console.log("");
        console.log("=== Test Tokens Minted ===");
        console.log("Deployer USDC:", usdc.balanceOf(deployer));
        console.log("Deployer G$:", gDollar.balanceOf(deployer));

        // ─── Step 7: Whitelist deployer in identity ──────────────────────────
        identity.testnetSimulateFaceScan(deployer);
        console.log("Deployer whitelisted in MockIdentity");

        console.log("");
        console.log("=== Deployment Complete! ===");

        vm.stopBroadcast();
    }
}
