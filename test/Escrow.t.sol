// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../src/Escrow.sol";

contract EscrowTest is Test {
    Escrow public escrow;

    address public buyer = address(0xB1);
    address public seller = address(0x51);
    address public attacker = address(0xA1);
    address public arbiter = address(0xA2);

    uint256 public constant AMOUNT = 1 ether;
    uint256 public constant DURATION = 7 days;

    function setUp() public {
        vm.deal(buyer, 10 ether);
        vm.deal(attacker, 10 ether);

        vm.prank(buyer);
        escrow = new Escrow(seller, AMOUNT, DURATION, arbiter);
    }

    function testInitialState() public view {
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.amount(), AMOUNT);
        assertEq(escrow.duration(), DURATION);
        assertEq(escrow.deadline(), 0);

        assertEq(uint256(escrow.state()), uint256(Escrow.State.CREATED));
    }

    function testBuyerCanFundEscrow() public {
        uint256 startTime = block.timestamp;

        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();

        assertEq(address(escrow).balance, AMOUNT);
        assertEq(escrow.deadline(), startTime + DURATION);

        assertEq(uint256(escrow.state()), uint256(Escrow.State.FUNDED));
    }

    function testNonBuyerCannotFund() public {
        vm.prank(attacker);
        vm.expectRevert(Escrow.OnlyBuyer.selector);

        escrow.fund{value: AMOUNT}();
    }

    function testCannotFundWithIncorrectAmount() public {
        vm.prank(buyer);
        vm.expectRevert(Escrow.IncorrectAmount.selector);

        escrow.fund{value: 0.5 ether}();
    }

    function testCannotFundTwice() public {
        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();

        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);

        escrow.fund{value: AMOUNT}();
    }

    function testBuyerCanReleaseFunds() public {
        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(buyer);
        escrow.release();

        assertEq(seller.balance, sellerBalanceBefore + AMOUNT);

        assertEq(address(escrow).balance, 0);

        assertEq(uint256(escrow.state()), uint256(Escrow.State.RELEASED));
    }

    function testCannotReleaseBeforeFunding() public {
        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);

        escrow.release();
    }

    function testNonBuyerCannotRelease() public {
        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();

        vm.prank(attacker);
        vm.expectRevert(Escrow.OnlyBuyer.selector);

        escrow.release();
    }

    function testCannotReleaseTwice() public {
        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();

        vm.prank(buyer);
        escrow.release();

        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);

        escrow.release();
    }

    function testBuyerCanCancelBeforeFunding() public {
        vm.prank(buyer);
        escrow.cancel();

        assertEq(uint256(escrow.state()), uint256(Escrow.State.CANCELLED));

        assertEq(address(escrow).balance, 0);
    }

    function testNonBuyerCannotCancel() public {
        vm.prank(attacker);
        vm.expectRevert(Escrow.OnlyBuyer.selector);

        escrow.cancel();
    }

    function testCannotCancelAfterFunding() public {
        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();

        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);

        escrow.cancel();
    }

    function testCannotRefundBeforeDeadline() public {
        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();

        vm.prank(buyer);
        vm.expectRevert(Escrow.DeadlineNotReached.selector);

        escrow.refund();
    }

    function testBuyerCanRefundAfterDeadline() public {
        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();

        uint256 buyerBalanceBeforeRefund = buyer.balance;

        vm.warp(escrow.deadline());

        vm.prank(buyer);
        escrow.refund();

        assertEq(buyer.balance, buyerBalanceBeforeRefund + AMOUNT);

        assertEq(address(escrow).balance, 0);

        assertEq(uint256(escrow.state()), uint256(Escrow.State.REFUNDED));
    }

    function testNonBuyerCannotRefund() public {
        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();

        vm.warp(escrow.deadline());

        vm.prank(attacker);
        vm.expectRevert(Escrow.OnlyBuyer.selector);

        escrow.refund();
    }

    function testCannotRefundAfterRelease() public {
        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();

        vm.prank(buyer);
        escrow.release();

        vm.warp(block.timestamp + DURATION);

        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);

        escrow.refund();
    }

    function testCannotReleaseAfterRefund() public {
        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();

        vm.warp(escrow.deadline());

        vm.prank(buyer);
        escrow.refund();

        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);

        escrow.release();
    }
}
