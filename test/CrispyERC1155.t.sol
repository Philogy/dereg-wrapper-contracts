// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {MockCrispyERC1155} from "./mocks/MockCrispyERC1155.sol";
import {CrispyERC1155} from "../src/CrispyERC1155.sol";
import {IERC1155} from "@openzeppelin/token/ERC1155/IERC1155.sol";
import {IERC165} from "@openzeppelin/utils/introspection/IERC165.sol";

/// @author philogy <https://github.com/philogy>
contract CripsyERC1155Test is Test {
    MockCrispyERC1155 token;

    function setUp() public {
        token = new MockCrispyERC1155();
    }

    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    function testSupportsInterface(bytes4 _interfaceId) public {
        if (_interfaceId == type(IERC165).interfaceId || _interfaceId == type(IERC1155).interfaceId) {
            assertTrue(token.supportsInterface(_interfaceId));
        } else {
            assertFalse(token.supportsInterface(_interfaceId));
        }
    }

    function testDefaultOwnerZero(uint256 _tokenId) public {
        assertEq(token.ownerOf(_tokenId), address(0));
    }

    function testDefaultBalanceZero(address _account, uint256 _tokenId) public {
        if (_account == address(0)) {
            vm.expectRevert(CrispyERC1155.ZeroAddress.selector);
            token.balanceOf(_account, _tokenId);
        } else {
            assertEq(token.balanceOf(_account, _tokenId), 0);
        }
    }

    function testDefaultApprovalFalse(address _owner, address _operator) public {
        assertFalse(token.isApprovedForAll(_owner, _operator));
    }

    function testApproval(address _owner, address _operator) public {
        vm.assume(_owner != _operator);

        vm.expectEmit(true, true, true, true);
        emit ApprovalForAll(_owner, _operator, true);
        vm.prank(_owner);
        token.setApprovalForAll(_operator, true);
        assertTrue(token.isApprovedForAll(_owner, _operator));
        assertFalse(token.isApprovedForAll(_operator, _owner));

        vm.expectEmit(true, true, true, true);
        emit ApprovalForAll(_owner, _operator, false);
        vm.prank(_owner);
        token.setApprovalForAll(_operator, false);
        assertFalse(token.isApprovedForAll(_owner, _operator));
        assertFalse(token.isApprovedForAll(_operator, _owner));
    }

    function testMintCreatesBalance(
        address _recipient,
        uint256 _tokenId,
        uint96 _auxData
    ) public {
        vm.assume(_recipient != address(0));

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(this), address(0), _recipient, _tokenId, 1);
        token.mint(_tokenId, _recipient, _auxData);

        assertEq(token.getAuxData(_tokenId), _auxData, "aux data mismatch");
        assertEq(token.ownerOf(_tokenId), _recipient, "invalid owner");
        assertEq(token.balanceOf(_recipient, _tokenId), 1, "invalid balance");
    }

    function testDirectTransfers(
        uint256 _tokenId,
        address _from,
        address _to,
        uint96 _auxData
    ) public {
        vm.assume(_to != address(0));
        vm.assume(_from != address(0));
        vm.assume(_to != _from);
        vm.assume(_to.code.length == 0);
        token.mint(_tokenId, _from, _auxData);

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(_from, _from, _to, _tokenId, 1);
        vm.prank(_from);
        token.safeTransferFrom(_from, _to, _tokenId, 1, "");

        assertEq(token.ownerOf(_tokenId), _to);
        assertEq(token.getAuxData(_tokenId), _auxData);
        assertEq(token.balanceOf(_to, _tokenId), 1);
        assertEq(token.balanceOf(_from, _tokenId), 0);
    }

    function testOperatorTransfer(
        uint256 _tokenId,
        address _from,
        address _operator,
        address _to,
        uint96 _auxData
    ) public {
        vm.assume(_to != address(0) && _from != address(0) && _operator != address(0));
        vm.assume(_to != _from && _to != _operator && _operator != _from);
        vm.assume(_to.code.length == 0);
        token.mint(_tokenId, _from, _auxData);
        vm.prank(_from);
        token.setApprovalForAll(_operator, true);

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(_operator, _from, _to, _tokenId, 1);
        vm.prank(_operator);
        token.safeTransferFrom(_from, _to, _tokenId, 1, "");

        assertEq(token.ownerOf(_tokenId), _to);
        assertEq(token.getAuxData(_tokenId), _auxData);
        assertEq(token.balanceOf(_to, _tokenId), 1, "rand balance");
        assertEq(token.balanceOf(_from, _tokenId), 0);
        assertEq(token.balanceOf(_operator, _tokenId), 0);
    }

    function testUnauthorizedTransfer(
        uint256 _tokenId,
        address _from,
        address _unauthorized,
        address _to,
        uint96 _auxData
    ) public {
        vm.assume(_to != address(0) && _from != address(0) && _unauthorized != address(0));
        vm.assume(_to != _from && _to != _unauthorized && _unauthorized != _from);
        vm.assume(_to.code.length == 0);
        token.mint(_tokenId, _from, _auxData);

        vm.expectRevert(CrispyERC1155.NotApprovedOrOwner.selector);
        vm.prank(_unauthorized);
        token.safeTransferFrom(_from, _to, _tokenId, 1, "");
    }

    function testBatchBalance() public {
        address account1 = vm.addr(0xabc001);
        address account2 = vm.addr(0xabc002);
        assertTrue(account1 != account2);

        uint256 size = 10;
        address[] memory accounts = new address[](size);
        address[] memory accounts1 = new address[](size);
        address[] memory accounts2 = new address[](size);
        uint256[] memory tokenIds = new uint256[](size);

        uint256 seed = 0xbbbb;
        for (uint256 i; i < size; i++) {
            uint256 rand = uint256(keccak256(abi.encode(seed, i)));
            address account = rand % 2 == 0 ? account1 : account2;
            accounts[i] = account;
            uint256 tokenId = uint256(keccak256(abi.encode(rand)));
            tokenIds[i] = tokenId;
            token.mint(tokenId, account, 0);

            accounts1[i] = account1;
            accounts2[i] = account2;
        }

        uint256[] memory balances = token.balanceOfBatch(accounts, tokenIds);
        uint256[] memory balances1 = token.balanceOfBatch(accounts1, tokenIds);
        uint256[] memory balances2 = token.balanceOfBatch(accounts2, tokenIds);
        for (uint256 i; i < size; i++) {
            assertEq(balances[i], 1);
            assertEq(balances1[i], accounts[i] == account1 ? 1 : 0);
            assertEq(balances2[i], accounts[i] == account2 ? 1 : 0);
        }
    }

    function testBatchTransfer() public {}
}
