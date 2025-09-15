// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {DGScenarioTestSetup, MAINNET_CHAIN_ID} from "test/utils/integration-tests.sol";
import {LidoUtils} from "test/utils/lido-utils.sol";
import {PercentsD16, PercentD16, HUNDRED_PERCENT_BP, HUNDRED_PERCENT_D16} from "contracts/types/PercentD16.sol";
import {DecimalsFormatting} from "test/utils/formatting.sol";

import {console} from "forge-std/console.sol";

contract LidoUtilsTest is DGScenarioTestSetup {
    using LidoUtils for LidoUtils.Context;
    using DecimalsFormatting for uint256;
    using DecimalsFormatting for PercentD16;

    address stranger = makeAddr("STRANGER");

    function setUp() public {
        _setupFork(MAINNET_CHAIN_ID, _getEnvForkBlockNumberOrDefault(MAINNET_CHAIN_ID));
        vm.deal(stranger, 100 ether);
    }

    function testFork_rebaseHundredPercentNoFinalization() public {
        uint256 shareRateBefore = _lido.stETH.getPooledEthByShares(1 ether);
        uint256 withdrawalQueueBalanceBefore = address(_lido.withdrawalQueue).balance;
        uint256 lastFinalizedRequestIdBefore = _lido.withdrawalQueue.getLastFinalizedRequestId();

        _lido.simulateRebase(PercentsD16.fromBasisPoints(100_00));

        assertEq(_lido.stETH.getPooledEthByShares(1 ether), shareRateBefore);
        assertEq(address(_lido.withdrawalQueue).balance, withdrawalQueueBalanceBefore);
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), lastFinalizedRequestIdBefore);
    }

    function testForkFuzz_rebaseAllowedPercentsNoFinalization(uint256 percentNotNormalized) public {
        vm.assume(percentNotNormalized < PercentsD16.from(10 ** 13).toUint256());
        PercentD16 rebasePercent = PercentsD16.from(HUNDRED_PERCENT_D16 + percentNotNormalized);

        uint256 shareRateBefore = _lido.stETH.getPooledEthByShares(1 ether);
        uint256 withdrawalQueueBalanceBefore = address(_lido.withdrawalQueue).balance;
        uint256 lastFinalizedRequestIdBefore = _lido.withdrawalQueue.getLastFinalizedRequestId();

        _lido.simulateRebase(rebasePercent);

        uint256 expectedShareRate = shareRateBefore * rebasePercent.toUint256() / HUNDRED_PERCENT_D16;

        assertApproxEqAbs(_lido.stETH.getPooledEthByShares(1 ether), expectedShareRate, 10_000 wei);
        assertEq(address(_lido.withdrawalQueue).balance, withdrawalQueueBalanceBefore);
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), lastFinalizedRequestIdBefore);
    }

    function testFork_OneRequestFinalization() public {
        uint256 shareRateBefore = _lido.stETH.getPooledEthByShares(1 ether);
        uint256 withdrawalQueueBalanceBefore = address(_lido.withdrawalQueue).balance;
        uint256 lastFinalizedRequestIdBefore = _lido.withdrawalQueue.getLastFinalizedRequestId();
        uint256 lastRequestIdBefore = _lido.withdrawalQueue.getLastRequestId();

        if (lastRequestIdBefore == lastFinalizedRequestIdBefore) {
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 1 ether;

            vm.prank(stranger);
            _lido.withdrawalQueue.requestWithdrawals(amounts, stranger);

            lastRequestIdBefore = _lido.withdrawalQueue.getLastRequestId();
        }

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = lastFinalizedRequestIdBefore + 1;

        _lido.performRebase(PercentsD16.fromBasisPoints(100_00), lastFinalizedRequestIdBefore + 1);

        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(requestIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());

        uint256 requestToFinalizeClaimableAmount = _lido.withdrawalQueue.getClaimableEther(requestIds, hints)[0];

        assertEq(
            address(_lido.withdrawalQueue).balance, withdrawalQueueBalanceBefore + requestToFinalizeClaimableAmount
        );
        assertEq(_lido.stETH.getPooledEthByShares(1 ether), shareRateBefore);
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), lastFinalizedRequestIdBefore + 1);
    }

    function testFork_rebaseAllowedPositivePercentsWithFinalization() public {
        uint256 percentNotNormalized = PercentsD16.from(10 ** 14).toUint256();
        // vm.assume(percentNotNormalized < PercentsD16.fromBasisPoints(2).toUint256());
        PercentD16 rebasePercent = PercentsD16.from(HUNDRED_PERCENT_D16) + PercentsD16.from(percentNotNormalized);

        console.log("Rebase percent:", rebasePercent.format());

        uint256 totalSupplyBefore = _lido.stETH.totalSupply();
        uint256 totalSharesBefore = _lido.stETH.getTotalShares();

        uint256 shareRateBefore = _lido.stETH.getPooledEthByShares(1 ether);
        uint256 withdrawalQueueBalanceBefore = address(_lido.withdrawalQueue).balance;
        uint256 lastFinalizedRequestIdBefore = _lido.withdrawalQueue.getLastFinalizedRequestId();

        if (lastFinalizedRequestIdBefore == _lido.withdrawalQueue.getLastRequestId()) {
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 1 ether;

            vm.prank(stranger);
            _lido.withdrawalQueue.requestWithdrawals(amounts, stranger);
        }

        _lido.performRebase(rebasePercent, lastFinalizedRequestIdBefore + 1);

        console.log(
            "Total supply before: %s, total shares before: %s",
            totalSupplyBefore.formatEther(),
            totalSharesBefore.formatEther()
        );
        console.log(
            "Total supply after: %s, total shares after: %s",
            _lido.stETH.totalSupply().formatEther(),
            _lido.stETH.getTotalShares().formatEther()
        );
        console.log((int256(_lido.stETH.totalSupply()) - int256(totalSupplyBefore)));
        console.log(int256(_lido.stETH.getTotalShares()) - int256(totalSharesBefore));

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = lastFinalizedRequestIdBefore + 1;

        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(requestIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());

        uint256 requestToFinalizeClaimableAmount = _lido.withdrawalQueue.getClaimableEther(requestIds, hints)[0];

        uint256 expectedShareRate = shareRateBefore * rebasePercent.toUint256() / HUNDRED_PERCENT_D16;

        assertApproxEqAbs(_lido.stETH.getPooledEthByShares(1 ether), expectedShareRate, 100 gwei);
        assertEq(
            address(_lido.withdrawalQueue).balance, withdrawalQueueBalanceBefore + requestToFinalizeClaimableAmount
        );
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), lastFinalizedRequestIdBefore + 1);
    }

    function testForkFuzz_rebaseAllowedPercentsWithFinalization(uint256 percentNotNormalized) public {
        vm.assume(percentNotNormalized < PercentsD16.fromBasisPoints(4).toUint256());
        PercentD16 rebasePercent = PercentsD16.from(percentNotNormalized) + PercentsD16.fromBasisPoints(99_98);

        console.log("Rebase percent:", rebasePercent.format());

        uint256 totalSupplyBefore = _lido.stETH.totalSupply();
        uint256 totalSharesBefore = _lido.stETH.getTotalShares();

        uint256 shareRateBefore = _lido.stETH.getPooledEthByShares(1 ether);
        uint256 withdrawalQueueBalanceBefore = address(_lido.withdrawalQueue).balance;
        uint256 lastFinalizedRequestIdBefore = _lido.withdrawalQueue.getLastFinalizedRequestId();

        if (lastFinalizedRequestIdBefore == _lido.withdrawalQueue.getLastRequestId()) {
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 1 ether;

            vm.prank(stranger);
            _lido.withdrawalQueue.requestWithdrawals(amounts, stranger);
        }

        _lido.performRebase(rebasePercent, lastFinalizedRequestIdBefore + 1);

        console.log(
            "Total supply before: %s, total shares before: %s",
            totalSupplyBefore.formatEther(),
            totalSharesBefore.formatEther()
        );
        console.log(
            "Total supply after: %s, total shares after: %s",
            _lido.stETH.totalSupply().formatEther(),
            _lido.stETH.getTotalShares().formatEther()
        );
        console.log((int256(_lido.stETH.totalSupply()) - int256(totalSupplyBefore)));
        console.log(int256(_lido.stETH.getTotalShares()) - int256(totalSharesBefore));

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = lastFinalizedRequestIdBefore + 1;

        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(requestIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());

        uint256 requestToFinalizeClaimableAmount = _lido.withdrawalQueue.getClaimableEther(requestIds, hints)[0];

        uint256 expectedShareRate = shareRateBefore * rebasePercent.toUint256() / HUNDRED_PERCENT_D16;

        assertApproxEqAbs(_lido.stETH.getPooledEthByShares(1 ether), expectedShareRate, 100 gwei);
        assertEq(
            address(_lido.withdrawalQueue).balance, withdrawalQueueBalanceBefore + requestToFinalizeClaimableAmount
        );
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), lastFinalizedRequestIdBefore + 1);
    }
}
