// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable no-console */

import {console} from "forge-std/console.sol";

import {IStETH} from "contracts/interfaces/IStETH.sol";
import {IWstETH} from "contracts/interfaces/IWstETH.sol";
import {IWithdrawalQueue} from "contracts/interfaces/IWithdrawalQueue.sol";

import {Duration} from "contracts/types/Duration.sol";

import {DualGovernance} from "contracts/DualGovernance.sol";

import {ConfigFileReader, ConfigFileBuilder, JsonKeys} from "../ConfigFiles.sol";

error InvalidParameter(string parameter);

using JsonKeys for string;
using ConfigFileBuilder for ConfigFileBuilder.Context;
using ConfigFileReader for ConfigFileReader.Context;

string constant DEFAULT_ROOT_KEY = "dual_governance";

library DualGovernanceContractDeployConfig {
    struct Context {
        address adminProposer;
        address resealCommittee;
        address proposalsCanceller;
        address[] sealableWithdrawalBlockers;
        Duration tiebreakerActivationTimeout;
        DualGovernance.SignallingTokens signallingTokens;
        DualGovernance.SanityCheckParams sanityCheckParams;
    }

    function load(string memory configFilePath, string memory configRootKey) internal view returns (Context memory) {
        ConfigFileReader.Context memory file = ConfigFileReader.load(configFilePath);

        string memory $ = configRootKey.key(DEFAULT_ROOT_KEY);
        string memory $sanityCheck = $.key("sanity_check_params");
        string memory $signallingTokens = $.key("signalling_tokens");

        return Context({
            adminProposer: file.readAddress($.key("admin_proposer")),
            resealCommittee: file.readAddress($.key("reseal_committee")),
            proposalsCanceller: file.readAddress($.key("proposals_canceller")),
            tiebreakerActivationTimeout: file.readDuration($.key("tiebreaker_activation_timeout")),
            sealableWithdrawalBlockers: file.readAddressArray($.key("sealable_withdrawal_blockers")),
            sanityCheckParams: DualGovernance.SanityCheckParams({
                minWithdrawalsBatchSize: file.readUint($sanityCheck.key("min_withdrawals_batch_size")),
                minTiebreakerActivationTimeout: file.readDuration(
                    $sanityCheck.key("min_tiebreaker_activation_timeout")
                ),
                maxTiebreakerActivationTimeout: file.readDuration(
                    $sanityCheck.key("max_tiebreaker_activation_timeout")
                ),
                maxSealableWithdrawalBlockersCount: file.readUint(
                    $sanityCheck.key("max_sealable_withdrawal_blockers_count")
                ),
                maxMinAssetsLockDuration: file.readDuration($sanityCheck.key("max_min_assets_lock_duration"))
            }),
            signallingTokens: DualGovernance.SignallingTokens({
                stETH: IStETH(file.readAddress($signallingTokens.key("st_eth"))),
                wstETH: IWstETH(file.readAddress($signallingTokens.key("wst_eth"))),
                withdrawalQueue: IWithdrawalQueue(file.readAddress($signallingTokens.key("withdrawal_queue")))
            })
        });
    }

    function validate(Context memory ctx) internal pure {
        if (ctx.sanityCheckParams.minTiebreakerActivationTimeout > ctx.sanityCheckParams.maxTiebreakerActivationTimeout)
        {
            revert InvalidParameter("dual_governance.sanity_check_params.min_tiebreaker_activation_timeout");
        }

        if (
            ctx.tiebreakerActivationTimeout > ctx.sanityCheckParams.maxTiebreakerActivationTimeout
                || ctx.tiebreakerActivationTimeout < ctx.sanityCheckParams.minTiebreakerActivationTimeout
        ) {
            revert InvalidParameter("dual_governance.tiebreaker_activation_timeout");
        }

        if (ctx.sanityCheckParams.maxSealableWithdrawalBlockersCount == 0) {
            revert InvalidParameter("dual_governance.sanity_check_params.max_sealable_withdrawal_blockers_count");
        }

        if (ctx.sealableWithdrawalBlockers.length > ctx.sanityCheckParams.maxSealableWithdrawalBlockersCount) {
            revert InvalidParameter("dual_governance.sealable_withdrawal_blockers");
        }
    }

    function toJSON(Context memory ctx) internal returns (string memory) {
        ConfigFileBuilder.Context memory builder = ConfigFileBuilder.create();
        // forgefmt: disable-next-item
        {
            ConfigFileBuilder.Context memory sanityCheckParamsBuilder = ConfigFileBuilder.create();

            sanityCheckParamsBuilder.set("min_withdrawals_batch_size", ctx.sanityCheckParams.minWithdrawalsBatchSize);
            sanityCheckParamsBuilder.set("min_tiebreaker_activation_timeout", ctx.sanityCheckParams.minTiebreakerActivationTimeout);
            sanityCheckParamsBuilder.set("max_tiebreaker_activation_timeout", ctx.sanityCheckParams.maxTiebreakerActivationTimeout);
            sanityCheckParamsBuilder.set("max_sealable_withdrawal_blockers_count", ctx.sanityCheckParams.maxSealableWithdrawalBlockersCount);
            sanityCheckParamsBuilder.set("max_min_assets_lock_duration", ctx.sanityCheckParams.maxMinAssetsLockDuration);

            ConfigFileBuilder.Context memory signallingTokensBuilder = ConfigFileBuilder.create();

            signallingTokensBuilder.set("st_eth", address(ctx.signallingTokens.stETH));
            signallingTokensBuilder.set("wst_eth", address(ctx.signallingTokens.wstETH));
            signallingTokensBuilder.set("withdrawal_queue", address(ctx.signallingTokens.withdrawalQueue));

            builder.set("admin_proposer", ctx.adminProposer);
            builder.set("reseal_committee", ctx.resealCommittee);
            builder.set("proposals_canceller", ctx.proposalsCanceller);
            builder.set("signalling_tokens", signallingTokensBuilder.content);
            builder.set("sanity_check_params", sanityCheckParamsBuilder.content);
            builder.set("tiebreaker_activation_timeout", ctx.tiebreakerActivationTimeout);
            builder.set("sealable_withdrawal_blockers", ctx.sealableWithdrawalBlockers);
        }

        return builder.content;
    }

    function print(Context memory ctx) internal pure {
        console.log("===== DualGovernance");
        console.log("Admin proposer", ctx.adminProposer);
        console.log("Reseal committee", ctx.resealCommittee);
        console.log("Proposals canceller", ctx.proposalsCanceller);
        console.log("Tiebreaker activation timeout", ctx.tiebreakerActivationTimeout.toSeconds());
        for (uint256 i = 0; i < ctx.sealableWithdrawalBlockers.length; ++i) {
            console.log("Sealable withdrawal blocker [%d] %s", i, ctx.sealableWithdrawalBlockers[i]);
        }
        console.log("\n");
        console.log("===== DualGovernance. Signalling tokens");
        console.log("stETH address", address(ctx.signallingTokens.stETH));
        console.log("wstETH address", address(ctx.signallingTokens.wstETH));
        console.log("Withdrawal queue address", address(ctx.signallingTokens.withdrawalQueue));
        console.log("\n");
        console.log("===== DualGovernance. Sanity check params");
        console.log("Max min assets lock duration", ctx.sanityCheckParams.maxMinAssetsLockDuration.toSeconds());
        console.log("Max sealable withdrawal blockers count", ctx.sanityCheckParams.maxSealableWithdrawalBlockersCount);
        console.log(
            "Min tiebreaker activation timeout", ctx.sanityCheckParams.minTiebreakerActivationTimeout.toSeconds()
        );
        console.log(
            "Max tiebreaker activation timeout", ctx.sanityCheckParams.maxTiebreakerActivationTimeout.toSeconds()
        );
        console.log("Min withdrawals batch size", ctx.sanityCheckParams.minWithdrawalsBatchSize);
        console.log("\n");
    }
}
