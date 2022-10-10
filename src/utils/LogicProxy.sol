// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

/// @author philogy <https://github.com/philogy>
contract LogicProxy {
    // `keccak256("eip1967.proxy.implementation") - 1`
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public immutable getAssetLayer;

    constructor(address _startImplementation) {
        getAssetLayer = msg.sender;
        _setImplementation(_startImplementation);
    }

    fallback() external payable {
        _delegateToImpl();
    }

    /*
     * @dev Sets implementation if caller is `assetLayer`, forwards to
     * implementation otherwise incase it has its own `upgradeTo` method.
     * */
    function upgradeTo(address _newImpl) external payable {
        if (msg.sender == getAssetLayer) _setImplementation(_newImpl);
        else _delegateToImpl();
    }

    /*
     * @dev Forwards calldata to implementation sending any ETH to the
     * `assetLayer`.
     * */
    function _delegateToImpl() internal {
        // store immutable locally since immutables not supported in assembly
        address assetLayer = getAssetLayer;
        assembly {
            // deposit any ETH directly into asset layer
            if callvalue() {
                pop(call(gas(), assetLayer, callvalue(), 0, 0, 0, 0))
            }
            // forward calldata to implementation
            calldatacopy(0x00, 0x00, calldatasize())
            let success := delegatecall(
                gas(),
                sload(_IMPLEMENTATION_SLOT),
                0x00,
                calldatasize(),
                0,
                0
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
