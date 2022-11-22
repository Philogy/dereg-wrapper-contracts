//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {CrispyERC1155} from "src/CrispyERC1155.sol";

contract MockCrispyERC1155 is CrispyERC1155 {
    function mint(
        uint256 _tokenId,
        address _recipient,
        uint96 _auxData
    ) external {
        _uncompliantUnsafeMintSingle(_tokenId, _recipient, _auxData);
    }

    function burn(uint256 _tokenId) external returns (address lastOwner, uint96 auxData) {
        (lastOwner, auxData) = _burn(_tokenId);
    }

    function setAuxData(uint256 _tokenId, uint96 _auxData) external {
        _setAuxData(_tokenId, _auxData);
    }

    function getAuxData(uint256 _tokenId) external view returns (uint256 auxData) {
        (, auxData) = _getTokenData(_tokenId);
    }
}
