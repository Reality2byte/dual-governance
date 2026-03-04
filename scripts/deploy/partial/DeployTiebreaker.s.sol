// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {
    ContractsDeployment,
    DGSetupDeployConfig,
    DGSetupDeployArtifacts,
    DGSetupDeployedContracts
} from "scripts/utils/contracts-deployment.sol";
import {
    TiebreakerDeployConfig,
    TiebreakerDeployedContracts,
    DEFAULT_ROOT_KEY as TIEBREAKER_ROOT_KEY
} from "scripts/utils/deployment/Tiebreaker.sol";
import {DeployFiles} from "scripts/utils/DeployFiles.sol";

contract DeployTiebreaker is Script {
    using DGSetupDeployConfig for DGSetupDeployConfig.Context;
    using DGSetupDeployArtifacts for DGSetupDeployArtifacts.Context;
    using DGSetupDeployedContracts for DGSetupDeployedContracts.Context;
    using TiebreakerDeployConfig for TiebreakerDeployConfig.Context;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    function run() public {
        string memory configFileName = vm.envString("DEPLOY_CONFIG_FILE_NAME");
        string memory deployFileName = DeployFiles.resolveDeployConfig(configFileName);

        console.log("Loading config file: %s", configFileName);
        DGSetupDeployArtifacts.Context memory deployArtifact;

        deployArtifact.deployConfig.chainId = DGSetupDeployConfig.loadChainId(deployFileName);
        deployArtifact.deployConfig.tiebreaker = TiebreakerDeployConfig.load(deployFileName);

        deployArtifact.deployConfig.tiebreaker.validate();
        deployArtifact.deployConfig.validateChainId();

        deployArtifact.deployConfig.print();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");
        console.log("Deployer account: %x", deployer);

        vm.startBroadcast();

        TiebreakerDeployedContracts.Context memory contracts =
            ContractsDeployment.deployTiebreaker(deployArtifact.deployConfig.tiebreaker, deployer);

        vm.stopBroadcast();

        deployArtifact.deployedContracts.tiebreakerCoreCommittee = contracts.tiebreakerCoreCommittee;
        deployArtifact.deployedContracts.tiebreakerSubCommittees = contracts.tiebreakerSubCommittees;

        console.log("");
        console.log("Tiebreaker deployed successfully");
        deployArtifact.deployedContracts.print();

        string memory deployArtifactFileName = string.concat(
            "deploy-artifact-tiebreaker-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".toml"
        );

        deployArtifact.save(deployArtifactFileName, TIEBREAKER_ROOT_KEY);
    }
}
