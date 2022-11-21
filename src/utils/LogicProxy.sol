// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

/// @author philogy <https://github.com/philogy>
contract LogicProxy {
    /// @dev ERC1967 implementation slot: `keccak256("eip1967.proxy.implementation") - 1`
    /// Layout (data after implementation address considered "auxiliary"):
    /// [0  , 159] address implementation
    /// [160, 161] "bit"   assetLayerActive
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    uint256 internal constant _LAYER_ACTIVE_FLAG = 0x010000000000000000000000000000000000000000;
    uint256 internal constant _AUX_ONLY_MASK =
        0xffffffffffffffffffffffff0000000000000000000000000000000000000000;

    address internal immutable assetLayer;

    constructor(address _startImplementation) {
        assetLayer = msg.sender;
        assembly {
            sstore(_IMPLEMENTATION_SLOT, or(_LAYER_ACTIVE_FLAG, _startImplementation))
        }
    }

    /// @dev Reroutes call to implementation if caller not `assetLayer`
    modifier onlyLayerCallable() {
        if (msg.sender != assetLayer) _delegateToImpl();
        _;
    }

    receive() external payable {
        _delegateToImpl();
    }

    fallback() external payable {
        _delegateToImpl();
    }

    /// @dev Sets implementation if caller is `assetLayer`, forwards to
    /// implementation otherwise incase it has its own `upgradeTo` method.
    function upgradeTo(address _newImpl) external payable onlyLayerCallable {
        assembly {
            let currentImplData := sload(_IMPLEMENTATION_SLOT)
            sstore(_IMPLEMENTATION_SLOT, or(and(currentImplData, _AUX_ONLY_MASK), _newImpl))
        }
    }

    function disableAssetLayer() external payable onlyLayerCallable {
        assembly {
            let currentImplData := sload(_IMPLEMENTATION_SLOT)
            sstore(_IMPLEMENTATION_SLOT, and(currentImplData, not(_LAYER_ACTIVE_FLAG)))
        }
    }

    /// @dev Forwards calldata, asset layer address and auxiliary data to the implementation sending any ETH to the `assetLayer`.
    function _delegateToImpl() internal {
        // Store immutable locally since immutables not supported in assembly.
        address assetLayer_ = assetLayer;
        assembly {
            // Deposit any ETH directly into asset layer, `msg.value` is still preserved because of delegate call.
            if callvalue() {
                pop(call(gas(), assetLayer_, callvalue(), 0, 0, 0, 0))
            }
            // Copy calldata to memory.
            calldatacopy(0x00, 0x00, calldatasize())
            // Append asset layer and auxiliary data as an immutable arg.
            let implSlotData := sload(_IMPLEMENTATION_SLOT)
            mstore(calldatasize(), or(and(implSlotData, _AUX_ONLY_MASK), assetLayer_))
            let success := delegatecall(
                gas(),
                implSlotData,
                0x00,
                add(calldatasize(), 0x20),
                0x00,
                0x00
            )
            // Relay return data to caller.
            returndatacopy(0x00, 0x00, returndatasize())
            if success {
                return(0x00, returndatasize())
            }
            revert(0x00, returndatasize())
        }
    }
}
