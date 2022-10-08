// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {LogicProxy} from "./utils/LogicProxy.sol";

/// @author philogy <https://github.com/philogy>
contract AssetLayer {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    event WithdrawalAdded(
        WithdrawalType indexed wtype,
        address indexed asset,
        address indexed recipient,
        uint256 assetDenominator,
        uint256 settlesAt
    );

    error NotLogicModule();
    error AttemptedReentrancy();
    error TooLargeTotalDelay();
    error AlreadySettled();
    error NotYetSettled();
    error NonexistentWithdrawal();
    error InvalidWithdrawalType();

    enum WithdrawalType {
        None,
        ERC20,
        ERC721
    }

    struct Withdrawal {
        uint64 enqueuedAt;
        uint24 delay;
        WithdrawalType wtype;
        address asset;
        address recipient;
        uint256 assetDenominator; // amount token ID
    }

    uint8 internal constant NO_ENTRY = 1;
    uint8 internal constant SINGLE_ENTRY = 2;

    address public immutable factory;

    mapping(uint256 => Withdrawal) public getWithdrawal;

    uint64 internal nextWithdrawalId;
    uint24 public withdrawDefaultDelay;
    uint8 internal reentryGuard = NO_ENTRY;
    address payable public logicModule;
    uint64 internal delayExtendTime = 1;
    uint24 internal delayExtension = 1;
    uint64 internal frozenAt;
    address public upgrader;

    modifier only(address _authAccount) {
        if (msg.sender != _authAccount) revert NotLogicModule();
        _;
    }

    modifier nonReentrant() {
        if (reentryGuard == SINGLE_ENTRY) revert AttemptedReentrancy();
        reentryGuard = SINGLE_ENTRY;
        _;
        reentryGuard = NO_ENTRY;
    }

    modifier existingWithdrawal(uint256 _withdrawalId) {
        if (
            _withdrawalId >= nextWithdrawalId &&
            getWithdrawal[_withdrawalId].wtype != WithdrawalType.None
        ) revert NonexistentWithdrawal();
        _;
    }

    constructor(address payable _logicModule, address _upgrader) {
        factory = msg.sender;
        logicModule = _logicModule;
        upgrader = _upgrader;
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                          PULL ASSETS
    //////////////////////////////////////////////////////////////*/

    function pullERC20(
        address _collection,
        address _sender,
        uint256 _tokenAmount
    )
        external
        only(logicModule)
        nonReentrant
        returns (uint256 depositedAmount)
    {
        uint256 balBefore = ERC20(_collection).balanceOf(address(this));
        ERC20(_collection).safeTransferFrom(
            _sender,
            address(this),
            _tokenAmount
        );
        depositedAmount =
            ERC20(_collection).balanceOf(address(this)) -
            balBefore;
    }

    function naivePullERC20(
        address _collection,
        address _sender,
        uint256 _tokenAmount
    ) external only(logicModule) nonReentrant {
        ERC20(_collection).safeTransferFrom(
            _sender,
            address(this),
            _tokenAmount
        );
    }

    function pullERC721(
        address _collection,
        address _owner,
        uint256 _tokenId
    ) external only(logicModule) nonReentrant {
        IERC721(_collection).transferFrom(_owner, address(this), _tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                         LOGIC UPGRADES
    //////////////////////////////////////////////////////////////*/

    function setUpgrader(address _newUpgrader) external only(upgrader) {
        upgrader = _newUpgrader;
    }

    function setLogicModule(address _newLogicModule) external only(upgrader) {
        logicModule = payable(_newLogicModule);
    }

    function upgradeAndCallProxyLogic(
        address _newLogicImplementation,
        bool _doPostCall,
        bytes memory _postUpgradeData
    ) external payable only(upgrader) {
        address payable logicModuleCached = logicModule;
        LogicProxy(logicModuleCached).upgradeTo(_newLogicImplementation);
        if (_doPostCall) {
            assembly {
                let success := call(
                    gas(),
                    logicModuleCached,
                    callvalue(),
                    add(_postUpgradeData, 0x20),
                    mload(_postUpgradeData),
                    0x00,
                    0x00
                )
                if iszero(success) {
                    returndatacopy(0x00, 0x00, returndatasize())
                    revert(0x00, returndatasize())
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                     MONITOR ADMIN METHODS
    //////////////////////////////////////////////////////////////*/

    function setDefaultDelay(uint24 _delay) external only(factory) {
        withdrawDefaultDelay = _delay;
    }

    function extendGlobalDelay(uint256 _delayIncrease) external only(factory) {
        uint256 delayExtendTimeCached = delayExtendTime;
        uint256 delayExtensionCached = delayExtension;
        if (delayExtendTimeCached == 0) {
            delayExtendTime = uint64(block.timestamp);
            delayExtension = _delayIncrease.safeCastTo24();
        } else {
            delayExtendTime = Math
                .max(
                    delayExtendTimeCached,
                    block.timestamp - delayExtensionCached
                )
                .safeCastTo64();
            delayExtension = (delayExtensionCached + _delayIncrease)
                .safeCastTo24();
        }
    }

    function resetGlobalDelayIncrease() external only(factory) {
        delayExtendTime = 1;
        delayExtension = 1;
    }

    /*//////////////////////////////////////////////////////////////
                ASSET WITHDRAWAL AND SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    function withdrawERC20(
        address _token,
        address _recipient,
        uint256 _tokens
    ) external only(logicModule) returns (uint256) {
        return
            _addWithdrawal(WithdrawalType.ERC20, _token, _recipient, _tokens);
    }

    function withdrawERC721(
        address _token,
        address _recipient,
        uint256 _tokenId
    ) external only(logicModule) returns (uint256) {
        return
            _addWithdrawal(WithdrawalType.ERC721, _token, _recipient, _tokenId);
    }

    function executeSettlement(uint256 _withdrawalId)
        external
        existingWithdrawal(_withdrawalId)
    {
        if (!settled(_withdrawalId)) revert NotYetSettled();
        WithdrawalType wtype = getWithdrawal[_withdrawalId].wtype;
        address asset = getWithdrawal[_withdrawalId].asset;
        address recipient = getWithdrawal[_withdrawalId].recipient;
        uint256 assetDenominator = getWithdrawal[_withdrawalId]
            .assetDenominator;
        delete getWithdrawal[_withdrawalId];
        if (wtype == WithdrawalType.ERC20) {
            ERC20(asset).safeTransfer(recipient, assetDenominator);
        } else if (wtype == WithdrawalType.ERC721) {
            IERC721(asset).transferFrom(
                address(this),
                recipient,
                assetDenominator
            );
        } else {
            revert InvalidWithdrawalType();
        }
    }

    function settled(uint256 _withdrawalId) public view returns (bool) {
        return _getSettlementTime(_withdrawalId) <= block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                       EMERGENCY ACTIONS
    //////////////////////////////////////////////////////////////*/

    function extendWithdrawal(uint256 _withdrawalId, uint24 _addedDelay)
        external
        only(factory)
        existingWithdrawal(_withdrawalId)
    {
        if (settled(_withdrawalId)) revert AlreadySettled();
        getWithdrawal[_withdrawalId].delay += _addedDelay;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL METHODS
    //////////////////////////////////////////////////////////////*/

    function _addWithdrawal(
        WithdrawalType _wtype,
        address _asset,
        address _recipient,
        uint256 _assetDenominator
    ) internal returns (uint256 withdrawalId) {
        unchecked {
            withdrawalId = nextWithdrawalId++;
            uint256 delay = withdrawDefaultDelay;
            getWithdrawal[withdrawalId] = Withdrawal({
                enqueuedAt: uint64(block.timestamp),
                delay: uint24(delay),
                wtype: _wtype,
                asset: _asset,
                recipient: _recipient,
                assetDenominator: _assetDenominator
            });

            emit WithdrawalAdded(
                _wtype,
                _asset,
                _recipient,
                _assetDenominator,
                block.timestamp + delay
            );
        }
    }

    function _getSettlementTime(uint256 _withdrawalId)
        internal
        view
        returns (uint256)
    {
        uint256 origTime = getWithdrawal[_withdrawalId].enqueuedAt;
        uint256 origDelay = getWithdrawal[_withdrawalId].enqueuedAt;
        return _addDelay(origTime + origDelay, delayExtendTime, delayExtension);
    }

    function _addDelay(
        uint256 _origSettlementTime,
        uint256 _addedTime,
        uint256 _addedDelay
    ) internal pure returns (uint256) {
        if (_addedTime == 1) return _origSettlementTime;
        return
            _origSettlementTime < _addedTime
                ? _origSettlementTime
                : _origSettlementTime + _addedDelay;
    }
}
