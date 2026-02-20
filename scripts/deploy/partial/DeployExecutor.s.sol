// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Executor} from "contracts/Executor.sol";

import {
    DGSetupDeployConfig,
    DGSetupDeployArtifacts,
    DGSetupDeployedContracts,
    EXECUTOR_ROOT_KEY
} from "scripts/utils/deployment/Setup.sol";
import {ContractsDeployment} from "scripts/utils/contracts-deployment.sol";
import {DeployFiles} from "scripts/utils/DeployFiles.sol";

contract DeployExecutor is Script {
    using DGSetupDeployConfig for DGSetupDeployConfig.Context;
    using DGSetupDeployArtifacts for DGSetupDeployArtifacts.Context;
    using DGSetupDeployedContracts for DGSetupDeployedContracts.Context;

    address OWNER = makeAddr("OWNER");

    function run() public {
        assert(OWNER != address(0));

        string memory configFileName = vm.envString("DEPLOY_CONFIG_FILE_NAME");
        string memory deployFileName = DeployFiles.resolveDeployConfig(configFileName);

        console.log("Loading config file: %s", configFileName);
        DGSetupDeployArtifacts.Context memory deployArtifact;

        deployArtifact.deployConfig.chainId = DGSetupDeployConfig.loadChainId(deployFileName);
        deployArtifact.deployConfig.validateChainId();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");
        console.log("Deployer account: %x", deployer);

        vm.startBroadcast();

        Executor executor = ContractsDeployment.deployExecutor(OWNER);

        vm.stopBroadcast();

        deployArtifact.deployedContracts.adminExecutor = executor;

        console.log("");
        console.log("Executor deployed successfully");
        deployArtifact.deployedContracts.print();

        string memory deployArtifactFileName = string.concat(
            "deploy-artifact-executor-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".toml"
        );

        deployArtifact.save(deployArtifactFileName, EXECUTOR_ROOT_KEY);
    }
}
