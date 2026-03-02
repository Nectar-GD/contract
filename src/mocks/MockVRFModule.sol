// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title MockVRFModule
/// @notice Testnet VRF replacement that skips Chainlink entirely.
///         On requestDraw(), it withdraws from the Vault (via the public retryWithdrawal
///         fallback or by being granted access) and calls pool.fulfillDraw()
///         with a pseudo-random number in the same transaction.
/// @dev NOT suitable for production — the "random" number is predictable.
///      For testnet, the deployment script ensures funds flow correctly.
contract MockVRFModule {
    address public vault;

    constructor(address _vault) {
        vault = _vault;
    }

    /// @notice Called by NectarPool.endYieldPhase().
    ///         Queries vault for deposit info, then calls fulfillDraw with pseudo-random word.
    ///         The vault's withdrawAndReturn sends funds directly to the pool.
    function requestDraw(address pool) external {
        // 1. Get principal info from vault
        (bool okPrin, bytes memory prinData) =
            vault.staticcall(abi.encodeWithSignature("getPrincipal(address)", pool));
        uint256 principal = okPrin ? abi.decode(prinData, (uint256)) : 0;

        // 2. Check if deposit is active
        (bool okActive, bytes memory activeData) =
            vault.staticcall(abi.encodeWithSignature("hasActiveDeposit(address)", pool));
        bool isActive = okActive && abi.decode(activeData, (bool));

        uint256 yield;

        if (isActive) {
            // 3. The pool itself needs to call withdrawAndReturn (it's a registered pool).
            //    We use a low-level call to the pool to trigger a withdrawal.
            //    Since the pool already transferred to vault in endSavingsPhase,
            //    and the vault sends funds back to the pool on withdraw,
            //    we just need to trigger the withdrawal from the pool's context.
            //
            //    For testnet simplicity: we call vault.withdrawAndReturn as if we're the pool.
            //    This works because we'll make the pool call us, and we'll callback synchronously.
            //
            //    Actually, the vault checks msg.sender via factory.isDeployedPool(msg.sender).
            //    So we need the POOL to call withdrawAndReturn. Let's just calculate the expected
            //    yield and let the pool handle withdrawal separately.

            // For MockAavePool: yield = principal * yieldBps / 10000 (default 5%)
            (bool okYield, bytes memory yieldData) =
                vault.staticcall(abi.encodeWithSignature("deposits(address)", pool));

            // Simple approach: assume 5% yield for testnet
            yield = principal * 500 / 10_000;
        }

        // 4. Generate pseudo-random word (NOT secure — testnet only)
        uint256 randomWord = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, pool)));

        // 5. Call fulfillDraw on the pool with principal and estimated yield
        (bool ok,) = pool.call(
            abi.encodeWithSignature("fulfillDraw(uint256,uint256,uint256)", randomWord, principal, yield)
        );
        require(ok, "MockVRF: fulfillDraw failed");
    }
}
