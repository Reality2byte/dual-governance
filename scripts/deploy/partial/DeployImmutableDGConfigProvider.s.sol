// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DualGovernanceConfig} from "contracts/libraries/DualGovernanceConfig.sol";

import {
    ContractsDeployment,
    DGSetupDeployConfig,
    DGSetupDeployArtifacts,
    DGSetupDeployedContracts
} from "scripts/utils/contracts-deployment.sol";
import {
    ImmutableDualGovernanceConfigProviderDeployConfig,
    DEFAULT_ROOT_KEY as DG_CONFIG_PROVIDER_ROOT_KEY
} from "scripts/utils/deployment/ImmutableDualGovernanceConfigProvider.sol";
import {DeployFiles} from "scripts/utils/DeployFiles.sol";

contract DeployImmutableDGConfigProvider is Script {
    using DGSetupDeployConfig for DGSetupDeployConfig.Context;
    using DGSetupDeployArtifacts for DGSetupDeployArtifacts.Context;
    using DGSetupDeployedContracts for DGSetupDeployedContracts.Context;
    using DualGovernanceConfig for DualGovernanceConfig.Context;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    function run() public {
        string memory configFileName = vm.envString("DEPLOY_CONFIG_FILE_NAME");
        string memory deployFileName = DeployFiles.resolveDeployConfig(configFileName);

        console.log("Loading config file: %s", configFileName);
        DGSetupDeployArtifacts.Context memory deployArtifact;

        deployArtifact.deployConfig.chainId = DGSetupDeployConfig.loadChainId(deployFileName);
        deployArtifact.deployConfig.dualGovernanceConfigProvider =
            ImmutableDualGovernanceConfigProviderDeployConfig.load(deployFileName);

        deployArtifact.deployConfig.dualGovernanceConfigProvider.validate();
        deployArtifact.deployConfig.validateChainId();
        deployArtifact.deployConfig.print();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");
        console.log("Deployer account: %x", deployer);

        vm.startBroadcast();

        deployArtifact.deployedContracts.dualGovernanceConfigProvider =
            ContractsDeployment.deployDualGovernanceConfigProvider(
                deployArtifact.deployConfig.dualGovernanceConfigProvider
            );

        vm.stopBroadcast();

        console.log("");
        console.log("Immutable Dual Governance Config Provider deployed successfully");
        deployArtifact.deployedContracts.print();

        string memory deployArtifactFileName = string.concat(
            "deploy-artifact-immutable-dg-config-provider-",
            vm.toString(block.chainid),
            "-",
            vm.toString(block.timestamp),
            ".toml"
        );

        deployArtifact.save(deployArtifactFileName, DG_CONFIG_PROVIDER_ROOT_KEY);
    }
}
