// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";

import {ITimelock} from "contracts/interfaces/ITimelock.sol";
import {ISignallingEscrow} from "contracts/interfaces/ISignallingEscrow.sol";

import {Durations} from "contracts/types/Duration.sol";
import {Timestamps} from "contracts/types/Timestamp.sol";

import {Escrow} from "contracts/Escrow.sol";
import {Executor} from "contracts/Executor.sol";
import {ResealManager} from "contracts/ResealManager.sol";
import {DualGovernance} from "contracts/DualGovernance.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";
import {ImmutableDualGovernanceConfigProvider} from "contracts/ImmutableDualGovernanceConfigProvider.sol";

import {TiebreakerCoreCommittee} from "contracts/committees/TiebreakerCoreCommittee.sol";
import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";

import {
    DGLaunchConfig,
    DGSetupDeployConfig,
    DGSetupDeployedContracts,
    DGSetupDeployArtifacts
} from "./deployment/Setup.sol";
import {DualGovernanceContractDeployConfig} from "./deployment/DualGovernance.sol";
import {TimelockContractDeployConfig} from "./deployment/Timelock.sol";
import {TGSetupDeployConfig, TGSetupDeployedContracts} from "./deployment/TimelockedGovernance.sol";
import {TiebreakerDeployConfig, TiebreakerDeployedContracts} from "./deployment/Tiebreaker.sol";

library ContractsDeployment {
    function deployTGSetup(
        address deployer,
        TGSetupDeployConfig.Context memory config
    ) internal returns (TGSetupDeployedContracts.Context memory contracts) {
        contracts.adminExecutor = deployExecutor({owner: deployer});

        contracts.timelock = deployEmergencyProtectedTimelock(contracts.adminExecutor, config.timelock);

        contracts.timelockedGovernance =
            deployTimelockedGovernance({governance: config.governance, timelock: contracts.timelock});

        configureEmergencyProtectedTimelock(contracts.adminExecutor, contracts.timelock, config.timelock);
        finalizeEmergencyProtectedTimelockDeploy(
            contracts.adminExecutor, contracts.timelock, address(contracts.timelockedGovernance)
        );
    }

    function deployDGSetup(
        address deployer,
        DGSetupDeployConfig.Context memory deployConfig
    ) internal returns (DGSetupDeployedContracts.Context memory contracts) {
        contracts.adminExecutor = deployExecutor({owner: deployer});

        contracts.timelock = deployEmergencyProtectedTimelock(contracts.adminExecutor, deployConfig.timelock);

        contracts.resealManager = deployResealManager(contracts.timelock);

        contracts.dualGovernanceConfigProvider =
            deployDualGovernanceConfigProvider(deployConfig.dualGovernanceConfigProvider);

        contracts.dualGovernance = deployDualGovernance(
            DualGovernance.DualGovernanceComponents({
                timelock: contracts.timelock,
                resealManager: contracts.resealManager,
                configProvider: contracts.dualGovernanceConfigProvider
            }),
            deployConfig.dualGovernance
        );

        deployConfig.tiebreaker.owner = address(contracts.adminExecutor);
        deployConfig.tiebreaker.dualGovernance = address(contracts.dualGovernance);

        contracts.escrowMasterCopy = Escrow(
            payable(address(ISignallingEscrow(contracts.dualGovernance.getVetoSignallingEscrow()).ESCROW_MASTER_COPY()))
        );

        TiebreakerDeployedContracts.Context memory tiebreakerDeployedContracts =
            deployTiebreaker(deployConfig.tiebreaker, deployer);

        contracts.tiebreakerCoreCommittee = tiebreakerDeployedContracts.tiebreakerCoreCommittee;
        contracts.tiebreakerSubCommittees = tiebreakerDeployedContracts.tiebreakerSubCommittees;

        configureTiebreakerCommittee(
            contracts.adminExecutor,
            contracts.dualGovernance,
            contracts.tiebreakerCoreCommittee,
            deployConfig.dualGovernance
        );

        // ---
        // Finalize Setup
        // ---

        configureDualGovernance(contracts.adminExecutor, contracts.dualGovernance, deployConfig.dualGovernance);

        contracts.emergencyGovernance =
            configureEmergencyProtectedTimelock(contracts.adminExecutor, contracts.timelock, deployConfig.timelock);

        finalizeEmergencyProtectedTimelockDeploy(
            contracts.adminExecutor, contracts.timelock, address(contracts.dualGovernance)
        );
    }

    function deployExecutor(address owner) internal returns (Executor) {
        return new Executor(owner);
    }

    function deployEmergencyProtectedTimelock(
        Executor adminExecutor,
        TimelockContractDeployConfig.Context memory config
    ) internal returns (EmergencyProtectedTimelock) {
        TimelockContractDeployConfig.validate(config);
        return new EmergencyProtectedTimelock(
            config.sanityCheckParams, address(adminExecutor), config.afterSubmitDelay, config.afterScheduleDelay
        );
    }

    function deployTimelockedGovernance(
        address governance,
        ITimelock timelock
    ) internal returns (TimelockedGovernance) {
        return new TimelockedGovernance(governance, timelock);
    }

    function deployResealManager(ITimelock timelock) internal returns (ResealManager) {
        return new ResealManager(timelock);
    }

    function deployDualGovernanceConfigProvider(
        DualGovernanceConfig.Context memory dgConfig
    ) internal returns (ImmutableDualGovernanceConfigProvider) {
        DualGovernanceConfig.validate(dgConfig);
        return new ImmutableDualGovernanceConfigProvider(dgConfig);
    }

    function deployDualGovernance(
        DualGovernance.DualGovernanceComponents memory components,
        DualGovernanceContractDeployConfig.Context memory dgDeployConfig
    ) internal returns (DualGovernance) {
        DualGovernanceContractDeployConfig.validate(dgDeployConfig);

        return new DualGovernance(components, dgDeployConfig.signallingTokens, dgDeployConfig.sanityCheckParams);
    }

    function deployTiebreaker(
        TiebreakerDeployConfig.Context memory tiebreakerConfig,
        address deployer
    ) internal returns (TiebreakerDeployedContracts.Context memory deployedContracts) {
        TiebreakerDeployConfig.validate(tiebreakerConfig);

        deployedContracts.tiebreakerCoreCommittee = new TiebreakerCoreCommittee({
            owner: deployer, dualGovernance: tiebreakerConfig.dualGovernance, timelock: tiebreakerConfig.executionDelay
        });

        deployedContracts.tiebreakerSubCommittees =
            deployTiebreakerSubCommittee(tiebreakerConfig, address(deployedContracts.tiebreakerCoreCommittee));

        address[] memory coreCommitteeMemberAddresses = new address[](deployedContracts.tiebreakerSubCommittees.length);

        for (uint256 i = 0; i < coreCommitteeMemberAddresses.length; ++i) {
            coreCommitteeMemberAddresses[i] = address(deployedContracts.tiebreakerSubCommittees[i]);
        }

        configureTiebreakerCoreCommittee(
            tiebreakerConfig,
            deployedContracts.tiebreakerCoreCommittee,
            coreCommitteeMemberAddresses,
            tiebreakerConfig.quorum
        );
    }

    function deployTiebreakerCoreCommittee(
        TiebreakerDeployConfig.Context memory tiebreakerConfig,
        address owner
    ) internal returns (TiebreakerCoreCommittee) {
        return new TiebreakerCoreCommittee({
            owner: owner, dualGovernance: tiebreakerConfig.dualGovernance, timelock: tiebreakerConfig.executionDelay
        });
    }

    function deployTiebreakerSubCommittee(
        TiebreakerDeployConfig.Context memory tiebreakerConfig,
        address tiebreakerCoreCommittee
    ) internal returns (TiebreakerSubCommittee[] memory tiebreakerSubCommittees) {
        tiebreakerSubCommittees = new TiebreakerSubCommittee[](tiebreakerConfig.committees.length);

        for (uint256 i = 0; i < tiebreakerConfig.committees.length; ++i) {
            tiebreakerSubCommittees[i] = new TiebreakerSubCommittee({
                owner: tiebreakerConfig.owner,
                executionQuorum: tiebreakerConfig.committees[i].quorum,
                committeeMembers: tiebreakerConfig.committees[i].members,
                tiebreakerCoreCommittee: tiebreakerCoreCommittee
            });
        }
    }

    function configureTiebreakerCoreCommittee(
        TiebreakerDeployConfig.Context memory tiebreakerConfig,
        TiebreakerCoreCommittee tiebreakerCoreCommittee,
        address[] memory memberAddresses,
        uint256 quorum
    ) internal {
        tiebreakerCoreCommittee.addMembers(memberAddresses, quorum);
        tiebreakerCoreCommittee.transferOwnership(tiebreakerConfig.owner);
    }

    function configureTiebreakerCommittee(
        Executor adminExecutor,
        DualGovernance dualGovernance,
        TiebreakerCoreCommittee tiebreakerCoreCommittee,
        DualGovernanceContractDeployConfig.Context memory dgDeployConfig
    ) internal {
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setTiebreakerActivationTimeout, dgDeployConfig.tiebreakerActivationTimeout)
        );
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setTiebreakerCommittee, address(tiebreakerCoreCommittee))
        );

        for (uint256 i = 0; i < dgDeployConfig.sealableWithdrawalBlockers.length; ++i) {
            adminExecutor.execute(
                address(dualGovernance),
                0,
                abi.encodeCall(
                    dualGovernance.addTiebreakerSealableWithdrawalBlocker, dgDeployConfig.sealableWithdrawalBlockers[i]
                )
            );
        }
    }

    function configureDualGovernance(
        Executor adminExecutor,
        DualGovernance dualGovernance,
        DualGovernanceContractDeployConfig.Context memory dgDeployConfig
    ) internal {
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.registerProposer, (dgDeployConfig.adminProposer, address(adminExecutor)))
        );
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setProposalsCanceller, dgDeployConfig.proposalsCanceller)
        );
        adminExecutor.execute(
            address(dualGovernance),
            0,
            abi.encodeCall(dualGovernance.setResealCommittee, dgDeployConfig.resealCommittee)
        );
    }

    function configureEmergencyProtectedTimelock(
        Executor adminExecutor,
        EmergencyProtectedTimelock timelock,
        TimelockContractDeployConfig.Context memory timelockConfig
    ) internal returns (TimelockedGovernance emergencyGovernance) {
        if (timelockConfig.emergencyGovernanceProposer != address(0)) {
            emergencyGovernance = deployTimelockedGovernance({
                governance: timelockConfig.emergencyGovernanceProposer, timelock: timelock
            });
            adminExecutor.execute(
                address(timelock), 0, abi.encodeCall(timelock.setEmergencyGovernance, (address(emergencyGovernance)))
            );
        }

        if (timelockConfig.emergencyActivationCommittee != address(0)) {
            console.log(
                "Setting the emergency activation committee to %x...", timelockConfig.emergencyActivationCommittee
            );
            adminExecutor.execute(
                address(timelock),
                0,
                abi.encodeCall(
                    timelock.setEmergencyProtectionActivationCommittee, (timelockConfig.emergencyActivationCommittee)
                )
            );
            console.log("Emergency activation committee set successfully.");
        }

        if (timelockConfig.emergencyExecutionCommittee != address(0)) {
            console.log(
                "Setting the emergency execution committee to %x...", timelockConfig.emergencyExecutionCommittee
            );
            adminExecutor.execute(
                address(timelock),
                0,
                abi.encodeCall(
                    timelock.setEmergencyProtectionExecutionCommittee, (timelockConfig.emergencyExecutionCommittee)
                )
            );
            console.log("Emergency execution committee set successfully.");
        }

        if (timelockConfig.emergencyProtectionEndDate != Timestamps.ZERO) {
            adminExecutor.execute(
                address(timelock),
                0,
                abi.encodeCall(timelock.setEmergencyProtectionEndDate, (timelockConfig.emergencyProtectionEndDate))
            );
        }

        if (timelockConfig.emergencyModeDuration != Durations.ZERO) {
            adminExecutor.execute(
                address(timelock),
                0,
                abi.encodeCall(timelock.setEmergencyModeDuration, (timelockConfig.emergencyModeDuration))
            );
        }
    }

    function finalizeEmergencyProtectedTimelockDeploy(
        Executor adminExecutor,
        EmergencyProtectedTimelock timelock,
        address governance
    ) internal {
        adminExecutor.execute(address(timelock), 0, abi.encodeCall(timelock.setGovernance, (governance)));
        adminExecutor.transferOwnership(address(timelock));
    }
}
