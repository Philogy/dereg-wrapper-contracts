// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {AssetLayer} from "./AssetLayerV0_1.sol";
import {Proxy} from "./utils/Proxy.sol";

/// @author philogy <https://github.com/philogy>
contract LayerFactoryV0_1 is Ownable {
    event AppCreated(address indexed app);

    error CannotReduceExpiry();

    mapping(address => uint256) public getAppWatchExpiry;
    mapping(address => bool) public getCreatedHere;

    constructor() Ownable() {}

    function setAppWatchExpiry(address _app, uint256 _newExpiry)
        external
        onlyOwner
    {
        if (_newExpiry <= getAppWatchExpiry[_app]) revert CannotReduceExpiry();
        getAppWatchExpiry[_app] = _newExpiry;
    }

    function createAppProxyLogic(address _upgrader, address _implementation)
        external
    {
        AssetLayer assetLayer = new AssetLayer(payable(0), address(this));
        Proxy logicModule = new Proxy(
            address(payable(assetLayer)),
            _implementation
        );
        assetLayer.setLogicModule(payable(logicModule));
        assetLayer.setUpgrader(_upgrader);
        _registerApp(assetLayer);
    }

    function createAppProxyLogic(
        address _upgrader,
        address _implementation,
        bytes memory _logicInitData
    ) external payable {
        AssetLayer assetLayer = new AssetLayer(payable(0), address(this));
        Proxy logicModule = new Proxy(
            address(payable(assetLayer)),
            _implementation
        );
        assembly {
            let success := call(
                gas(),
                logicModule,
                callvalue(),
                add(_logicInitData, 0x20),
                mload(_logicInitData),
                0x00,
                0x00
            )

            if iszero(success) {
                returndatacopy(0x00, 0x00, returndatasize())
                revert(0x00, returndatasize())
            }
        }

        assetLayer.setLogicModule(payable(logicModule));
        assetLayer.setUpgrader(_upgrader);
        _registerApp(assetLayer);
    }

    function createAppBasic(address payable _logicModule, address _upgrader)
        external
    {
        _registerApp(new AssetLayer(_logicModule, _upgrader));
    }

    function _registerApp(AssetLayer _assetLayer) internal {
        address app = address(payable(_assetLayer));
        getCreatedHere[app] = true;
        emit AppCreated(app);
    }
}
