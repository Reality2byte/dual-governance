// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";

import {Executor} from "contracts/Executor.sol";
import {TimelockedGovernance} from "contracts/TimelockedGovernance.sol";
import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

import {ConfigFileReader, ConfigFileBuilder, JsonKeys} from "../ConfigFiles.sol";

import {TimelockContractDeployConfig} from "./Timelock.sol";

error InvalidParameter(string parameter);
error InvalidChainId(uint256 actual, uint256 expected);

using JsonKeys for string;
using ConfigFileBuilder for ConfigFileBuilder.Context;
using ConfigFileReader for ConfigFileReader.Context;

library TimelockedGovernanceDeployConfig {
    struct Context {
        uint256 chainId;
        address governance;
        EmergencyProtectedTimelock timelock;
    }

    function load(
        string memory configFilePath,
        string memory configRootKey
    ) internal view returns (Context memory ctx) {
        string memory $ = configRootKey.root();
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);

        ctx.chainId = file.readUint($.key("chain_id"));
        ctx.governance = file.readAddress($.key("timelocked_governance.governance"));
        ctx.timelock = EmergencyProtectedTimelock(file.readAddress($.key("timelocked_governance.timelock")));
    }

    function validate(Context memory ctx) internal view {
        if (ctx.chainId != block.chainid) {
            revert InvalidChainId({actual: block.chainid, expected: ctx.chainId});
        }
        if (address(ctx.timelock) == address(0)) {
            revert InvalidParameter("timelock");
        }
        if (ctx.governance == address(0)) {
            revert InvalidParameter("governance");
        }
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("governance", ctx.governance);
        builder.set("timelock", address(ctx.timelock));

        return builder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("Governance address", ctx.governance);
        console.log("Timelock address", address(ctx.timelock));
    }
}

library TimelockedGovernanceDeployedContracts {
    struct Context {
        TimelockedGovernance timelockedGovernance;
    }

    function load(
        string memory deployedContractsFilePath,
        string memory prefix
    ) internal view returns (Context memory ctx) {
        string memory $ = prefix.root();
        ConfigFileReader.Context memory deployedContract = ConfigFileReader.load(deployedContractsFilePath);

        ctx.timelockedGovernance = TimelockedGovernance(deployedContract.readAddress($.key("timelocked_governance")));
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("timelocked_governance", address(ctx.timelockedGovernance));

        return builder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("TimelockedGovernance address", address(ctx.timelockedGovernance));
    }
}

library TGSetupDeployConfig {
    struct Context {
        uint256 chainId;
        address governance;
        TimelockContractDeployConfig.Context timelock;
    }
}

library TGSetupDeployedContracts {
    struct Context {
        Executor adminExecutor;
        EmergencyProtectedTimelock timelock;
        TimelockedGovernance timelockedGovernance;
    }
}
