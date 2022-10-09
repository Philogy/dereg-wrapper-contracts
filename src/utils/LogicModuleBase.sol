// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IAssetLayerV0_1} from "../IAssetLayerV0_1.sol";

/// @author philogy <https://github.com/philogy>
abstract contract LogicModuleBase {
    IAssetLayerV0_1 private assetLayer;

    function _initializeLogicBase(address _assetLayer) internal {
        assetLayer = IAssetLayerV0_1(_assetLayer);
    }

    function transferERC20From(
        address _token,
        address _sender,
        uint256 _amount
    ) internal {
        assetLayer.naivePullERC20(_token, _sender, _amount);
    }

    function transferERC20From(
        address _token,
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal {
        IAssetLayerV0_1 assetLayerCached = assetLayer;
        if (_recipient == address(this)) {
            assetLayerCached.naivePullERC20(_token, _sender, _amount);
        } else {
            uint256 sentAmount = assetLayerCached.pullERC20(
                _token,
                _sender,
                _amount
            );
            assetLayerCached.withdrawERC20(_token, _recipient, sentAmount);
        }
    }

    function safeTransferERC20From(
        address _token,
        address _sender,
        uint256 _amount
    ) internal returns (uint256) {
        return assetLayer.pullERC20(_token, _sender, _amount);
    }

    function safeTransferERC20From(
        address _token,
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal returns (uint256 sentAmount) {
        IAssetLayerV0_1 assetLayerCached = assetLayer;
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
        assetLayer.withdrawERC20(_token, _recipient, _amount);
    }

    function transferERC721From(
        address _token,
        address _sender,
        uint256 _tokenId
    ) internal {
        assetLayer.pullERC721(_token, _sender, _tokenId);
    }

    function transferERC721From(
        address _token,
        address _sender,
        address _recipient,
        uint256 _tokenId
    ) internal {
        IAssetLayerV0_1 assetLayerCached = assetLayer;
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
        assetLayer.withdrawERC721(_token, _recipient, _tokenId);
    }

    function transferETH(address _recipient, uint256 _amount) internal {
        assetLayer.withdrawNative(_recipient, _amount);
    }

    function transferNative(address _recipient, uint256 _amount) internal {
        assetLayer.withdrawNative(_recipient, _amount);
    }
}
