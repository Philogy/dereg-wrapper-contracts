// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

/// @author philogy <https://github.com/philogy>
interface IAssetLayerV0_1 {
    function setDefaultDelay(uint24 _delay) external;

    function extendGlobalDelay(uint256 _delayIncrease) external;

    function resetGlobalDelayIncrease() external;

    function extendWithdrawalDelay(uint256 _withdrawalId, uint24 _addedDelay)
        external;

    function freeze() external;

    function unfreeze(bytes32 _validWithdrawalsRoot) external;
}
