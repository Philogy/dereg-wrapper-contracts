// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

/// @author philogy <https://github.com/philogy>
contract LogicProxy {
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address internal immutable assetLayer;

    error InitUnsuccessful();

    constructor(address _assetLayer, address _startImplementation) {
        assetLayer = _assetLayer;
        _setImplementation(_startImplementation);
    }

    fallback() external payable {
        _delegateToImpl();
    }

    function upgradeTo(address _newImpl) external {
        if (msg.sender == assetLayer) _setImplementation(_newImpl);
        else _delegateToImpl();
    }

    function _delegateToImpl() internal {
        // store immutable locally since immutables not supported in assembly
        address assetLayerCached = assetLayer;
        assembly {
            // deposit any ETH directly into asset layer
            if callvalue() {
                pop(
                    call(
                        gas(),
                        assetLayerCached,
                        callvalue(),
                        0x00,
                        0x00,
                        0x00,
                        0x00
                    )
                )
            }
            // forward calldata to implementation
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
