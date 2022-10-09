// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {Multicallable} from "solady/utils/Multicallable.sol";
import {AssetLayer} from "./AssetLayerV0_1.sol";
import {LogicProxy} from "./utils/LogicProxy.sol";
import {RawCallLib} from "./utils/RawCallLib.sol";

/// @author philogy <https://github.com/philogy>
contract LayerFactoryV0_1 is Ownable, Multicallable {
    using RawCallLib for address;

    event AppCreated(address indexed app);

    error CannotReduceExpiry();
    error NotApp();

    mapping(address => uint256) public getAppWatchExpiry;
    mapping(address => bool) public getCreatedHere;

    constructor() Ownable() {}

    /*//////////////////////////////////////////////////////////////
                          MANAGE APPS
    //////////////////////////////////////////////////////////////*/

    function setAppWatchExpiry(address _app, uint256 _newExpiry)
        external
        onlyOwner
    {
        if (_newExpiry <= getAppWatchExpiry[_app]) revert CannotReduceExpiry();
        getAppWatchExpiry[_app] = _newExpiry;
    }

    function callApp(address _app, bytes memory _data) external onlyOwner {
        if (!getCreatedHere[_app]) revert NotApp();
        _app.rawCall(_data);
    }

    /*//////////////////////////////////////////////////////////////
                           CREATE APP
    //////////////////////////////////////////////////////////////*/

    function createApp(address _upgrader, address _implementation) external {
        _registerApp(new AssetLayer(_upgrader, _implementation));
    }

    function createAppAndCall(
        address _upgrader,
        address _implementation,
        bytes memory _logicInitData
    ) external payable {
        AssetLayer assetLayer = new AssetLayer(_upgrader, _implementation);
        address logicModule = address(assetLayer.logicModule());
        logicModule.rawCall(_logicInitData, msg.value);
        _registerApp(assetLayer);
    }

    function _registerApp(AssetLayer _assetLayer) internal {
        address app = address(payable(_assetLayer));
        getCreatedHere[app] = true;
        emit AppCreated(app);
    }
}
