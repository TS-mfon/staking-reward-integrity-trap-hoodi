# Staking Reward Integrity Trap

Drosera Hoodi trap for Synthetix-style staking reward accounting.

The trap monitors whether global staking reward accounting remains mathematically consistent over time. It does not track individual users, so it is suitable as a compact example trap for staking systems with a standard `rewardPerToken` model.

## Network

- Chain: Hoodi
- Chain ID: `560048`
- Default RPC: `https://ethereum-hoodi-rpc.publicnode.com`
- Drosera relay: `https://relay.hoodi.drosera.io`

## Monitored Interface

```solidity
interface IStakingRewards {
    function totalSupply() external view returns (uint256);
    function rewardRate() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function lastUpdateTime() external view returns (uint256);
    function periodFinish() external view returns (uint256);
    function rewardsToken() external view returns (address);
}
```

The trap also reads:

```solidity
function balanceOf(address account) external view returns (uint256);
```

on the reward token.

## Plug-in Registry

The trap reads its target from:

```solidity
address constant REGISTRY = 0x0000000000000000000000000000000000007101;
```

The registry stores:

- `environmentId`
- `stakingRewards`
- `responseContract`
- `active`

This lets a Hoodi deployment plug in any Synthetix-style staking contract without changing the trap bytecode.

## Core Invariant

For two ordered samples:

```text
observedRewardPerTokenDelta <= elapsedTime * rewardRate * 1e18 / totalSupply
```

The trap applies a small tolerance of `1%` to avoid edge rounding false positives.

## Additional Checks

The trap also detects:

- reward reserves are insufficient to pay promised future rewards
- rewards continue accruing after `periodFinish`
- `rewardRate` changes unexpectedly
- failed state collection
- invalid sample ordering

## Response Function

```solidity
function pauseRewardClaims(bytes calldata reasonData) external;
```

The returned `reasonData` encodes:

```solidity
abi.encode(
    currentRewardPerToken,
    previousRewardPerToken,
    observedDelta,
    allowedDelta,
    reasonBitmap
)
```

The included `StakingRewardIntegrityResponse` is an alert-style response contract that emits `RewardClaimsPaused`. A production staking contract can replace it with a real emergency pause executor.

## Reason Bitmap

| Bit | Reason |
| --- | --- |
| `1 << 0` | `rewardPerToken` increased too fast |
| `1 << 1` | reward reserve shortfall |
| `1 << 2` | accrual after reward period ended |
| `1 << 3` | reward rate changed |
| `1 << 4` | collect failed |
| `1 << 5` | invalid sample window |

## Build and Test

```bash
forge build
forge test -vvv
drosera dryrun
```

The trap was generated using the local Drosera MCP context and follows the Drosera `collect()` / `shouldRespond()` interface used in the provided Drosera examples.

