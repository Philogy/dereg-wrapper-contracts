// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

struct TupleMap {
    uint256 _____val;
}

/// @author philogy <https://github.com/philogy>
library TupleMapLib {
    function setVal(
        TupleMap storage _self,
        address _a,
        address _b,
        uint256 _val
    ) internal {
        assembly {
            let freeMem := mload(0x40)
            mstore(0x00, _a)
            mstore(0x20, _b)
            mstore(0x40, _self.slot)
            sstore(keccak256(0x00, 0x60), _val)
            mstore(0x40, freeMem)
        }
    }
}

contract TupleMapTest {
    using TupleMapLib for TupleMap;

    TupleMap internal tokens;

    function set(
        address _a,
        address _b,
        uint256 _val
    ) external {
        tokens.setVal(_a, _b, _val);
    }
}
