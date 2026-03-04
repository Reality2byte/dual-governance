// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";

import {EmergencyProtectedTimelock} from "contracts/EmergencyProtectedTimelock.sol";

import {Duration} from "contracts/types/Duration.sol";
import {Timestamp} from "contracts/types/Timestamp.sol";

import {ConfigFileReader, ConfigFileBuilder, JsonKeys} from "../ConfigFiles.sol";

error InvalidParameter(string parameter);
error InvalidChainId(uint256 actual, uint256 expected);

using JsonKeys for string;
using ConfigFileBuilder for ConfigFileBuilder.Context;
using ConfigFileReader for ConfigFileReader.Context;

string constant DEFAULT_ROOT_KEY = "timelock";

library TimelockContractDeployConfig {
    struct Context {
        Duration afterSubmitDelay;
        Duration afterScheduleDelay;
        EmergencyProtectedTimelock.SanityCheckParams sanityCheckParams;
        Duration emergencyModeDuration;
        Timestamp emergencyProtectionEndDate;
        address emergencyGovernanceProposer;
        address emergencyActivationCommittee;
        address emergencyExecutionCommittee;
    }

    function load(
        string memory configFilePath,
        string memory configRootKey
    ) internal view returns (Context memory ctx) {
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);

        string memory $ = configRootKey.key(DEFAULT_ROOT_KEY);
        string memory $sanityCheckParams = $.key("sanity_check_params");
        string memory $emergencyProtection = $.key("emergency_protection");

        return Context({
            afterSubmitDelay: file.readDuration($.key("after_submit_delay")),
            afterScheduleDelay: file.readDuration($.key("after_schedule_delay")),
            sanityCheckParams: EmergencyProtectedTimelock.SanityCheckParams({
                minExecutionDelay: file.readDuration($sanityCheckParams.key("min_execution_delay")),
                maxAfterSubmitDelay: file.readDuration($sanityCheckParams.key("max_after_submit_delay")),
                maxAfterScheduleDelay: file.readDuration($sanityCheckParams.key("max_after_schedule_delay")),
                maxEmergencyModeDuration: file.readDuration($sanityCheckParams.key("max_emergency_mode_duration")),
                maxEmergencyProtectionDuration: file.readDuration(
                    $sanityCheckParams.key("max_emergency_protection_duration")
                )
            }),
            emergencyGovernanceProposer: file.readAddress($emergencyProtection.key("emergency_governance_proposer")),
            emergencyActivationCommittee: file.readAddress($emergencyProtection.key("emergency_activation_committee")),
            emergencyExecutionCommittee: file.readAddress($emergencyProtection.key("emergency_execution_committee")),
            emergencyModeDuration: file.readDuration($emergencyProtection.key("emergency_mode_duration")),
            emergencyProtectionEndDate: file.readTimestamp($emergencyProtection.key("emergency_protection_end_date"))
        });
    }

    function validate(Context memory ctx) internal pure {
        if (ctx.afterSubmitDelay > ctx.sanityCheckParams.maxAfterSubmitDelay) {
            revert InvalidParameter("timelock.after_submit_delay");
        }

        if (ctx.afterScheduleDelay > ctx.sanityCheckParams.maxAfterScheduleDelay) {
            revert InvalidParameter("timelock.after_schedule_delay");
        }

        if (ctx.emergencyModeDuration > ctx.sanityCheckParams.maxEmergencyModeDuration) {
            revert InvalidParameter("timelock.emergency_mode_duration");
        }
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("after_schedule_delay", ctx.afterScheduleDelay);
        builder.set("after_submit_delay", ctx.afterSubmitDelay);
        builder.set("sanity_check_params", _sanityCheckParamsToJSON(ctx));
        builder.set("emergency_protection", _emergencyProtectionToJSON(ctx));

        return builder.content;
    }

    function _sanityCheckParamsToJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("min_execution_delay", ctx.sanityCheckParams.minExecutionDelay);
        builder.set("max_after_submit_delay", ctx.sanityCheckParams.maxAfterSubmitDelay);
        builder.set("max_after_schedule_delay", ctx.sanityCheckParams.maxAfterScheduleDelay);
        builder.set("max_emergency_mode_duration", ctx.sanityCheckParams.maxEmergencyModeDuration);
        builder.set("max_emergency_protection_duration", ctx.sanityCheckParams.maxEmergencyProtectionDuration);

        return builder.content;
    }

    function _emergencyProtectionToJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();

        builder.set("emergency_mode_duration", ctx.emergencyModeDuration);
        builder.set("emergency_protection_end_date", ctx.emergencyProtectionEndDate);
        builder.set("emergency_governance_proposer", ctx.emergencyGovernanceProposer);
        builder.set("emergency_activation_committee", ctx.emergencyActivationCommittee);
        builder.set("emergency_execution_committee", ctx.emergencyExecutionCommittee);

        return builder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("===== Timelock");
        console.log("After submit delay", ctx.afterSubmitDelay.toSeconds());
        console.log("After schedule delay", ctx.afterScheduleDelay.toSeconds());
        console.log("\n");
        console.log("===== Timelock. Sanity check params");
        console.log("Min execution delay", ctx.sanityCheckParams.minExecutionDelay.toSeconds());
        console.log("Max after submit delay", ctx.sanityCheckParams.maxAfterSubmitDelay.toSeconds());
        console.log("Max after schedule delay", ctx.sanityCheckParams.maxAfterScheduleDelay.toSeconds());
        console.log("Max emergency mode duration", ctx.sanityCheckParams.maxEmergencyModeDuration.toSeconds());
        console.log(
            "Max emergency protection duration", ctx.sanityCheckParams.maxEmergencyProtectionDuration.toSeconds()
        );
        console.log("\n");
        console.log("===== Timelock. Emergency protection");
        console.log("Emergency activation committee", ctx.emergencyActivationCommittee);
        console.log("Emergency execution committee", ctx.emergencyExecutionCommittee);
        console.log("Emergency governance proposer", ctx.emergencyGovernanceProposer);
        console.log("Emergency mode duration", ctx.emergencyModeDuration.toSeconds());
        console.log("Emergency protection end date", ctx.emergencyProtectionEndDate.toSeconds());
        console.log("\n");
    }
}
