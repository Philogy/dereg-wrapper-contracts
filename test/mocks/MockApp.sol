// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {LogicModuleBase} from "../../src/utils/LogicModuleBase.sol";

/// @author philogy <https://github.com/philogy>
contract MockApp is LogicModuleBase {
    function naivePullERC20(
        address _token,
        address _sender,
        uint256 _amount
    ) external {
        transferERC20From(_token, _sender, _amount);
    }

    function pullERC20(
        address _token,
        address _sender,
        uint256 _amount
    ) external returns (uint256) {
        return safeTransferERC20From(_token, _sender, _amount);
    }

    function pullERC721(
        address _token,
        address _sender,
        uint256 _tokenId
    ) external {
        transferERC721From(_token, _sender, _tokenId);
    }

    function depositETH() external payable {}

    function withdrawERC20(
        address _token,
        address _recipient,
        uint256 _amount
    ) external {
        transferERC20(_token, _recipient, _amount);
    }

    function withdrawERC721(
        address _token,
        address _recipient,
        uint256 _tokenId
    ) external {
        transferERC721(_token, _recipient, _tokenId);
    }

    function withdrawETH(address _recipient, uint256 _amount) external {
        transferETH(_recipient, _amount);
    }
}
