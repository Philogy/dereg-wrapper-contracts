// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @author philogy <https://github.com/philogy>
contract MockERC20 is ERC20("Mock Token", "MCK", 18) {
    function mint(address _recipient, uint256 _amount) external {
        _mint(_recipient, _amount);
    }
}
