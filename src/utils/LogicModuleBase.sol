// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IAssetLayerV0_1} from "../IAssetLayerV0_1.sol";
import {ILogicProxy} from "./ILogicProxy.sol";

/// @author philogy <https://github.com/philogy>
abstract contract LogicModuleBase {
    error ZeroAddress();

    function transferERC20From(
        address _token,
        address _sender,
        uint256 _amount
    ) internal {
        getAssetLayer().naivePullERC20(_token, _sender, _amount);
    }

    function safeTransferERC20From(
        address _token,
        address _sender,
        uint256 _amount
    ) internal returns (uint256) {
        return getAssetLayer().pullERC20(_token, _sender, _amount);
    }

    function safeTransferERC20From(
        address _token,
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal returns (uint256 sentAmount) {
        IAssetLayerV0_1 assetLayerCached = getAssetLayer();
        sentAmount = assetLayerCached.pullERC20(_token, _sender, _amount);
        if (_recipient != address(this)) {
            assetLayerCached.withdrawERC20(_token, _recipient, sentAmount);
        }
    }

    function transferERC20(
        address _token,
        address _recipient,
        uint256 _amount
    ) internal {
        getAssetLayer().withdrawERC20(_token, _recipient, _amount);
    }

    function transferERC721From(
        address _token,
        address _sender,
        uint256 _tokenId
    ) internal {
        getAssetLayer().pullERC721(_token, _sender, _tokenId);
    }

    function transferERC721From(
        address _token,
        address _sender,
        address _recipient,
        uint256 _tokenId
    ) internal {
        IAssetLayerV0_1 assetLayerCached = getAssetLayer();
        assetLayerCached.pullERC721(_token, _sender, _tokenId);
        if (_recipient != address(this)) {
            assetLayerCached.withdrawERC721(_token, _recipient, _tokenId);
        }
    }

    function transferERC721(
        address _token,
        address _recipient,
        uint256 _tokenId
    ) internal {
        getAssetLayer().withdrawERC721(_token, _recipient, _tokenId);
    }

    function transferETH(address _recipient, uint256 _amount) internal {
        transferNative(_recipient, _amount);
    }

    function transferNative(address _recipient, uint256 _amount) internal {
        getAssetLayer().withdrawNative(_recipient, _amount);
    }

    function getAssetLayer() internal view returns (IAssetLayerV0_1) {
        return IAssetLayerV0_1(ILogicProxy(address(this)).getAssetLayer());
    }
}
