//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IERC1155} from "@openzeppelin/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/utils/introspection/IERC165.sol";

abstract contract CrispyERC1155 is IERC1155 {
    error ZeroAddress();
    error InputMismatch();
    error NotApprovedOrOwner();
    error InsufficientBalance();
    error ReceiveCheckFailed();

    mapping(uint256 => bytes32) private packedOwnerAux;
    mapping(address => mapping(address => bool)) private operatorApprovals;

    uint256 internal constant _OWNER_MASK = 0x00ffffffffffffffffffffffffffffffffffffffff;

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 _interfaceId) external view virtual returns (bool) {
        return _interfaceId == type(IERC1155).interfaceId || _interfaceId == type(IERC165).interfaceId;
    }

    function ownerOf(uint256 _tokenId) external view returns (address owner) {
        (owner, ) = _getTokenData(_tokenId);
    }

    /// @dev See {IERC1155-balanceOf}.
    /// Requirements:
    /// - `account` cannot be the zero address.
    function balanceOf(address _account, uint256 _tokenId) public view returns (uint256 bal) {
        if (_account == address(0)) revert ZeroAddress();
        (address owner, ) = _getTokenData(_tokenId);
        assembly {
            bal := eq(owner, _account)
        }
    }

    /// @dev See {IERC1155-balanceOfBatch}.
    /// Requirements:
    /// - `accounts` and `ids` must have the same length.
    function balanceOfBatch(address[] calldata _accounts, uint256[] calldata _tokenIds)
        external
        view
        returns (uint256[] memory)
    {
        uint256 totalAccounts = _accounts.length;
        if (totalAccounts != _tokenIds.length) revert InputMismatch();
        uint256[] memory batchBalances = new uint256[](totalAccounts);

        for (uint256 i; i < totalAccounts; ) {
            batchBalances[i] = balanceOf(_accounts[i], _tokenIds[i]);
            // prettier-ignore
            unchecked { ++i; }
        }

        return batchBalances;
    }

    /**
     * @dev See {IERC1155-setApprovalForAll}.
     */
    function setApprovalForAll(address _operator, bool _approved) external {
        operatorApprovals[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    /**
     * @dev See {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
        return operatorApprovals[_owner][_operator];
    }

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _amount,
        bytes calldata _data
    ) external override {
        if (_to == address(0)) revert ZeroAddress();
        if (_from != msg.sender && !operatorApprovals[_from][msg.sender]) revert NotApprovedOrOwner();
        if (_amount == 0) return;
        (address owner, uint96 auxData) = _getTokenData(_tokenId);
        if (_amount > 1 || _from != owner) revert InsufficientBalance();
        _setTokenData(_tokenId, _to, auxData);
        emit TransferSingle(msg.sender, _from, _to, _tokenId, 1);
        _doSafeTransferAcceptanceCheck(_from, _to, _tokenId, _data);
    }

    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     */
    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _tokenIds,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external override {
        if (_to == address(0)) revert ZeroAddress();
        if (_from != msg.sender && !operatorApprovals[_from][msg.sender]) revert NotApprovedOrOwner();
        uint256 totalTokens = _tokenIds.length;
        if (totalTokens != _amounts.length) revert InputMismatch();

        for (uint256 i; i < totalTokens; ) {
            uint256 amount = _amounts[i];
            uint256 tokenId = _tokenIds[i];
            // prettier-ignore
            unchecked { ++i; }
            if (amount == 0) continue;
            (address owner, uint96 auxData) = _getTokenData(tokenId);
            if (amount > 1 || _from != owner) revert InsufficientBalance();
            _setTokenData(tokenId, _to, auxData);
        }
        emit TransferBatch(msg.sender, _from, _to, _tokenIds, _amounts);
        _doSafeBatchTransferAcceptanceCheck(_from, _to, _tokenIds, _amounts, _data);
    }

    /// @dev Mints single token without recipient check or checking whether the token already exists.
    /// @dev Warning: Will **overwrite** owner if token already exists
    /// @param _tokenId ID of token to be minted
    /// @param _owner Initial token owner
    /// @param _auxData Data to be stored along with owner in slot (96-bits)
    function _uncompliantUnsafeMintSingle(
        uint256 _tokenId,
        address _owner,
        uint96 _auxData
    ) internal {
        _setTokenData(_tokenId, _owner, _auxData);
        emit TransferSingle(msg.sender, address(0), _owner, _tokenId, 1);
    }

    function _burn(uint256 _tokenId) internal returns (address owner, uint96 auxData) {
        (owner, auxData) = _getTokenData(_tokenId);
        delete packedOwnerAux[_tokenId];
        emit TransferSingle(msg.sender, owner, address(0x0), _tokenId, 1);
    }

    function _doSafeTransferAcceptanceCheck(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes calldata _data
    ) private {
        if (_to.code.length != 0) {
            bytes4 receiveAck = IERC1155Receiver(_to).onERC1155Received(msg.sender, _from, _tokenId, 1, _data);
            if (receiveAck != IERC1155Receiver.onERC1155Received.selector) revert ReceiveCheckFailed();
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address _from,
        address _to,
        uint256[] calldata _tokenIds,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) private {
        if (_to.code.length != 0) {
            bytes4 receiveAck = IERC1155Receiver(_to).onERC1155BatchReceived(
                msg.sender,
                _from,
                _tokenIds,
                _amounts,
                _data
            );
            if (receiveAck != IERC1155Receiver.onERC1155BatchReceived.selector) revert ReceiveCheckFailed();
        }
    }

    function _getTokenData(uint256 _tokenId) internal view returns (address owner, uint96 auxData) {
        bytes32 tokenData = packedOwnerAux[_tokenId];
        assembly {
            owner := and(tokenData, _OWNER_MASK)
            auxData := shr(160, tokenData)
        }
    }

    function _setTokenData(
        uint256 _tokenId,
        address _owner,
        uint96 _auxData
    ) internal {
        bytes32 newPackedData;
        assembly {
            newPackedData := or(shl(160, _auxData), _owner)
        }
        packedOwnerAux[_tokenId] = newPackedData;
    }

    function _setAuxData(uint256 _tokenId, uint96 _auxData) internal {
        bytes32 tokenData = packedOwnerAux[_tokenId];
        bytes32 newPackedData;
        assembly {
            newPackedData := or(shl(160, _auxData), and(tokenData, _OWNER_MASK))
        }
        packedOwnerAux[_tokenId] = newPackedData;
    }
}
