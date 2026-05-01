// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract StakingRewardIntegrityResponse {
    address public immutable drosera;

    event RewardClaimsPaused(bytes reasonData);

    error OnlyDrosera();

    constructor(address drosera_) {
        drosera = drosera_;
    }

    function pauseRewardClaims(bytes calldata reasonData) external {
        if (msg.sender != drosera) revert OnlyDrosera();
        emit RewardClaimsPaused(reasonData);
    }
}

