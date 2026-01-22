// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {TiebreakerSubCommittee} from "contracts/committees/TiebreakerSubCommittee.sol";

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
import {DeployVerification} from "scripts/utils/DeployVerification.sol";
import {DeployFiles} from "scripts/utils/DeployFiles.sol";

contract DeployTiebreakerCommittees is Script {
    using DGSetupDeployConfig for DGSetupDeployConfig.Context;
    using DGSetupDeployArtifacts for DGSetupDeployArtifacts.Context;
    using DGSetupDeployedContracts for DGSetupDeployedContracts.Context;
    using TiebreakerDeployConfig for TiebreakerDeployConfig.Context;

    error ChainIdMismatch(uint256 actual, uint256 expected);

    address constant TIEBREAKER_CORE_COMMITTEE = address(0);

    function run() public {
        assert(TIEBREAKER_CORE_COMMITTEE != address(0));

        string memory configFileName = vm.envString("DEPLOY_CONFIG_FILE_NAME");
        string memory deployFileName = DeployFiles.resolveDeployConfig(configFileName);

        console.log("Loading config file: %s", configFileName);
        DGSetupDeployArtifacts.Context memory deployArtifact;
        deployArtifact.deployConfig.chainId = DGSetupDeployConfig.loadChainId(deployFileName);
        deployArtifact.deployConfig.tiebreaker = TiebreakerDeployConfig.loadSubCommittees(deployFileName, "");

        deployArtifact.deployConfig.tiebreaker.validateSubCommittees();
        deployArtifact.deployConfig.validateChainId();
        deployArtifact.deployConfig.print();

        address deployer = msg.sender;
        vm.label(deployer, "DEPLOYER");
        console.log("Deployer account: %x", deployer);

        vm.startBroadcast();

        TiebreakerSubCommittee[] memory contracts =
            ContractsDeployment.deployTiebreakerSubCommittee(deployArtifact.deployConfig.tiebreaker, deployer);

        vm.stopBroadcast();

        deployArtifact.deployedContracts.tiebreakerSubCommittees = contracts;

        console.log("");
        console.log("Tiebreaker subcommittees deployed successfully");
        deployArtifact.deployedContracts.print();

        string memory deployArtifactFileName = string.concat(
            "deploy-artifact-tiebreaker-subcommittees-",
            vm.toString(block.chainid),
            "-",
            vm.toString(block.timestamp),
            ".toml"
        );

        deployArtifact.save(deployArtifactFileName, TIEBREAKER_ROOT_KEY);
    }
}
