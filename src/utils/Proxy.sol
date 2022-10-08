// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

/// @author philogy <https://github.com/philogy>
contract Proxy {
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address internal immutable admin;

    error InitUnsuccessful();

    constructor(address _admin, address _startImplementation) {
        admin = _admin;
        _setImplementation(_startImplementation);
    }

    fallback() external payable {
        _delegateToImpl();
    }

    function upgradeTo(address _newImpl) external {
        if (msg.sender == admin) _setImplementation(_newImpl);
        else _delegateToImpl();
    }

    function _delegateToImpl() internal {
        assembly {
            calldatacopy(0x00, 0x00, calldatasize())
            let success := delegatecall(
                gas(),
                sload(_IMPLEMENTATION_SLOT),
                0x00,
                calldatasize(),
                0x00,
                0x00
            )
            returndatacopy(0x00, 0x00, returndatasize())
            if success {
                return(0x00, returndatasize())
            }
            revert(0x00, returndatasize())
        }
    }

    function _setImplementation(address _impl) internal {
        assembly {
            sstore(_IMPLEMENTATION_SLOT, _impl)
        }
    }
}
