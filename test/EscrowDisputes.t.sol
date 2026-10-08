// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../src/Escrow.sol";

contract EscrowDisputesTest is Test {
    Escrow public escrow;

    address public buyer = address(0xB1);
    address public seller = address(0x51);
    address public arbiter = address(0xA2);
    address public attacker = address(0xA1);

    uint256 public constant AMOUNT = 1 ether;
    uint256 public constant DURATION = 7 days;

    function setUp() public {
        vm.deal(buyer, 10 ether);

        vm.prank(buyer);
        escrow = new Escrow(seller, AMOUNT, DURATION, arbiter);
    }

    function _fund() internal {
        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();
    }

    function _deliver() internal {
        _fund();

        vm.prank(seller);
        escrow.markDelivered();
    }

    function _approve() internal {
        _deliver();

        vm.prank(buyer);
        escrow.approveDelivery();
    }

    function _dispute() internal {
        _deliver();

        vm.prank(buyer);
        escrow.openDispute();
    }

    // CONFIGURATION

    function testArbiterConfiguration() public view {
        assertEq(escrow.arbiter(), arbiter);
        assertEq(escrow.REVIEW_PERIOD(), 3 days);
        assertEq(escrow.reviewDeadline(), 0);
    }

    // DELIVERY

    function testSellerCanMarkDelivered() public {
        _fund();

        uint256 deliveryTime = block.timestamp;

        vm.prank(seller);
        escrow.markDelivered();

        assertEq(uint256(escrow.state()), uint256(Escrow.State.DELIVERED));

        assertEq(escrow.reviewDeadline(), deliveryTime + 3 days);
        assertEq(address(escrow).balance, AMOUNT);
    }

    function testNonSellerCannotMarkDelivered() public {
        _fund();

        vm.prank(attacker);
        vm.expectRevert(Escrow.OnlySeller.selector);
        escrow.markDelivered();
    }

    function testCannotDeliverBeforeFunding() public {
        vm.prank(seller);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.markDelivered();
    }

    function testCannotDeliverAtFundingDeadline() public {
        _fund();

        vm.warp(escrow.deadline());

        vm.prank(seller);
        vm.expectRevert(Escrow.DeliveryDeadlinePassed.selector);
        escrow.markDelivered();
    }

    function testCannotMarkDeliveredTwice() public {
        _deliver();

        vm.prank(seller);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.markDelivered();
    }

    // BUYER APPROVAL

    function testBuyerCanApproveDelivery() public {
        _deliver();

        vm.prank(buyer);
        escrow.approveDelivery();

        assertEq(uint256(escrow.state()), uint256(Escrow.State.APPROVED));

        assertEq(address(escrow).balance, AMOUNT);
    }

    function testNonBuyerCannotApprove() public {
        _deliver();

        vm.prank(seller);
        vm.expectRevert(Escrow.OnlyBuyer.selector);
        escrow.approveDelivery();
    }

    function testCannotApproveBeforeDelivery() public {
        _fund();

        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.approveDelivery();
    }

    function testCannotApproveAfterReviewPeriod() public {
        _deliver();

        vm.warp(escrow.reviewDeadline());

        vm.prank(buyer);
        vm.expectRevert(Escrow.ReviewPeriodFinished.selector);
        escrow.approveDelivery();
    }

    function testCannotDisputeAfterApproval() public {
        _approve();

        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.openDispute();
    }

    // SELLER PAYMENT

    function testSellerCannotClaimWithoutApproval() public {
        _deliver();

        vm.warp(escrow.reviewDeadline() + 5 days);

        vm.prank(seller);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.claimPayment();
    }

    function testSellerCanClaimImmediatelyAfterApproval() public {
        _approve();

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(seller);
        escrow.claimPayment();

        assertEq(seller.balance, sellerBalanceBefore + AMOUNT);
        assertEq(address(escrow).balance, 0);

        assertEq(uint256(escrow.state()), uint256(Escrow.State.RELEASED));
    }

    function testSellerCanClaimLongAfterApproval() public {
        _approve();

        vm.warp(block.timestamp + 365 days);

        vm.prank(seller);
        escrow.claimPayment();

        assertEq(seller.balance, AMOUNT);
        assertEq(address(escrow).balance, 0);
    }

    function testNonSellerCannotClaimPayment() public {
        _approve();

        vm.prank(attacker);
        vm.expectRevert(Escrow.OnlySeller.selector);
        escrow.claimPayment();
    }

    function testCannotClaimTwice() public {
        _approve();

        vm.prank(seller);
        escrow.claimPayment();

        vm.prank(seller);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.claimPayment();
    }

    function testCannotReleaseAfterDelivery() public {
        _deliver();

        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.release();
    }

    function testCannotRefundAfterDelivery() public {
        _deliver();

        vm.warp(escrow.deadline() + 1);

        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.refund();
    }

    // BUYER DISPUTES

    function testBuyerCanOpenDispute() public {
        _dispute();

        assertEq(uint256(escrow.state()), uint256(Escrow.State.DISPUTED));

        assertEq(address(escrow).balance, AMOUNT);
    }

    function testNonBuyerCannotOpenDispute() public {
        _deliver();

        vm.prank(seller);
        vm.expectRevert(Escrow.OnlyBuyer.selector);
        escrow.openDispute();
    }

    function testCannotDisputeBeforeDelivery() public {
        _fund();

        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.openDispute();
    }

    function testCannotOpenDisputeAfterReviewPeriod() public {
        _deliver();

        vm.warp(escrow.reviewDeadline());

        vm.prank(buyer);
        vm.expectRevert(Escrow.ReviewPeriodFinished.selector);
        escrow.openDispute();
    }

    // TIMEOUT DISPUTES

    function testAnyoneCanTriggerDisputeAfterTimeout() public {
        _deliver();

        vm.warp(escrow.reviewDeadline());

        vm.prank(attacker);
        escrow.triggerDispute();

        assertEq(uint256(escrow.state()), uint256(Escrow.State.DISPUTED));

        assertEq(address(escrow).balance, AMOUNT);
    }

    function testCannotTriggerDisputeTooEarly() public {
        _deliver();

        vm.prank(attacker);
        vm.expectRevert(Escrow.ReviewPeriodNotFinished.selector);
        escrow.triggerDispute();
    }

    function testCannotTriggerDisputeAfterApproval() public {
        _approve();

        vm.warp(escrow.reviewDeadline());

        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.triggerDispute();
    }

    // ARBITRATION

    function testOnlyArbiterCanResolveDispute() public {
        _dispute();

        vm.prank(attacker);
        vm.expectRevert(Escrow.OnlyArbiter.selector);
        escrow.resolveDispute(true);
    }

    function testCannotResolveWithoutDispute() public {
        _fund();

        vm.prank(arbiter);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.resolveDispute(true);
    }

    function testArbiterCanPaySeller() public {
        _dispute();

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(arbiter);
        escrow.resolveDispute(true);

        assertEq(seller.balance, sellerBalanceBefore + AMOUNT);
        assertEq(address(escrow).balance, 0);

        assertEq(uint256(escrow.state()), uint256(Escrow.State.RELEASED));
    }

    function testArbiterCanRefundBuyer() public {
        _dispute();

        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(arbiter);
        escrow.resolveDispute(false);

        assertEq(buyer.balance, buyerBalanceBefore + AMOUNT);
        assertEq(address(escrow).balance, 0);

        assertEq(uint256(escrow.state()), uint256(Escrow.State.REFUNDED));
    }

    function testCannotBypassDispute() public {
        _dispute();

        vm.startPrank(buyer);

        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.release();

        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.refund();

        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.approveDelivery();

        vm.stopPrank();

        vm.prank(seller);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.claimPayment();

        assertEq(address(escrow).balance, AMOUNT);
    }

    function testCannotResolveDisputeTwice() public {
        _dispute();

        vm.prank(arbiter);
        escrow.resolveDispute(true);

        vm.prank(arbiter);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.resolveDispute(false);
    }
}
