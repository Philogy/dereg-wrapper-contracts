// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {Multicallable} from "solady/utils/Multicallable.sol";
import {AssetLayer} from "./AssetLayerV0_1.sol";
import {LogicProxy} from "./utils/LogicProxy.sol";
import {RawCallLib} from "./utils/RawCallLib.sol";

/// @author philogy <https://github.com/philogy>
contract LayerFactory is Ownable, Multicallable {
    using RawCallLib for address;

    event AppCreated(address indexed app);

    error CannotReduceExpiry();
    error NotApp();

    mapping(address => uint256) public getAppWatchExpiry;
    mapping(address => bool) public getCreatedHere;

    uint24 public defaultWithdrawDelay;

    constructor() Ownable() {}

    /*//////////////////////////////////////////////////////////////
                          MANAGE APPS
    //////////////////////////////////////////////////////////////*/

    /*
     * @dev Set when the monitor stops watching the given app.
     * */
    function setAppWatchExpiry(address _app, uint256 _newExpiry)
        external
        onlyOwner
    {
        if (_newExpiry <= getAppWatchExpiry[_app]) revert CannotReduceExpiry();
        getAppWatchExpiry[_app] = _newExpiry;
    }

    /*
     * @dev Set the default withdrawal delay for new apps.
     * */
    function setDefaultAppWithdrawDelay(uint24 _defaultWithdrawDelay)
        external
        onlyOwner
    {
        defaultWithdrawDelay = _defaultWithdrawDelay;
    }

    /*
     * @dev Call app from factory with arbitrary payload.
     * */
    function callApp(address _app, bytes memory _data) external onlyOwner {
        if (!getCreatedHere[_app]) revert NotApp();
        _app.rawCall(_data);
    }

    /*//////////////////////////////////////////////////////////////
                           CREATE APP
    //////////////////////////////////////////////////////////////*/

    /*
     * @dev Create a new circuit breaker wrapped app without doing an
     * initializaiton call.
     * */
    function createApp(address _upgrader, address _implementation) external {
        _registerApp(
            new AssetLayer(_upgrader, _implementation, defaultWithdrawDelay)
        );
    }

    /*
     * @dev Create a new app with an initialization call.
     * */
    function createAppAndCall(
        address _upgrader,
        address _implementation,
        bytes memory _logicInitData
    ) external payable {
        AssetLayer assetLayer = new AssetLayer(
            _upgrader,
            _implementation,
            defaultWithdrawDelay
        );
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
