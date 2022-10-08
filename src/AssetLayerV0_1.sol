// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {Proxy} from "./utils/Proxy.sol";

/// @author philogy <https://github.com/philogy>
contract AssetLayer {
    using SafeTransferLib for ERC20;

    event WithdrawalAdded(
        WithdrawalType indexed wtype,
        address indexed asset,
        address indexed recipient,
        uint256 assetDenominator,
        uint256 settlesAt
    );

    error NotLogicModule();
    error AttemptedReentrancy();

    enum WithdrawalType {
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

    mapping(uint256 => Withdrawal) public withdrawals;

    uint64 internal nextWithdrawalId;
    uint24 public withdrawDefaultDelay;
    uint8 internal reentryGuard = NO_ENTRY;
    address payable public logicModule;
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

    function setLogicModule(address payable _newLogicModule)
        external
        only(upgrader)
    {
        logicModule = _newLogicModule;
    }

    function upgradeAndCallProxyLogic(
        address _newLogicImplementation,
        bool _doPostCall,
        bytes memory _postUpgradeData
    ) external payable only(upgrader) {
        address payable logicModuleCached = logicModule;
        Proxy(logicModuleCached).upgradeTo(_newLogicImplementation);
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

    /*//////////////////////////////////////////////////////////////
                       EMERGENCY ACTIONS
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
            withdrawals[withdrawalId] = Withdrawal({
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
}
