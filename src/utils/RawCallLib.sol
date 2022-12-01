// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

/// @author philogy <https://github.com/philogy>
library RawCallLib {
    function rawCall(address _addr, bytes memory _data) internal {
        rawCall(_addr, _data, 0);
    }

    function rawCall(
        address _addr,
        bytes memory _data,
        uint256 _value
    ) internal {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let success := call(gas(), _addr, _value, add(_data, 0x20), mload(_data), 0, 0)
            if iszero(success) {
                returndatacopy(0x00, 0x00, returndatasize())
                revert(0x00, returndatasize())
            }
        }
    }
}
