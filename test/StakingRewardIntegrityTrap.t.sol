// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/StakingRewardIntegrityEnvironmentRegistry.sol";
import "../src/StakingRewardIntegrityResponse.sol";
import "../src/StakingRewardIntegrityTrap.sol";

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function roll(uint256 blockNumber) external;
    function warp(uint256 timestamp) external;
    function prank(address sender) external;
}

contract RewardTokenMock {
    mapping(address => uint256) public balanceOf;

    function setBalance(address account, uint256 value) external {
        balanceOf[account] = value;
    }
}

contract StakingRewardsMock {
    uint256 public totalSupply;
    uint256 public rewardRate;
    uint256 public rewardPerToken;
    uint256 public lastUpdateTime;
    uint256 public periodFinish;
    address public rewardsToken;

    function setState(
        uint256 totalSupply_,
        uint256 rewardRate_,
        uint256 rewardPerToken_,
        uint256 lastUpdateTime_,
        uint256 periodFinish_,
        address rewardsToken_
    ) external {
        totalSupply = totalSupply_;
        rewardRate = rewardRate_;
        rewardPerToken = rewardPerToken_;
        lastUpdateTime = lastUpdateTime_;
        periodFinish = periodFinish_;
        rewardsToken = rewardsToken_;
    }
}

contract StakingRewardIntegrityTrapTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant REGISTRY = address(0x0000000000000000000000000000000000007101);
    address internal constant STAKING = address(0x0000000000000000000000000000000000007201);
    address internal constant TOKEN = address(0x0000000000000000000000000000000000007301);
    address internal constant DROSERA = address(0xD005E7A);

    function testHealthyRewardPerTokenDoesNotTrigger() public {
        StakingRewardIntegrityTrap trap = _deploy();
        bytes[] memory data = _samples(trap, 1e16);
        (bool ok,) = trap.shouldRespond(data);
        _assertFalse(ok, "mathematically valid rewardPerToken delta should not trigger");
    }

    function testRewardPerTokenJumpTriggers() public {
        StakingRewardIntegrityTrap trap = _deploy();
        bytes[] memory data = _samples(trap, 50e18);
        (bool ok, bytes memory payload) = trap.shouldRespond(data);
        _assertTrue(ok, "excess rewardPerToken jump should trigger");
        (,,,, uint256 reasons) = abi.decode(payload, (uint256, uint256, uint256, uint256, uint256));
        _assertTrue((reasons & trap.REASON_RPT_TOO_FAST()) != 0, "rpt too fast reason");
    }

    function testReserveShortfallTriggers() public {
        StakingRewardIntegrityTrap trap = _deploy();
        RewardTokenMock(TOKEN).setBalance(STAKING, 1 ether);
        bytes[] memory data = _samples(trap, 10e18);
        (bool ok, bytes memory payload) = trap.shouldRespond(data);
        _assertTrue(ok, "reward reserve shortfall should trigger");
        (,,,, uint256 reasons) = abi.decode(payload, (uint256, uint256, uint256, uint256, uint256));
        _assertTrue((reasons & trap.REASON_REWARD_RESERVE_SHORTFALL()) != 0, "shortfall reason");
    }

    function testResponseOnlyDrosera() public {
        StakingRewardIntegrityResponse response = new StakingRewardIntegrityResponse(DROSERA);
        bool reverted;
        try response.pauseRewardClaims("") {}
        catch {
            reverted = true;
        }
        _assertTrue(reverted, "non-Drosera caller rejected");
        vm.prank(DROSERA);
        response.pauseRewardClaims("");
    }

    function _deploy() internal returns (StakingRewardIntegrityTrap trap) {
        vm.roll(1_000);
        vm.warp(10_000);
        StakingRewardIntegrityEnvironmentRegistry registryImpl =
            new StakingRewardIntegrityEnvironmentRegistry(keccak256("unused"), address(0), address(0), false);
        StakingRewardsMock stakingImpl = new StakingRewardsMock();
        RewardTokenMock tokenImpl = new RewardTokenMock();
        vm.etch(REGISTRY, address(registryImpl).code);
        vm.etch(STAKING, address(stakingImpl).code);
        vm.etch(TOKEN, address(tokenImpl).code);
        StakingRewardIntegrityEnvironmentRegistry(REGISTRY).setConfig(
            keccak256("staking-reward-integrity-trap-hoodi"), STAKING, address(0), true
        );
        RewardTokenMock(TOKEN).setBalance(STAKING, 100_000 ether);
        StakingRewardsMock(STAKING).setState(100 ether, 1 ether, 1_000e18, block.timestamp, block.timestamp + 1 days, TOKEN);
        trap = new StakingRewardIntegrityTrap();
    }

    function _samples(StakingRewardIntegrityTrap trap, uint256 rptIncrease) internal returns (bytes[] memory data) {
        data = new bytes[](2);
        data[1] = trap.collect();
        vm.roll(1_001);
        vm.warp(block.timestamp + 1);
        StakingRewardsMock(STAKING).setState(100 ether, 1 ether, 1_000e18 + rptIncrease, block.timestamp, block.timestamp + 1 days, TOKEN);
        data[0] = trap.collect();
    }

    function _assertTrue(bool value, string memory reason) internal pure {
        require(value, reason);
    }

    function _assertFalse(bool value, string memory reason) internal pure {
        require(!value, reason);
    }
}
