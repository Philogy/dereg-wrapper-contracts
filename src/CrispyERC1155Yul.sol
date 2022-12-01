//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IERC1155} from "@openzeppelin/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/token/ERC1155/IERC1155Receiver.sol";

/// TODO: Complete, not production ready
abstract contract CrispyERC1155 is IERC1155 {
    error NotApprovedOrOwner();
    error InsufficientBalance();

    type DirectMapping is bytes32;
    DirectMapping private _tokens;
    type TupleMapping is bytes32;
    TupleMapping private _operatorApprovals;

    uint256 private constant __PROTECTED_STORAGE_RANGE = 1e3;
    uint256 private constant _ADDRESS_MASK = 0x00ffffffffffffffffffffffffffffffffffffffff;

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 _interfaceId) public pure virtual override returns (bool sups) {
        assembly {
            sups := or(
                eq(_interfaceId, 0xd9b67a2600000000000000000000000000000000000000000000000000000000),
                eq(_interfaceId, 0x01ffc9a700000000000000000000000000000000000000000000000000000000)
            )
        }
    }

    /**
     * @dev See {IERC1155-balanceOf}.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address _owner, uint256 _tokenId) external view returns (uint256) {
        assembly {
            let tokenOwner := and(sload(_tokenId), _ADDRESS_MASK)
            mstore(shl(iszero(_owner), 0xff), 0x20)
            return(0x00, 0x20)
        }
    }

    /**
     * @dev See {IERC1155-balanceOfBatch}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(address[] calldata _owners, uint256[] calldata _tokenIds)
        external
        view
        returns (uint256[] memory)
    {
        assembly {
            let ownersOffset := _owners.offset
            let idsOffset := _tokenIds.offset
            let totalOwners := calldataload(ownersOffset)
            mstore(sub(eq(totalOwners, calldataload(idsOffset)), 1), 0x20)
            mstore(0x20, totalOwners)
            let retOffset := 0x20
            let totalRelativeOffset := shl(5, totalOwners)
            // prettier-ignore
            for { let i := totalRelativeOffset } i { i := sub(i, 0x20) } {
                let tokenId := calldataload(add(idsOffset, i))
                let compOwner := calldataload(add(ownersOffset, i))
                let tokenOwner := and(sload(tokenId), _ADDRESS_MASK)
                mstore(add(retOffset, i), and(eq(compOwner, tokenOwner), gt(tokenId, __PROTECTED_STORAGE_RANGE)))
            }
            return(0x00, add(0x40, totalRelativeOffset))
        }
    }

    /**
     * @dev See {IERC1155-setApprovalForAll}.
     */
    function setApprovalForAll(address _operator, bool _approved) external {
        assembly {
            let freeMem := mload(0x40)
            mstore(0x00, caller())
            mstore(0x20, _operator)
            mstore(0x40, _operatorApprovals.slot)
            let approvalSlot := keccak256(0x00, 0x60)
            mstore(0x40, freeMem)
            sstore(approvalSlot, _approved)
        }
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    /**
     * @dev See {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(address, address) external view returns (bool approved) {
        assembly {
            calldatacopy(0x00, 0x04, 0x40)
            mstore(0x40, _operatorApprovals.slot)
            approved := sload(keccak256(0x00, 0x60))
            mstore(0x00, approved)
            return(0x00, 0x20)
        }
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
    ) external {
        assembly {
            mstore(shl(iszero(_to), 0xff), 1)
            if sub(_from, caller()) {
                mstore(0x00, _from)
                mstore(0x20, caller())
                mstore(0x40, _operatorApprovals.slot)
                if iszero(sload(keccak256(0x00, 0x60))) {
                    mstore(0x00, 0xe433766c)
                    revert(0x1c, 0x04)
                }
            }
            let ownerData := sload(_tokenId)
            mstore(0x00, 0xf4d678b8)
        }
    }

    // /**
    //  * @dev See {IERC1155-safeBatchTransferFrom}.
    //  */
    // function safeBatchTransferFrom(
    //     address _from,
    //     address _to,
    //     uint256[] memory ids,
    //     uint256[] memory amounts,
    //     bytes memory data
    // ) public virtual override {
    //     require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");
    //     assembly {
    //         mstore(shl(iszero(_to), 0xff), 1)
    //         if sub(_from, caller()) {
    //             mstore(0x00, _from)
    //             mstore(0x20, caller())
    //             mstore(0x40, _operatorApprovals.slot)
    //             if iszero(sload(keccak256(0x00, 0x60))) {
    //                 revert(0x00, 0x00)
    //             }
    //         }
    //     }

    //     for (uint256 i = 0; i < ids.length; ++i) {
    //         uint256 id = ids[i];
    //         uint256 amount = amounts[i];

    //         (address oldOwner, uint32 fuses, uint64 expiry) = getData(id);

    //         require(amount == 1 && oldOwner == _from, "ERC1155: insufficient balance for transfer");
    //         _setData(id, _to, fuses, expiry);
    //     }

    //     emit TransferBatch(msg.sender, _from, _to, ids, amounts);

    //     _doSafeBatchTransferAcceptanceCheck(msg.sender, _from, _to, ids, amounts, data);
    // }

    // /**************************************************************************
    //  * Internal/private methods
    //  *************************************************************************/

    // /**
    //  * @dev Sets the Name's owner address and fuses
    //  */

    // function _mint(
    //     bytes32 node,
    //     address owner,
    //     uint32 fuses,
    //     uint64 expiry
    // ) internal virtual {
    //     uint256 tokenId = uint256(node);
    //     address oldOwner;
    //     uint32 oldFuses;
    //     uint64 oldExpiry;

    //     uint32 parentControlledFuses = (uint32(type(uint16).max) << 16) & oldFuses;

    //     if (oldExpiry > expiry) {
    //         expiry = oldExpiry;
    //     }

    //     if (oldExpiry >= block.timestamp) {
    //         fuses = fuses | parentControlledFuses;
    //     }

    //     require(oldOwner == address(0), "ERC1155: mint of existing token");
    //     require(owner != address(0), "ERC1155: mint to the zero address");
    //     require(owner != address(this), "ERC1155: newOwner cannot be the NameWrapper contract");

    //     _setData(tokenId, owner, fuses, expiry);
    //     emit TransferSingle(msg.sender, address(0x0), owner, tokenId, 1);
    //     _doSafeTransferAcceptanceCheck(msg.sender, address(0), owner, tokenId, 1, "");
    // }

    // function _burn(uint256 tokenId) internal virtual {
    //     (address owner, uint32 fuses, uint64 expiry) = getData(tokenId);
    //     // Fuses and expiry are kept on burn
    //     _setData(tokenId, address(0x0), fuses, expiry);
    //     emit TransferSingle(msg.sender, owner, address(0x0), tokenId, 1);
    // }

    // function _transfer(
    //     address from,
    //     address to,
    //     uint256 id,
    //     uint256 amount,
    //     bytes memory data
    // ) internal {
    //     (address oldOwner, uint32 fuses, uint64 expiry) = getData(id);

    //     require(amount == 1 && oldOwner == from, "ERC1155: insufficient balance for transfer");

    //     if (oldOwner == to) {
    //         return;
    //     }

    //     _setData(id, to, fuses, expiry);

    //     emit TransferSingle(msg.sender, from, to, id, amount);

    //     _doSafeTransferAcceptanceCheck(msg.sender, from, to, id, amount, data);
    // }

    // function _doSafeTransferAcceptanceCheck(
    //     address operator,
    //     address from,
    //     address to,
    //     uint256 id,
    //     uint256 amount,
    //     bytes memory data
    // ) private {
    //     if (to.code.length != 0) {
    //         try IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data) returns (bytes4 response) {
    //             if (response != IERC1155Receiver(to).onERC1155Received.selector) {
    //                 revert("ERC1155: ERC1155Receiver rejected tokens");
    //             }
    //         } catch Error(string memory reason) {
    //             revert(reason);
    //         } catch {
    //             revert("ERC1155: transfer to non ERC1155Receiver implementer");
    //         }
    //     }
    // }

    // function _doSafeBatchTransferAcceptanceCheck(
    //     address operator,
    //     address from,
    //     address to,
    //     uint256[] memory ids,
    //     uint256[] memory amounts,
    //     bytes memory data
    // ) private {
    //     if (to.code.length != 0) {
    //         try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data) returns (
    //             bytes4 response
    //         ) {
    //             if (response != IERC1155Receiver(to).onERC1155BatchReceived.selector) {
    //                 revert("ERC1155: ERC1155Receiver rejected tokens");
    //             }
    //         } catch Error(string memory reason) {
    //             revert(reason);
    //         } catch {
    //             revert("ERC1155: transfer to non ERC1155Receiver implementer");
    //         }
    //     }
    // }
}
