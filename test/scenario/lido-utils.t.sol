// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DGScenarioTestSetup, MAINNET_CHAIN_ID} from "test/utils/integration-tests.sol";
import {LidoUtils} from "test/utils/lido-utils.sol";
import {PercentsD16, PercentD16, HUNDRED_PERCENT_BP, HUNDRED_PERCENT_D16} from "contracts/types/PercentD16.sol";
import {DecimalsFormatting} from "test/utils/formatting.sol";
import {IOracleReportSanityChecker} from "test/utils/interfaces/IOracleReportSanityChecker.sol";
import {Durations} from "contracts/types/Duration.sol";

contract LidoUtilsTest is DGScenarioTestSetup {
    using LidoUtils for LidoUtils.Context;
    using DecimalsFormatting for uint256;
    using DecimalsFormatting for PercentD16;

    address stranger = makeAddr("STRANGER");

    function setUp() public {
        _setupFork(MAINNET_CHAIN_ID, _getEnvForkBlockNumberOrDefault(MAINNET_CHAIN_ID));
        vm.deal(stranger, 100 ether);

        vm.startPrank(stranger);
        _lido.stETH.submit{value: 10 ether}(address(0));
        _lido.stETH.approve(address(_lido.withdrawalQueue), type(uint256).max);
        vm.stopPrank();
    }

    function testFork_rebaseHundredPercentNoFinalization() public {
        uint256 shareRateBefore = _lido.stETH.getPooledEthByShares(1 ether);
        uint256 withdrawalQueueBalanceBefore = address(_lido.withdrawalQueue).balance;
        uint256 lastFinalizedRequestIdBefore = _lido.withdrawalQueue.getLastFinalizedRequestId();

        _lido.performRebase(PercentsD16.fromBasisPoints(100_00));

        assertEq(_lido.stETH.getPooledEthByShares(1 ether), shareRateBefore);
        assertEq(address(_lido.withdrawalQueue).balance, withdrawalQueueBalanceBefore);
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), lastFinalizedRequestIdBefore);
    }

    function testForkFuzz_rebaseAllowedPercentsNoFinalization(uint256 percentNotNormalized) public {
        uint256 percentLimit = PercentsD16.from(2 * 10 ** 13).toUint256();
        vm.assume(percentNotNormalized < percentLimit);

        PercentD16 rebasePercent = PercentsD16.from(HUNDRED_PERCENT_D16 + percentNotNormalized - percentLimit);

        uint256 shareRateBefore = _lido.stETH.getPooledEthByShares(1 ether);
        uint256 withdrawalQueueBalanceBefore = address(_lido.withdrawalQueue).balance;
        uint256 lastFinalizedRequestIdBefore = _lido.withdrawalQueue.getLastFinalizedRequestId();

        _lido.performRebase(rebasePercent);

        uint256 expectedShareRate = shareRateBefore * rebasePercent.toUint256() / HUNDRED_PERCENT_D16;

        assertApproxEqAbs(_lido.stETH.getPooledEthByShares(1 ether), expectedShareRate, 1);
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
        PercentD16 rebasePercent = PercentsD16.from(HUNDRED_PERCENT_D16) + PercentsD16.from(percentNotNormalized);

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

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = lastFinalizedRequestIdBefore + 1;

        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(requestIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());

        uint256 requestToFinalizeClaimableAmount = _lido.withdrawalQueue.getClaimableEther(requestIds, hints)[0];

        uint256 expectedShareRate = shareRateBefore * rebasePercent.toUint256() / HUNDRED_PERCENT_D16;

        assertApproxEqAbs(_lido.stETH.getPooledEthByShares(1 ether), expectedShareRate, 2 wei);
        assertEq(
            address(_lido.withdrawalQueue).balance, withdrawalQueueBalanceBefore + requestToFinalizeClaimableAmount
        );
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), lastFinalizedRequestIdBefore + 1);
    }

    function testForkFuzz_rebaseAllowedPercentsWithFinalization(uint256 percentNotNormalized) public {
        vm.assume(percentNotNormalized < PercentsD16.fromBasisPoints(4).toUint256());
        PercentD16 rebasePercent = PercentsD16.from(percentNotNormalized) + PercentsD16.fromBasisPoints(99_98);

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

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = lastFinalizedRequestIdBefore + 1;

        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(requestIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());

        uint256 requestToFinalizeClaimableAmount = _lido.withdrawalQueue.getClaimableEther(requestIds, hints)[0];

        uint256 expectedShareRate = shareRateBefore * rebasePercent.toUint256() / HUNDRED_PERCENT_D16;

        assertApproxEqAbs(_lido.stETH.getPooledEthByShares(1 ether), expectedShareRate, 2 wei);
        assertEq(
            address(_lido.withdrawalQueue).balance, withdrawalQueueBalanceBefore + requestToFinalizeClaimableAmount
        );
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), lastFinalizedRequestIdBefore + 1);
    }

    function testFork_negativeRebaseThenSmallerPositiveRebaseWithFinalization() public {
        uint256 negativeRebaseRateBp = 99_99;
        uint256 positiveRebaseRateBp = 100_01;

        _finalizeWithdrawalQueue();

        uint256 initialShareRate = _lido.stETH.getPooledEthByShares(1 ether);
        uint256 requestAmount = 1 ether;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = requestAmount;

        vm.prank(stranger);
        uint256[] memory requestIds = _lido.withdrawalQueue.requestWithdrawals(amounts, stranger);
        uint256 newRequestId = requestIds[0];

        assertEq(_lido.withdrawalQueue.getLastRequestId(), newRequestId);
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), newRequestId - 1);

        _lido.performRebase(PercentsD16.fromBasisPoints(negativeRebaseRateBp));

        uint256 shareRateAfterNegative = _lido.stETH.getPooledEthByShares(1 ether);
        assertApproxEqAbs(shareRateAfterNegative, initialShareRate * negativeRebaseRateBp / 100_00, 1);

        _lido.performRebase(PercentsD16.fromBasisPoints(positiveRebaseRateBp), newRequestId);

        uint256 shareRateAfterPositive = _lido.stETH.getPooledEthByShares(1 ether);
        assertApproxEqAbs(shareRateAfterPositive, shareRateAfterNegative * positiveRebaseRateBp / 100_00, 1);
        assertLt(shareRateAfterPositive, initialShareRate);
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), newRequestId);

        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(requestIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());
        uint256 claimableAmount = _lido.withdrawalQueue.getClaimableEther(requestIds, hints)[0];

        assertLt(claimableAmount, requestAmount);

        uint256 strangerBalanceBefore = stranger.balance;

        vm.prank(stranger);
        _lido.withdrawalQueue.claimWithdrawals(requestIds, hints);

        assertEq(stranger.balance, strangerBalanceBefore + claimableAmount);
    }

    function testFork_positiveRebaseThenSmallerNegativeRebaseWithFinalization() public {
        uint256 positiveRebaseRateBp = 100_02;
        uint256 negativeRebaseRateBp = 99_99;

        _finalizeWithdrawalQueue();

        uint256 initialShareRate = _lido.stETH.getPooledEthByShares(1 ether);
        uint256 requestAmount = 1 ether;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = requestAmount;

        vm.prank(stranger);
        uint256[] memory requestIds = _lido.withdrawalQueue.requestWithdrawals(amounts, stranger);
        uint256 newRequestId = requestIds[0];

        assertEq(_lido.withdrawalQueue.getLastRequestId(), newRequestId);
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), newRequestId - 1);

        _lido.performRebase(PercentsD16.fromBasisPoints(positiveRebaseRateBp));

        uint256 shareRateAfterPositive = _lido.stETH.getPooledEthByShares(1 ether);
        assertApproxEqAbs(shareRateAfterPositive, initialShareRate * positiveRebaseRateBp / 100_00, 1);

        _lido.performRebase(PercentsD16.fromBasisPoints(negativeRebaseRateBp), newRequestId);

        uint256 shareRateAfterNegative = _lido.stETH.getPooledEthByShares(1 ether);
        assertApproxEqAbs(shareRateAfterNegative, shareRateAfterPositive * negativeRebaseRateBp / 100_00, 1);
        assertGt(shareRateAfterNegative, initialShareRate);
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), newRequestId);

        uint256[] memory hints =
            _lido.withdrawalQueue.findCheckpointHints(requestIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());
        uint256 claimableAmount = _lido.withdrawalQueue.getClaimableEther(requestIds, hints)[0];

        assertEq(claimableAmount, requestAmount);

        uint256 strangerBalanceBefore = stranger.balance;

        vm.prank(stranger);
        _lido.withdrawalQueue.claimWithdrawals(requestIds, hints);

        assertEq(stranger.balance, strangerBalanceBefore + claimableAmount);
    }

    function testFork_twoRequestsWithPositiveThenNegativeRebaseFinalization() public {
        uint256 positiveRebaseRateBp = 100_02;
        uint256 negativeRebaseRateBp = 99_99;

        _finalizeWithdrawalQueue();

        uint256 initialShareRate = _lido.stETH.getPooledEthByShares(1 ether);
        uint256 requestAmount = 1 ether;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = requestAmount;

        vm.prank(stranger);
        uint256[] memory firstRequestIds = _lido.withdrawalQueue.requestWithdrawals(amounts, stranger);
        uint256 firstRequestId = firstRequestIds[0];

        assertEq(_lido.withdrawalQueue.getLastRequestId(), firstRequestId);
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), firstRequestId - 1);

        _lido.performRebase(PercentsD16.fromBasisPoints(positiveRebaseRateBp));

        uint256 shareRateAfterPositive = _lido.stETH.getPooledEthByShares(1 ether);
        assertApproxEqAbs(shareRateAfterPositive, initialShareRate * positiveRebaseRateBp / 100_00, 1);

        vm.prank(stranger);
        uint256[] memory secondRequestIds = _lido.withdrawalQueue.requestWithdrawals(amounts, stranger);
        uint256 secondRequestId = secondRequestIds[0];

        assertEq(_lido.withdrawalQueue.getLastRequestId(), secondRequestId);
        assertEq(secondRequestId, firstRequestId + 1);

        _lido.performRebase(PercentsD16.fromBasisPoints(negativeRebaseRateBp), secondRequestId);

        uint256 shareRateAfterNegative = _lido.stETH.getPooledEthByShares(1 ether);
        assertApproxEqAbs(shareRateAfterNegative, shareRateAfterPositive * negativeRebaseRateBp / 100_00, 1);
        assertGt(shareRateAfterNegative, initialShareRate);
        assertEq(_lido.withdrawalQueue.getLastFinalizedRequestId(), secondRequestId);

        uint256[] memory bothRequestIds = new uint256[](2);
        bothRequestIds[0] = firstRequestId;
        bothRequestIds[1] = secondRequestId;

        uint256[] memory hints = _lido.withdrawalQueue
        .findCheckpointHints(bothRequestIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());
        uint256[] memory claimableAmounts = _lido.withdrawalQueue.getClaimableEther(bothRequestIds, hints);

        assertEq(claimableAmounts[0], requestAmount);
        assertLt(claimableAmounts[1], requestAmount);
    }
}
