// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {SafeTransaferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";

/// @author philogy <https://github.com/philogy>
contract AssetLayer {
    using SafeTransferLib for ERC20;

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

    error NotLogicModule();
    error AttemptedReentrancy();

    mapping(uint256 => Withdrawal) public withdrawals;

    uint8 internal constant NO_ENTRY = 1;
    uint8 internal constant SINGLE_ENTRY = 2;

    uint8 internal reentryGuard = NO_ENTRY;
    address public logicModule;
    address public upgrader;
    address public circuitBreaker;

    modifier onlyLogic() {
        if (msg.sender != logicModule) revert NotLogicModule();
        _;
    }

    modifier nonReentrant() {
        if (reentryGuard == SINGLE_ENTRY) revert AttemptedReentrancy();
        reentryGuard = SINGLE_ENTRY;
        _;
        reentryGuard = NO_ENTRY;
    }

    receive() external payable {}

    function pullERC20(
        address _collection,
        address _sender,
        uint256 _tokenAmount
    ) external onlyLogic nonReentrant returns (uint256 depositedAmount) {
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
    ) external onlyLogic nonReentrant {
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
    ) external onlyLogic nonReentrant {
        IERC721(_collection).transferFrom(_owner, address(this), _tokenId);
    }
}
