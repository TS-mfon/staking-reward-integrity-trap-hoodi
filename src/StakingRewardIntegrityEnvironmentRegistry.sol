// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract StakingRewardIntegrityEnvironmentRegistry {
    bytes32 public environmentId;
    address public stakingRewards;
    address public responseContract;
    bool public active;

    constructor(bytes32 environmentId_, address stakingRewards_, address responseContract_, bool active_) {
        environmentId = environmentId_;
        stakingRewards = stakingRewards_;
        responseContract = responseContract_;
        active = active_;
    }

    function setConfig(bytes32 environmentId_, address stakingRewards_, address responseContract_, bool active_) external {
        environmentId = environmentId_;
        stakingRewards = stakingRewards_;
        responseContract = responseContract_;
        active = active_;
    }
}

