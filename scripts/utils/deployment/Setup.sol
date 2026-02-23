// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";

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

import {ImmutableDualGovernanceConfigProviderDeployConfig} from "./ImmutableDualGovernanceConfigProvider.sol";
import {DualGovernanceContractDeployConfig} from "./DualGovernance.sol";
import {TiebreakerDeployConfig} from "./Tiebreaker.sol";
import {TimelockContractDeployConfig} from "./Timelock.sol";
import {IVotingProvider} from "scripts/utils/interfaces/IVotingProvider.sol";

import {DeployFiles} from "../DeployFiles.sol";
import {ConfigFileReader, ConfigFileBuilder, JsonKeys} from "../ConfigFiles.sol";

import {DEFAULT_ROOT_KEY as DUAL_GOVERNANCE_ROOT_KEY} from "./DualGovernance.sol";
import {DEFAULT_ROOT_KEY as TIMELOCK_ROOT_KEY} from "./Timelock.sol";
import {DEFAULT_ROOT_KEY as TIEBREAKER_ROOT_KEY} from "./Tiebreaker.sol";
import {DEFAULT_ROOT_KEY as DG_CONFIG_PROVIDER_ROOT_KEY} from "./ImmutableDualGovernanceConfigProvider.sol";

error InvalidChainId(uint256 actual, uint256 expected);

using JsonKeys for string;
using ConfigFileBuilder for ConfigFileBuilder.Context;
using ConfigFileReader for ConfigFileReader.Context;

string constant EXECUTOR_ROOT_KEY = "executor";

library DGSetupDeployConfig {
    using StringUtils for string;
    using TimelockContractDeployConfig for TimelockContractDeployConfig.Context;
    using TiebreakerDeployConfig for TiebreakerDeployConfig.Context;
    using DualGovernanceContractDeployConfig for DualGovernanceContractDeployConfig.Context;
    using ImmutableDualGovernanceConfigProviderDeployConfig for DualGovernanceConfig.Context;

    struct Context {
        uint256 chainId;
        TimelockContractDeployConfig.Context timelock;
        TiebreakerDeployConfig.Context tiebreaker;
        DualGovernanceContractDeployConfig.Context dualGovernance;
        DualGovernanceConfig.Context dualGovernanceConfigProvider;
    }

    function load(string memory configFilePath) internal view returns (Context memory ctx) {
        return load(configFilePath, "");
    }

    function load(
        string memory configFilePath,
        string memory configRootKey
    ) internal view returns (Context memory ctx) {
        string memory $ = configRootKey.root();

        ctx.chainId = loadChainId(configFilePath, $);
        ctx.timelock = TimelockContractDeployConfig.load(configFilePath, $);
        ctx.tiebreaker = TiebreakerDeployConfig.load(configFilePath, $);
        ctx.dualGovernance = DualGovernanceContractDeployConfig.load(configFilePath, $);
        ctx.dualGovernanceConfigProvider = ImmutableDualGovernanceConfigProviderDeployConfig.load(configFilePath, $);
    }

    function loadChainId(string memory configFilePath) internal view returns (uint256) {
        return loadChainId(configFilePath, "");
    }

    function loadChainId(string memory configFilePath, string memory configRootKey) internal view returns (uint256) {
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);
        return file.readUint(configRootKey.key("chain_id"));
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("chain_id", ctx.chainId);
        builder.set(TIMELOCK_ROOT_KEY, ctx.timelock.toJSON());
        builder.set(TIEBREAKER_ROOT_KEY, ctx.tiebreaker.toJSON());
        builder.set(DUAL_GOVERNANCE_ROOT_KEY, ctx.dualGovernance.toJSON());
        builder.set(DG_CONFIG_PROVIDER_ROOT_KEY, ctx.dualGovernanceConfigProvider.toJSON());

        return builder.content;
    }

    function toJSON(Context memory ctx, string memory field) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("chain_id", ctx.chainId);

        if (field.equal(TIMELOCK_ROOT_KEY)) {
            builder.set(TIMELOCK_ROOT_KEY, ctx.timelock.toJSON());
        } else if (field.equal(TIEBREAKER_ROOT_KEY)) {
            builder.set(TIEBREAKER_ROOT_KEY, ctx.tiebreaker.toJSON());
        } else if (field.equal(DUAL_GOVERNANCE_ROOT_KEY)) {
            builder.set(DUAL_GOVERNANCE_ROOT_KEY, ctx.dualGovernance.toJSON());
        } else if (field.equal(DG_CONFIG_PROVIDER_ROOT_KEY)) {
            builder.set(DG_CONFIG_PROVIDER_ROOT_KEY, ctx.dualGovernanceConfigProvider.toJSON());
        }

        return builder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("Chain ID", ctx.chainId);

        ctx.timelock.print();
        ctx.dualGovernanceConfigProvider.print();
        ctx.dualGovernance.print();
        ctx.tiebreaker.print();
    }

    function validateChainId(Context memory ctx) internal view {
        if (ctx.chainId != block.chainid) {
            revert InvalidChainId(block.chainid, ctx.chainId);
        }
    }
}

library DGSetupDeployedContracts {
    using StringUtils for string;

    struct Context {
        Executor adminExecutor;
        Escrow escrowMasterCopy;
        EmergencyProtectedTimelock timelock;
        TimelockedGovernance emergencyGovernance;
        ResealManager resealManager;
        DualGovernance dualGovernance;
        ImmutableDualGovernanceConfigProvider dualGovernanceConfigProvider;
        TiebreakerCoreCommittee tiebreakerCoreCommittee;
        TiebreakerSubCommittee[] tiebreakerSubCommittees;
    }

    function load(
        string memory deployedContractsFilePath,
        string memory prefix
    ) internal view returns (Context memory ctx) {
        string memory $ = prefix.root();
        ConfigFileReader.Context memory deployedContract = ConfigFileReader.load(deployedContractsFilePath);

        ctx.adminExecutor = Executor(payable(deployedContract.readAddress($.key("admin_executor"))));
        ctx.timelock = EmergencyProtectedTimelock(deployedContract.readAddress($.key("timelock")));
        ctx.emergencyGovernance = TimelockedGovernance(deployedContract.readAddress($.key("emergency_governance")));
        ctx.resealManager = ResealManager(deployedContract.readAddress($.key("reseal_manager")));
        ctx.dualGovernance = DualGovernance(deployedContract.readAddress($.key("dual_governance")));
        ctx.escrowMasterCopy = Escrow(payable(deployedContract.readAddress($.key("escrow_master_copy"))));
        ctx.dualGovernanceConfigProvider = ImmutableDualGovernanceConfigProvider(
            deployedContract.readAddress($.key("dual_governance_config_provider"))
        );
        ctx.tiebreakerCoreCommittee =
            TiebreakerCoreCommittee(deployedContract.readAddress($.key("tiebreaker_core_committee")));

        address[] memory tiebreakerSubCommittees = deployedContract.readAddressArray($.key("tiebreaker_sub_committees"));
        ctx.tiebreakerSubCommittees = new TiebreakerSubCommittee[](tiebreakerSubCommittees.length);
        for (uint256 i = 0; i < tiebreakerSubCommittees.length; ++i) {
            ctx.tiebreakerSubCommittees[i] = TiebreakerSubCommittee(tiebreakerSubCommittees[i]);
        }
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory configBuilder = ConfigFileBuilder.create();

        configBuilder.set("admin_executor", address(ctx.adminExecutor));
        configBuilder.set("timelock", address(ctx.timelock));
        configBuilder.set("emergency_governance", address(ctx.emergencyGovernance));
        configBuilder.set("reseal_manager", address(ctx.resealManager));
        configBuilder.set("dual_governance", address(ctx.dualGovernance));
        configBuilder.set("escrow_master_copy", address(ctx.escrowMasterCopy));
        configBuilder.set("dual_governance_config_provider", address(ctx.dualGovernanceConfigProvider));
        configBuilder.set("tiebreaker_core_committee", address(ctx.tiebreakerCoreCommittee));
        configBuilder.set("tiebreaker_sub_committees", _getTiebreakerSubCommitteeAddresses(ctx));

        return configBuilder.content;
    }

    function toJSON(Context memory ctx, string memory field) internal returns (string memory) {
        ConfigFileBuilder.Context memory configBuilder = ConfigFileBuilder.create();

        if (field.equal(TIMELOCK_ROOT_KEY)) {
            configBuilder.set(TIMELOCK_ROOT_KEY, address(ctx.timelock));
        } else if (field.equal(TIEBREAKER_ROOT_KEY)) {
            configBuilder.set("tiebreaker_core_committee", address(ctx.tiebreakerCoreCommittee));
            configBuilder.set("tiebreaker_sub_committees", _getTiebreakerSubCommitteeAddresses(ctx));
        } else if (field.equal(DUAL_GOVERNANCE_ROOT_KEY)) {
            configBuilder.set("reseal_manager", address(ctx.resealManager));
            configBuilder.set("dual_governance", address(ctx.dualGovernance));
            configBuilder.set("escrow_master_copy", address(ctx.escrowMasterCopy));
            configBuilder.set("admin_executor", address(ctx.adminExecutor));
            configBuilder.set("emergency_governance", address(ctx.emergencyGovernance));
        } else if (field.equal(DG_CONFIG_PROVIDER_ROOT_KEY)) {
            configBuilder.set(DG_CONFIG_PROVIDER_ROOT_KEY, address(ctx.dualGovernanceConfigProvider));
        } else if (field.equal(EXECUTOR_ROOT_KEY)) {
            configBuilder.set("admin_executor", address(ctx.adminExecutor));
        }

        return configBuilder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("DualGovernance address", address(ctx.dualGovernance));
        console.log("DualGovernanceConfigProvider address", address(ctx.dualGovernanceConfigProvider));
        console.log("EscrowMasterCopy address", address(ctx.escrowMasterCopy));
        console.log("ResealManager address", address(ctx.resealManager));
        console.log("TiebreakerCoreCommittee address", address(ctx.tiebreakerCoreCommittee));

        address[] memory tiebreakerSubCommittees = _getTiebreakerSubCommitteeAddresses(ctx);

        for (uint256 i = 0; i < tiebreakerSubCommittees.length; ++i) {
            console.log("TiebreakerSubCommittee[%d] address %x", i, tiebreakerSubCommittees[i]);
        }

        console.log("AdminExecutor address", address(ctx.adminExecutor));
        console.log("EmergencyProtectedTimelock address", address(ctx.timelock));
        console.log("EmergencyGovernance address", address(ctx.emergencyGovernance));

        console.log("\n");
    }

    function _getTiebreakerSubCommitteeAddresses(Context memory ctx)
        private
        pure
        returns (address[] memory tiebreakerSubCommittees)
    {
        tiebreakerSubCommittees = new address[](ctx.tiebreakerSubCommittees.length);
        for (uint256 i = 0; i < tiebreakerSubCommittees.length; ++i) {
            tiebreakerSubCommittees[i] = address(ctx.tiebreakerSubCommittees[i]);
        }
    }
}

library DGSetupDeployArtifacts {
    using DGSetupDeployConfig for DGSetupDeployConfig.Context;
    using DGSetupDeployedContracts for DGSetupDeployedContracts.Context;
    using DGLaunchConfig for DGLaunchConfig.Context;

    struct Context {
        DGSetupDeployConfig.Context deployConfig;
        DGSetupDeployedContracts.Context deployedContracts;
    }

    function load(string memory deployArtifactFileName) internal view returns (Context memory ctx) {
        string memory deployArtifactFilePath = DeployFiles.resolveDeployArtifact(deployArtifactFileName);
        ctx.deployConfig = DGSetupDeployConfig.load(deployArtifactFilePath, "deploy_config");
        ctx.deployedContracts = DGSetupDeployedContracts.load(deployArtifactFilePath, "deployed_contracts");
    }

    function loadDGLaunchConfig(string memory deployArtifactFileName)
        internal
        view
        returns (DGLaunchConfig.Context memory)
    {
        string memory deployArtifactFilePath = DeployFiles.resolveDeployArtifact(deployArtifactFileName);
        return DGLaunchConfig.load(deployArtifactFilePath);
    }

    function save(Context memory ctx, string memory fileName) internal {
        ConfigFileBuilder.Context memory configBuilder = ConfigFileBuilder.create();
        string memory deployArtifactFilePath = DeployFiles.resolveDeployArtifact(fileName);

        // forgefmt: disable-next-item
        configBuilder
            .set("deploy_config", ctx.deployConfig.toJSON())
            .set("deployed_contracts", ctx.deployedContracts.toJSON())
            .write(deployArtifactFilePath);

        console.log("\n");
        console.log("Deploy artifact saved to: %s", deployArtifactFilePath);
    }

    function save(Context memory ctx, string memory fileName, string memory field) internal {
        ConfigFileBuilder.Context memory configBuilder = ConfigFileBuilder.create();
        string memory deployArtifactFilePath = DeployFiles.resolveDeployArtifact(fileName);

        // forgefmt: disable-next-item
        configBuilder
            .set("deploy_config", ctx.deployConfig.toJSON(field))
            .set("deployed_contracts", ctx.deployedContracts.toJSON(field))
            .write(deployArtifactFilePath);

        console.log("\n");
        console.log("Deploy artifact saved to: %s", deployArtifactFilePath);
    }
}

library DGLaunchConfig {
    struct Context {
        uint256 chainId;
        TimelockedGovernance daoEmergencyGovernance;
        address dgLaunchVerifier;
        address rolesValidator;
        address timeConstraints;
        IVotingProvider omnibusContract;
    }

    function load(string memory configFilePath) internal view returns (Context memory ctx) {
        return load(configFilePath, "");
    }

    function load(
        string memory configFilePath,
        string memory configRootKey
    ) internal view returns (Context memory ctx) {
        string memory $ = configRootKey.root();

        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);

        string memory $daoVoting = $.key("dg_launch");

        ctx.daoEmergencyGovernance = TimelockedGovernance(file.readAddress($daoVoting.key("dao_emergency_governance")));
        ctx.dgLaunchVerifier = file.readAddress($daoVoting.key("dg_launch_verifier"));
        ctx.rolesValidator = file.readAddress($daoVoting.key("roles_validator"));
        ctx.timeConstraints = file.readAddress($daoVoting.key("time_constraints"));
        ctx.omnibusContract = IVotingProvider(file.readAddress($daoVoting.key("omnibus_contract")));
    }
}

library StringUtils {
    function equal(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
