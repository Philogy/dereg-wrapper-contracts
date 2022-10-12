// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";
import {Multicallable} from "solady/utils/Multicallable.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {LogicProxy} from "./utils/LogicProxy.sol";
import {RawCallLib} from "./utils/RawCallLib.sol";
import {IAssetLayerV0_1} from "./IAssetLayerV0_1.sol";

/// @author philogy <https://github.com/philogy>
contract AssetLayer is IAssetLayerV0_1, Multicallable {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;
    using MerkleProofLib for bytes32[];
    using RawCallLib for address;

    event WithdrawalAdded(
        uint256 indexed withdrawalId,
        bytes21 indexed assetId,
        address indexed recipient,
        uint256 assetDenominator,
        uint256 settlesAt
    );
    event WithdrawDelayExtended(
        uint256 indexed withdrawalId,
        uint256 addedDelay,
        uint256 settlesAt
    );

    error UnauthorizedCaller();
    error AttemptedReentrancy();
    error TooLargeTotalDelay();
    error AlreadySettled();
    error NotYetSettled();
    error UnknownSettlementStatus();
    error NonexistentWithdrawal();
    error InvalidAssetType();
    error Frozen();
    error NotFrozen();

    enum AssetType {
        None,
        ERC20,
        ERC721,
        NATIVE
    }

    struct Withdrawal {
        uint64 enqueuedAt;
        uint24 delay;
        AssetType atype;
        address asset;
        address recipient;
        uint256 assetDenominator; // amount token ID
    }

    struct Freeze {
        uint64 lastEnd;
        uint64 start;
        uint64 globalDelayExtendTime;
        uint24 globalDelayExtension;
        bytes32 validWithdrawalsRoot;
    }

    address public immutable factory;

    mapping(uint256 => Withdrawal) internal withdrawals;
    mapping(uint256 => Freeze) public getFreeze;

    uint8 internal constant NO_ENTRY = 1;
    uint8 internal constant SINGLE_ENTRY = 2;

    uint8 internal reentryGuard = NO_ENTRY;
    uint64 public nextWithdrawalId;
    uint24 public withdrawDefaultDelay;
    address payable public logicModule;

    uint64 internal delayExtendTime = 1;
    uint24 internal delayExtension = 1;
    uint64 internal lastFreeze;
    uint64 internal nextFreezeId;
    bool internal isFrozen;

    address public upgrader;

    modifier only(address _authAccount) {
        if (msg.sender != _authAccount) revert UnauthorizedCaller();
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
            _withdrawalId >= nextWithdrawalId ||
            withdrawals[_withdrawalId].atype == AssetType.None
        ) revert NonexistentWithdrawal();
        _;
    }

    modifier whileNotFrozen() {
        if (isFrozen) revert Frozen();
        _;
    }

    constructor(
        address _upgrader,
        address _initialLogicImpl,
        uint24 _withdrawDefaultDelay
    ) {
        factory = msg.sender;
        upgrader = _upgrader;
        logicModule = payable(new LogicProxy(_initialLogicImpl));
        withdrawDefaultDelay = _withdrawDefaultDelay;
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                          PULL ASSETS
    //////////////////////////////////////////////////////////////*/

    function pullERC20(
        address _token,
        address _sender,
        uint256 _tokenAmount
    )
        external
        only(logicModule)
        nonReentrant
        returns (uint256 depositedAmount)
    {
        uint256 balBefore = ERC20(_token).balanceOf(address(this));
        ERC20(_token).safeTransferFrom(_sender, address(this), _tokenAmount);
        depositedAmount = ERC20(_token).balanceOf(address(this)) - balBefore;
    }

    function naivePullERC20(
        address _token,
        address _sender,
        uint256 _tokenAmount
    ) external only(logicModule) nonReentrant {
        ERC20(_token).safeTransferFrom(_sender, address(this), _tokenAmount);
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
        if (_doPostCall)
            address(logicModuleCached).rawCall(_postUpgradeData, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                     MONITOR ADMIN METHODS
    //////////////////////////////////////////////////////////////*/

    function setDefaultDelay(uint24 _delay) external only(factory) {
        withdrawDefaultDelay = _delay;
    }

    function resetGlobalDelayIncrease() external only(factory) {
        delayExtendTime = 1;
        delayExtension = 1;
    }

    /*//////////////////////////////////////////////////////////////
                        ASSET WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    function withdrawERC20(
        address _token,
        address _recipient,
        uint256 _amount
    ) external only(logicModule) {
        _addWithdrawal(AssetType.ERC20, _token, _recipient, _amount);
    }

    function withdrawERC721(
        address _token,
        address _recipient,
        uint256 _tokenId
    ) external only(logicModule) {
        _addWithdrawal(AssetType.ERC721, _token, _recipient, _tokenId);
    }

    function withdrawNative(address _recipient, uint256 _amount)
        external
        only(logicModule)
    {
        _addWithdrawal(AssetType.NATIVE, address(0), _recipient, _amount);
    }

    function getWithdrawal(uint256 _withdrawalId)
        external
        view
        returns (Withdrawal memory)
    {
        return withdrawals[_withdrawalId];
    }

    function getAssetId(AssetType _atype, address _asset)
        public
        pure
        returns (bytes21 assetId)
    {
        assembly {
            mstore(0x00, _asset)
            mstore8(0x0b, _atype)
            mstore(0x20, 0x00)
            assetId := mload(0x0b)
        }
    }

    /*//////////////////////////////////////////////////////////////
                           SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    function executeDirectSettlement(uint256 _withdrawalId)
        external
        existingWithdrawal(_withdrawalId)
    {
        if (!settled(_withdrawalId)) revert NotYetSettled();
        _executeSettlement(_withdrawalId);
    }

    function executePreFreezeSettlement(
        uint256 _withdrawalId,
        uint256 _freezeId
    ) external existingWithdrawal(_withdrawalId) {
        (uint256 origTime, uint256 settlementTime) = _getSettlementTime(
            _withdrawalId
        );
        uint256 lastEnd = getFreeze[_freezeId].lastEnd;
        uint256 start = getFreeze[_freezeId].start;
        if (origTime < lastEnd || start < settlementTime)
            revert UnknownSettlementStatus();
        _executeSettlement(_withdrawalId);
    }

    function executeValidWithdrawalSettlement(
        uint256 _withdrawalId,
        uint256 _freezeId,
        bytes32[] calldata _proof
    ) external existingWithdrawal(_withdrawalId) {
        if (
            !_proof.verify(
                getFreeze[_freezeId].validWithdrawalsRoot,
                bytes32(_withdrawalId)
            )
        ) revert UnknownSettlementStatus();
        _executeSettlement(_withdrawalId);
    }

    function settled(uint256 _withdrawalId) public view returns (bool) {
        (uint256 origTime, uint256 settlementTime) = _getSettlementTime(
            _withdrawalId
        );
        if (origTime < lastFreeze) revert UnknownSettlementStatus();
        return settlementTime <= block.timestamp;
    }

    function getSettlementTime(uint256 _withdrawalId)
        public
        view
        returns (uint256 settlementTime)
    {
        (, settlementTime) = _getSettlementTime(_withdrawalId);
    }

    /*//////////////////////////////////////////////////////////////
                       EMERGENCY ACTIONS
    //////////////////////////////////////////////////////////////*/

    function extendWithdrawalDelay(uint256 _withdrawalId, uint24 _addedDelay)
        external
        only(factory)
        existingWithdrawal(_withdrawalId)
    {
        if (settled(_withdrawalId)) revert AlreadySettled();
        withdrawals[_withdrawalId].delay += _addedDelay;
        (, uint256 newSettlementTime) = _getSettlementTime(_withdrawalId);
        emit WithdrawDelayExtended(
            _withdrawalId,
            _addedDelay,
            newSettlementTime
        );
    }

    function extendGlobalDelay(uint256 _delayIncrease) external only(factory) {
        uint256 delayExtendTimeCached = delayExtendTime;
        uint256 delayExtensionCached = delayExtension;
        if (delayExtendTimeCached == 1) {
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

    function getGlobalDelayExtend() public view returns (uint256, uint256) {
        uint256 delayExtendTimeCached = delayExtendTime;
        uint256 delayExtensionCached = delayExtension;
        return
            delayExtendTimeCached == 1
                ? (0, 0)
                : (delayExtendTimeCached, delayExtensionCached);
    }

    function freeze() external only(factory) whileNotFrozen {
        lastFreeze = uint64(block.timestamp);
        uint256 freezeId = nextFreezeId;
        isFrozen = true;
        getFreeze[freezeId].start = uint64(block.timestamp);
        getFreeze[freezeId].globalDelayExtendTime = delayExtendTime;
        getFreeze[freezeId].globalDelayExtension = delayExtension;
    }

    function unfreeze(bytes32 _validWithdrawalsRoot) external only(factory) {
        if (!isFrozen) revert NotFrozen();
        isFrozen = false;
        uint256 currentFreezeId = nextFreezeId;
        getFreeze[currentFreezeId].validWithdrawalsRoot = _validWithdrawalsRoot;
        unchecked {
            getFreeze[nextFreezeId = uint64(++currentFreezeId)]
                .lastEnd = uint64(block.timestamp);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL METHODS
    //////////////////////////////////////////////////////////////*/

    function _addWithdrawal(
        AssetType _atype,
        address _asset,
        address _recipient,
        uint256 _assetDenominator
    ) internal whileNotFrozen {
        unchecked {
            uint256 withdrawalId = nextWithdrawalId++;
            uint256 delay = withdrawDefaultDelay;
            withdrawals[withdrawalId] = Withdrawal({
                enqueuedAt: uint64(block.timestamp),
                delay: uint24(delay),
                atype: _atype,
                asset: _asset,
                recipient: _recipient,
                assetDenominator: _assetDenominator
            });

            emit WithdrawalAdded(
                withdrawalId,
                getAssetId(_atype, _asset),
                _recipient,
                _assetDenominator,
                _addDelay(
                    block.timestamp + delay,
                    delayExtendTime,
                    delayExtension
                )
            );
        }
    }

    function _executeSettlement(uint256 _withdrawalId) internal nonReentrant {
        AssetType atype = withdrawals[_withdrawalId].atype;
        address asset = withdrawals[_withdrawalId].asset;
        address recipient = withdrawals[_withdrawalId].recipient;
        uint256 assetDenominator = withdrawals[_withdrawalId].assetDenominator;
        delete withdrawals[_withdrawalId];
        if (atype == AssetType.ERC20) {
            ERC20(asset).safeTransfer(recipient, assetDenominator);
        } else if (atype == AssetType.ERC721) {
            IERC721(asset).transferFrom(
                address(this),
                recipient,
                assetDenominator
            );
        } else if (atype == AssetType.NATIVE) {
            SafeTransferLib.safeTransferETH(recipient, assetDenominator);
        } else {
            revert InvalidAssetType();
        }
    }

    function _getSettlementTime(uint256 _withdrawalId)
        internal
        view
        returns (uint256 origTime, uint256 settlementTime)
    {
        origTime = withdrawals[_withdrawalId].enqueuedAt;
        uint256 origDelay = withdrawals[_withdrawalId].delay;
        settlementTime = _addDelay(
            origTime + origDelay,
            delayExtendTime,
            delayExtension
        );
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
