// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PercentsD16} from "contracts/types/PercentD16.sol";
import {Duration, Durations} from "contracts/types/Duration.sol";

import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";

import {Escrow} from "contracts/Escrow.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";

import {State as DualGovernanceState} from "contracts/interfaces/IDualGovernance.sol";

import {MAINNET_DISCONNECTED_DUAL_GOVERNANCE} from "../utils/lido-utils.sol";
import {LidoUtils, DGRegressionTestSetup, MAINNET_CHAIN_ID} from "../utils/integration-tests.sol";

uint256 constant ACCURACY = 2 wei;
uint256 constant MAX_WITHDRAWAL_REQUEST_AMOUNT = 1_000 ether;

contract DisconnectedContractsRegressionTest is DGRegressionTestSetup {
    using LidoUtils for LidoUtils.Context;
    using DualGovernanceConfig for DualGovernanceConfig.Context;

    Escrow internal escrow;
    DualGovernance internal dualGovernance;

    address internal immutable _VETOER_1 = makeAddr("VETOER_1");
    address internal immutable _VETOER_2 = makeAddr("VETOER_2");

    Duration internal minAssetsLockDurationOnDisconnectedEscrow;

    function setUp() external {
        if (!vm.envOr("RUN_DISCONNECTED_DG_SETUP_TEST", false)) {
            vm.skip(true, "To enable this test set the env variable RUN_DISCONNECTED_DG_SETUP_TEST=true");
            return;
        }

        _loadOrDeployDGSetup();

        if (block.chainid != MAINNET_CHAIN_ID) {
            vm.skip(true, "Test supports can be run only on mainnet network");
        }

        dualGovernance = DualGovernance(MAINNET_DISCONNECTED_DUAL_GOVERNANCE);
        escrow = Escrow(payable(dualGovernance.getVetoSignallingEscrow()));

        minAssetsLockDurationOnDisconnectedEscrow = escrow.getMinAssetsLockDuration();

        _setupStETHBalance(_VETOER_1, PercentsD16.fromBasisPoints(50_01));

        vm.startPrank(_VETOER_1);
        _lido.stETH.approve(address(_lido.wstETH), type(uint256).max);
        _lido.stETH.approve(address(escrow), type(uint256).max);
        _lido.stETH.approve(address(_lido.withdrawalQueue), type(uint256).max);
        _lido.wstETH.approve(address(escrow), type(uint256).max);

        _lido.wstETH.wrap(10 * 10 ** 18);
        vm.stopPrank();
    }

    function testFork_LockUnlockAssetsDisconnectedEscrow_HappyPath() public {
        uint256 firstVetoerLockStETHAmount = 1 ether;
        uint256 firstVetoerLockWstETHAmount = 2 ether;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = firstVetoerLockStETHAmount;
        vm.prank(_VETOER_1);
        uint256[] memory unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);

        uint256 firstVetoerStETHBalanceBefore = _lido.stETH.balanceOf(_VETOER_1);

        vm.startPrank(_VETOER_1);
        escrow.lockStETH(firstVetoerLockStETHAmount);
        escrow.lockWstETH(firstVetoerLockWstETHAmount);

        _lido.withdrawalQueue.setApprovalForAll(address(escrow), true);
        escrow.lockUnstETH(unstETHIds);
        _lido.withdrawalQueue.setApprovalForAll(address(escrow), false);
        vm.stopPrank();

        assert(minAssetsLockDurationOnDisconnectedEscrow == Durations.from(1 seconds));
        _wait(minAssetsLockDurationOnDisconnectedEscrow.plusSeconds(1));

        vm.startPrank(_VETOER_1);
        escrow.unlockStETH();
        escrow.unlockUnstETH(unstETHIds);
        vm.stopPrank();

        assertApproxEqAbs(
            _lido.stETH.balanceOf(_VETOER_1),
            firstVetoerStETHBalanceBefore + _lido.stETH.getPooledEthByShares(firstVetoerLockWstETHAmount),
            ACCURACY
        );
    }

    function testFork_LockMoreThan50PercentOfTvl_NoRageQuitExpected() public {
        // Checking that rage quit support is less than 0.01%. (There may be some dust on the escrow)
        _step("0. Checking that rage quit support is less than 0.01%");
        {
            assert(escrow.getRageQuitSupport() < PercentsD16.fromBasisPoints(1));
            assert(dualGovernance.getEffectiveState() == DualGovernanceState.Normal);
        }

        _step("1. Lock more than 50% of TVL");
        {
            vm.startPrank(_VETOER_1);
            escrow.lockStETH(_lido.stETH.balanceOf(_VETOER_1));
            escrow.lockWstETH(_lido.wstETH.balanceOf(_VETOER_1));
            vm.stopPrank();
        }

        _step("2. Checking that rage quit support is > 50% and does not affect DG state");
        {
            dualGovernance.activateNextState();
            assert(escrow.getRageQuitSupport() >= PercentsD16.fromBasisPoints(50_00));
            assert(dualGovernance.getEffectiveState() == DualGovernanceState.Normal);
        }
    }

    function testFork_LockMoreThan99PercentOfTvl_RageQuitExpected() public {
        uint256[] memory unstETHIds;

        _step("0. Add some locked assets to the escrow");
        {
            vm.startPrank(_VETOER_1);
            escrow.lockWstETH(1 * 10 ** 18);
            vm.stopPrank();
        }

        _step("1. Checking that rage quit support is less than 0.01%");
        {
            assert(escrow.getRageQuitSupport() < PercentsD16.fromBasisPoints(1));
            assert(dualGovernance.getEffectiveState() == DualGovernanceState.Normal);
        }

        _step("2. Create withdrawal NFT to bypass 99.99% rage quit");
        {
            uint256 vetoerBalance = _lido.stETH.balanceOf(_VETOER_1);
            uint256 minRequestAmount = _lido.withdrawalQueue.MIN_STETH_WITHDRAWAL_AMOUNT();
            uint256 requestAmount = _lido.withdrawalQueue.MAX_STETH_WITHDRAWAL_AMOUNT();
            uint256 requestsCount = vetoerBalance / requestAmount + 1;
            uint256[] memory amounts = new uint256[](requestsCount);

            uint256 i = 0;
            while (vetoerBalance > 0) {
                if (vetoerBalance < minRequestAmount) {
                    uint256 topUpAmount = minRequestAmount - vetoerBalance;
                    vm.deal(_VETOER_1, _VETOER_1.balance + topUpAmount);
                    vm.prank(_VETOER_1);
                    _lido.stETH.submit{value: topUpAmount}(address(0));
                    vetoerBalance = _lido.stETH.balanceOf(_VETOER_1);
                }
                uint256 amount = vetoerBalance <= requestAmount ? vetoerBalance : requestAmount;
                amounts[i] = amount;
                vetoerBalance -= amount;
                i++;
            }

            vm.startPrank(_VETOER_1);
            unstETHIds = _lido.withdrawalQueue.requestWithdrawals(amounts, _VETOER_1);
            {
                _lido.withdrawalQueue.setApprovalForAll(address(escrow), true);
                escrow.lockUnstETH(unstETHIds);
                _lido.withdrawalQueue.setApprovalForAll(address(escrow), false);
            }
            vm.stopPrank();

            for (i = 0; i < unstETHIds.length; ++i) {
                assertEq(_lido.withdrawalQueue.ownerOf(unstETHIds[i]), address(escrow));
            }
            _finalizeWithdrawalQueue();

            assert(escrow.getRageQuitSupport() > PercentsD16.fromBasisPoints(99_99));
        }

        _step("3. 99.99% reached. Transition to VetoSignalling state");
        {
            dualGovernance.activateNextState();
            assert(dualGovernance.getEffectiveState() == DualGovernanceState.VetoSignalling);
        }

        _step("4. Transition to RageQuit state");
        {
            _wait(dualGovernance.getConfigProvider().getDualGovernanceConfig().vetoSignallingMaxDuration.plusSeconds(1));
            dualGovernance.activateNextState();
            assert(dualGovernance.getEffectiveState() == DualGovernanceState.RageQuit);
            while (!escrow.isWithdrawalsBatchesClosed()) {
                escrow.requestNextWithdrawalsBatch(escrow.MIN_WITHDRAWALS_BATCH_SIZE());
            }
            _finalizeWithdrawalQueue();
            escrow.claimNextWithdrawalsBatch(1);
            escrow.startRageQuitExtensionPeriod();
            _wait(
                dualGovernance.getConfigProvider().getDualGovernanceConfig().rageQuitExtensionPeriodDuration
                    .plusSeconds(1)
            );
        }

        _step("5. Claim locked assets");
        {
            uint256[] memory hints = _lido.withdrawalQueue
            .findCheckpointHints(unstETHIds, 1, _lido.withdrawalQueue.getLastCheckpointIndex());

            escrow.claimUnstETH(unstETHIds, hints);
            vm.startPrank(_VETOER_1);
            escrow.withdrawETH(unstETHIds);
            vm.stopPrank();
        }
    }
}
