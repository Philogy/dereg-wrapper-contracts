// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

/// @author philogy <https://github.com/philogy>
interface IAssetLayerV0_1 {
    function pullERC20(
        address _collection,
        address _sender,
        uint256 _tokenAmount
    ) external returns (uint256);

    function naivePullERC20(
        address _collection,
        address _sender,
        uint256 _tokenAmount
    ) external;

    function pullERC721(
        address _collection,
        address _owner,
        uint256 _tokenId
    ) external;

    function withdrawERC20(
        address _token,
        address _recipient,
        uint256 _tokens
    ) external;

    function withdrawERC721(
        address _token,
        address _recipient,
        uint256 _tokenId
    ) external;

    function withdrawNative(address _recipient, uint256 _amount) external;
}
