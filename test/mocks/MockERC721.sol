// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {ERC721} from "solmate/tokens/ERC721.sol";

/// @author philogy <https://github.com/philogy>
contract MockERC721 is ERC721("Mock NFT", "MCKNFT") {
    uint256 public totalSupply;

    function mint(address _recipient) external {
        _mint(_recipient, totalSupply++);
    }

    function tokenURI(uint256) public view override returns (string memory) {
        return "";
    }
}
