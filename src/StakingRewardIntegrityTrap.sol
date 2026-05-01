// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "./ITrap.sol";

interface IStakingRewardIntegrityRegistry {
    function environmentId() external view returns (bytes32);
    function stakingRewards() external view returns (address);
    function active() external view returns (bool);
}

interface IStakingRewards {
    function totalSupply() external view returns (uint256);
    function rewardRate() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function lastUpdateTime() external view returns (uint256);
    function periodFinish() external view returns (uint256);
    function rewardsToken() external view returns (address);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract StakingRewardIntegrityTrap is ITrap {
    address public constant REGISTRY = address(0x0000000000000000000000000000000000007101);

    uint256 public constant REQUIRED_SAMPLES = 2;
    uint256 public constant MAX_BLOCK_GAP = 64;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant TOLERANCE_BPS = 100;
    uint256 public constant BPS = 10_000;

    uint256 public constant REASON_RPT_TOO_FAST = 1 << 0;
    uint256 public constant REASON_REWARD_RESERVE_SHORTFALL = 1 << 1;
    uint256 public constant REASON_ACCRUAL_AFTER_PERIOD_END = 1 << 2;
    uint256 public constant REASON_REWARD_RATE_CHANGE = 1 << 3;
    uint256 public constant REASON_COLLECT_FAILED = 1 << 4;
    uint256 public constant REASON_INVALID_SAMPLE_WINDOW = 1 << 5;

    uint8 internal constant STATUS_OK = 0;
    uint8 internal constant STATUS_REGISTRY_INACTIVE = 1;
    uint8 internal constant STATUS_TARGET_MISSING = 2;
    uint8 internal constant STATUS_CALL_FAILED = 3;

    struct CollectOutput {
        bytes32 environmentId;
        address stakingRewards;
        address rewardsToken;
        uint8 status;
        uint256 observedBlockNumber;
        uint256 observedTimestamp;
        uint256 totalSupply;
        uint256 rewardRate;
        uint256 rewardPerToken;
        uint256 lastUpdateTime;
        uint256 periodFinish;
        uint256 rewardTokenBalance;
    }

    function collect() external view returns (bytes memory) {
        if (REGISTRY.code.length == 0) return _status(bytes32(0), address(0), address(0), STATUS_TARGET_MISSING);
        IStakingRewardIntegrityRegistry registry = IStakingRewardIntegrityRegistry(REGISTRY);
        bytes32 environmentId = registry.environmentId();
        address target = registry.stakingRewards();
        if (!registry.active()) return _status(environmentId, target, address(0), STATUS_REGISTRY_INACTIVE);
        if (target.code.length == 0) return _status(environmentId, target, address(0), STATUS_TARGET_MISSING);

        try IStakingRewards(target).rewardsToken() returns (address rewardToken) {
            try IStakingRewards(target).totalSupply() returns (uint256 supply) {
                try IStakingRewards(target).rewardRate() returns (uint256 rate) {
                    try IStakingRewards(target).rewardPerToken() returns (uint256 rpt) {
                        try IStakingRewards(target).lastUpdateTime() returns (uint256 lastUpdate) {
                            try IStakingRewards(target).periodFinish() returns (uint256 finish) {
                                uint256 balance = _balance(rewardToken, target);
                                return abi.encode(
                                    CollectOutput({
                                        environmentId: environmentId,
                                        stakingRewards: target,
                                        rewardsToken: rewardToken,
                                        status: STATUS_OK,
                                        observedBlockNumber: block.number,
                                        observedTimestamp: block.timestamp,
                                        totalSupply: supply,
                                        rewardRate: rate,
                                        rewardPerToken: rpt,
                                        lastUpdateTime: lastUpdate,
                                        periodFinish: finish,
                                        rewardTokenBalance: balance
                                    })
                                );
                            } catch {
                                return _status(environmentId, target, rewardToken, STATUS_CALL_FAILED);
                            }
                        } catch {
                            return _status(environmentId, target, rewardToken, STATUS_CALL_FAILED);
                        }
                    } catch {
                        return _status(environmentId, target, rewardToken, STATUS_CALL_FAILED);
                    }
                } catch {
                    return _status(environmentId, target, rewardToken, STATUS_CALL_FAILED);
                }
            } catch {
                return _status(environmentId, target, rewardToken, STATUS_CALL_FAILED);
            }
        } catch {
            return _status(environmentId, target, address(0), STATUS_CALL_FAILED);
        }
    }

    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
        if (data.length < REQUIRED_SAMPLES) return (false, bytes(""));
        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        if (!_validWindow(data)) {
            return (true, abi.encode(current.rewardPerToken, uint256(0), uint256(0), uint256(0), REASON_INVALID_SAMPLE_WINDOW));
        }
        CollectOutput memory previous = abi.decode(data[data.length - 1], (CollectOutput));

        uint256 reasons;
        uint256 observedDelta;
        uint256 allowedDelta;
        if (current.status != STATUS_OK || previous.status != STATUS_OK) reasons |= REASON_COLLECT_FAILED;

        if (current.rewardPerToken > previous.rewardPerToken) {
            observedDelta = current.rewardPerToken - previous.rewardPerToken;
            if (previous.totalSupply > 0) {
                uint256 elapsed = current.observedTimestamp > previous.observedTimestamp
                    ? current.observedTimestamp - previous.observedTimestamp
                    : 0;
                allowedDelta = elapsed * previous.rewardRate * PRECISION / previous.totalSupply;
                allowedDelta = allowedDelta + (allowedDelta * TOLERANCE_BPS / BPS);
                if (observedDelta > allowedDelta) reasons |= REASON_RPT_TOO_FAST;
            }
            if (previous.observedTimestamp >= previous.periodFinish) reasons |= REASON_ACCRUAL_AFTER_PERIOD_END;
        }

        if (current.rewardRate != previous.rewardRate) reasons |= REASON_REWARD_RATE_CHANGE;
        if (current.observedTimestamp < current.periodFinish) {
            uint256 remaining = current.periodFinish - current.observedTimestamp;
            uint256 promised = remaining * current.rewardRate;
            if (promised > current.rewardTokenBalance) reasons |= REASON_REWARD_RESERVE_SHORTFALL;
        }

        if (reasons == 0) return (false, bytes(""));
        return (true, abi.encode(current.rewardPerToken, previous.rewardPerToken, observedDelta, allowedDelta, reasons));
    }

    function _balance(address token, address account) internal view returns (uint256) {
        if (token.code.length == 0 || account == address(0)) return 0;
        try IERC20(token).balanceOf(account) returns (uint256 balance) {
            return balance;
        } catch {
            return 0;
        }
    }

    function _status(bytes32 environmentId, address target, address rewardToken, uint8 status) internal view returns (bytes memory) {
        return abi.encode(
            CollectOutput({
                environmentId: environmentId,
                stakingRewards: target,
                rewardsToken: rewardToken,
                status: status,
                observedBlockNumber: block.number,
                observedTimestamp: block.timestamp,
                totalSupply: 0,
                rewardRate: 0,
                rewardPerToken: 0,
                lastUpdateTime: 0,
                periodFinish: 0,
                rewardTokenBalance: 0
            })
        );
    }

    function _validWindow(bytes[] calldata data) internal pure returns (bool) {
        CollectOutput memory previous = abi.decode(data[0], (CollectOutput));
        for (uint256 i = 1; i < data.length; i++) {
            CollectOutput memory current = abi.decode(data[i], (CollectOutput));
            if (current.environmentId != previous.environmentId) return false;
            if (current.stakingRewards != previous.stakingRewards) return false;
            if (previous.observedBlockNumber <= current.observedBlockNumber) return false;
            if (previous.observedBlockNumber - current.observedBlockNumber > MAX_BLOCK_GAP) return false;
            previous = current;
        }
        return true;
    }
}

