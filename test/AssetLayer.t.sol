// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {AssetLayer} from "../src/AssetLayerV0_1.sol";
import {DeRegDEX} from "../src/examples/DeRegDEX.sol";
import {VulnerableDeRegDEX} from "../src/examples/VulnerableDeRegDEX.sol";
import {MockApp} from "./mocks/MockApp.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @author philogy <https://github.com/philogy>
contract AssetLayerV0_1Test is Test {
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

    address factory = vm.addr(0xfac10111);
    address upgrader = vm.addr(0xaa11aa);

    address vulnerableDex;
    address dex;
    address mockApp;

    address[] users;

    uint256 defaultDelay = 3 hours;

    function setUp() public {
        vulnerableDex = address(new VulnerableDeRegDEX());
        dex = address(new DeRegDEX());
        mockApp = address(new MockApp());

        users = new address[](10);
        for (uint256 i = 0; i < 10; i++) users[i] = vm.addr(i + 1);
    }

    function testAcceptsAndRedirectsETH() public {
        (MockApp app, AssetLayer assetLayer) = getMockApp();

        assertEq(assetLayer.factory(), factory);

        vm.deal(users[0], 10 ether);

        vm.prank(users[0]);
        app.depositETH{value: 1 ether}();
        assertEq(address(app).balance, 0);
        assertEq(address(assetLayer).balance, 1 ether);

        vm.prank(users[0]);
        (bool success, ) = address(assetLayer).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(app).balance, 0);
        assertEq(address(assetLayer).balance, 2 ether);
    }

    function testPullERC20() public {
        (, AssetLayer assetLayer) = getMockApp();
        MockERC20 token = new MockERC20();
        token.mint(users[0], 100e18);

        vm.prank(users[0]);
        token.approve(address(assetLayer), type(uint256).max);

        vm.expectRevert(AssetLayer.UnauthorizedCaller.selector);
        assetLayer.pullERC20(address(token), users[0], 1e18);

        vm.expectRevert(AssetLayer.UnauthorizedCaller.selector);
        assetLayer.naivePullERC20(address(token), users[0], 1e18);
    }

    function testCannotSettleNonexistent() public {
        (, AssetLayer assetLayer) = getMockApp();
        vm.expectRevert(AssetLayer.NonexistentWithdrawal.selector);
        assetLayer.executeDirectSettlement(0xffff);
    }

    function testBasicSettlement() public {
        (MockApp app, AssetLayer assetLayer) = getMockApp();
        MockERC20 token = new MockERC20();
        token.mint(address(assetLayer), 100e18);

        uint256 withdrawAmount = 15e18;
        vm.expectEmit(true, true, true, true);
        uint256 nextId = assetLayer.nextWithdrawalId();

        emit WithdrawalAdded(
            nextId,
            bytes21(
                abi.encodePacked(AssetLayer.AssetType.ERC20, address(token))
            ),
            users[0],
            withdrawAmount,
            block.timestamp + defaultDelay
        );
        app.withdrawERC20(address(token), users[0], withdrawAmount);
        AssetLayer.Withdrawal memory withdrawal = assetLayer.getWithdrawal(
            nextId
        );
        assertEq(withdrawal.enqueuedAt, block.timestamp);
        assertEq(withdrawal.delay, defaultDelay);
        assertTrue(withdrawal.atype == AssetLayer.AssetType.ERC20);
        assertEq(withdrawal.asset, address(token));
        assertEq(withdrawal.recipient, users[0]);
        assertEq(withdrawal.assetDenominator, withdrawAmount);
        assertEq(assetLayer.settled(nextId), false);

        vm.warp(uint256(withdrawal.enqueuedAt) + uint256(withdrawal.delay) / 2);
        vm.expectRevert(AssetLayer.NotYetSettled.selector);
        assetLayer.executeDirectSettlement(nextId);

        vm.warp(uint256(withdrawal.enqueuedAt) + uint256(withdrawal.delay));
        assertEq(assetLayer.settled(nextId), true);
        vm.prank(users[1]);
        uint256 balBefore = token.balanceOf(users[0]);
        assetLayer.executeDirectSettlement(nextId);
        uint256 balAfter = token.balanceOf(users[0]);
        assertEq(balAfter - balBefore, withdrawAmount);
    }

    function testCreateAssetId(uint8 _atype, address _asset) public {
        vm.assume(_atype <= uint8(type(AssetLayer.AssetType).max));
        AssetLayer.AssetType atype = AssetLayer.AssetType(_atype);
        (, AssetLayer assetLayer) = getMockApp();
        assertEq(
            bytes21(abi.encodePacked(atype, _asset)),
            assetLayer.getAssetId(atype, _asset)
        );
    }

    function testDelayIndividualSettlement() public {
        (MockApp app, AssetLayer assetLayer) = getMockApp();
        MockERC20 token = new MockERC20();
        token.mint(address(assetLayer), 100e18);

        // create withdrawal
        uint256 withdrawAmount = 15e18;
        uint256 withdrawalId = assetLayer.nextWithdrawalId();
        app.withdrawERC20(address(token), users[0], withdrawAmount);

        uint256 prevSettlementTime = assetLayer.getSettlementTime(withdrawalId);
        uint256 addedDelay = 3 days;

        AssetLayer.Withdrawal memory withdrawalBefore = assetLayer
            .getWithdrawal(withdrawalId);

        vm.expectEmit(true, true, true, true);
        emit WithdrawDelayExtended(
            withdrawalId,
            addedDelay,
            block.timestamp + defaultDelay + addedDelay
        );

        vm.prank(factory);
        assetLayer.extendWithdrawalDelay(withdrawalId, uint24(addedDelay));

        AssetLayer.Withdrawal memory withdrawalAfter = assetLayer.getWithdrawal(
            withdrawalId
        );

        assertEq(
            assetLayer.getSettlementTime(withdrawalId) - prevSettlementTime,
            addedDelay
        );
        assertEq(withdrawalAfter.delay - withdrawalBefore.delay, addedDelay);

        vm.warp(
            uint256(withdrawalBefore.enqueuedAt) +
                uint256(withdrawalBefore.delay)
        );
        assertFalse(assetLayer.settled(withdrawalId));

        vm.warp(block.timestamp + addedDelay);
        assertTrue(assetLayer.settled(withdrawalId));
        assetLayer.executeDirectSettlement(withdrawalId);
    }

    function testGlobalDelay() public {}

    function getMockApp()
        internal
        returns (MockApp app, AssetLayer assetLayer)
    {
        vm.prank(factory);
        assetLayer = new AssetLayer(upgrader, mockApp, uint24(defaultDelay));
        app = MockApp(assetLayer.logicModule());
    }
}
