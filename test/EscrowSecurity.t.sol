// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../src/Escrow.sol";

// Seller contract that refuses incoming ETH.
contract RejectingSeller {
    function markDelivered(Escrow escrow) external {
        escrow.markDelivered();
    }

    function claimPayment(Escrow escrow) external {
        escrow.claimPayment();
    }

    receive() external payable {
        revert("ETH rejected");
    }
}

// Buyer contract that refuses incoming ETH.
contract RejectingBuyer {
    Escrow public escrow;

    function create(address seller, uint256 amount, uint256 duration, address arbiter) external {
        escrow = new Escrow(seller, amount, duration, arbiter);
    }

    function fund() external payable {
        escrow.fund{value: msg.value}();
    }

    function requestRefund() external {
        escrow.refund();
    }

    function openDispute() external {
        escrow.openDispute();
    }

    receive() external payable {
        revert("ETH rejected");
    }
}

// Buyer contract that attempts to reenter refund().
contract ReenteringBuyer {
    Escrow public escrow;

    uint256 public receiveCount;
    bool public reentryBlocked;

    function create(address seller, uint256 amount, uint256 duration, address arbiter) external {
        escrow = new Escrow(seller, amount, duration, arbiter);
    }

    function fund() external payable {
        escrow.fund{value: msg.value}();
    }

    function requestRefund() external {
        escrow.refund();
    }

    receive() external payable {
        receiveCount++;

        try escrow.refund() {
        // This should never succeed.
        }
        catch {
            reentryBlocked = true;
        }
    }
}

contract EscrowSecurityTest is Test {
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

    function _escrowWithSeller(address newSeller) internal returns (Escrow newEscrow) {
        vm.prank(buyer);
        newEscrow = new Escrow(newSeller, AMOUNT, DURATION, arbiter);
    }

    // CONSTRUCTOR VALIDATION

    function testRejectsInvalidSellers() public {
        vm.startPrank(buyer);

        vm.expectRevert(Escrow.InvalidSeller.selector);
        new Escrow(address(0), AMOUNT, DURATION, arbiter);

        vm.expectRevert(Escrow.InvalidSeller.selector);
        new Escrow(buyer, AMOUNT, DURATION, arbiter);

        vm.stopPrank();
    }

    function testRejectsInvalidArbiters() public {
        vm.startPrank(buyer);

        vm.expectRevert(Escrow.InvalidArbiter.selector);
        new Escrow(seller, AMOUNT, DURATION, address(0));

        vm.expectRevert(Escrow.InvalidArbiter.selector);
        new Escrow(seller, AMOUNT, DURATION, buyer);

        vm.expectRevert(Escrow.InvalidArbiter.selector);
        new Escrow(seller, AMOUNT, DURATION, seller);

        vm.stopPrank();
    }

    function testRejectsZeroAmount() public {
        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidAmount.selector);

        new Escrow(seller, 0, DURATION, arbiter);
    }

    function testRejectsZeroDuration() public {
        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidDuration.selector);

        new Escrow(seller, AMOUNT, 0, arbiter);
    }

    // FAILED ETH TRANSFERS

    function testRejectedReleasePreservesFundsAndState() public {
        RejectingSeller rejecting = new RejectingSeller();

        Escrow target = _escrowWithSeller(address(rejecting));

        vm.prank(buyer);
        target.fund{value: AMOUNT}();

        vm.prank(buyer);
        vm.expectRevert(Escrow.ETHTransferFailed.selector);
        target.release();

        assertEq(address(target).balance, AMOUNT);

        assertEq(uint256(target.state()), uint256(Escrow.State.FUNDED));
    }

    function testRejectedClaimPreservesApprovalAndFunds() public {
        RejectingSeller rejecting = new RejectingSeller();

        Escrow target = _escrowWithSeller(address(rejecting));

        vm.prank(buyer);
        target.fund{value: AMOUNT}();

        rejecting.markDelivered(target);

        vm.prank(buyer);
        target.approveDelivery();

        vm.expectRevert(Escrow.ETHTransferFailed.selector);
        rejecting.claimPayment(target);

        assertEq(address(target).balance, AMOUNT);

        assertEq(uint256(target.state()), uint256(Escrow.State.APPROVED));
    }

    function testRejectedSellerArbitrationPreservesDispute() public {
        RejectingSeller rejecting = new RejectingSeller();

        Escrow target = _escrowWithSeller(address(rejecting));

        vm.prank(buyer);
        target.fund{value: AMOUNT}();

        rejecting.markDelivered(target);

        vm.prank(buyer);
        target.openDispute();

        vm.prank(arbiter);
        vm.expectRevert(Escrow.ETHTransferFailed.selector);
        target.resolveDispute(true);

        assertEq(address(target).balance, AMOUNT);

        assertEq(uint256(target.state()), uint256(Escrow.State.DISPUTED));

        // The arbiter can still choose the other outcome.
        vm.prank(arbiter);
        target.resolveDispute(false);

        assertEq(address(target).balance, 0);

        assertEq(uint256(target.state()), uint256(Escrow.State.REFUNDED));
    }

    function testRejectedRefundPreservesFundsAndState() public {
        RejectingBuyer rejecting = new RejectingBuyer();

        rejecting.create(seller, AMOUNT, DURATION, arbiter);

        Escrow target = rejecting.escrow();

        vm.prank(buyer);
        rejecting.fund{value: AMOUNT}();

        vm.warp(target.deadline());

        vm.expectRevert(Escrow.ETHTransferFailed.selector);
        rejecting.requestRefund();

        assertEq(address(target).balance, AMOUNT);

        assertEq(uint256(target.state()), uint256(Escrow.State.FUNDED));
    }

    function testRejectedBuyerArbitrationPreservesDispute() public {
        RejectingBuyer rejecting = new RejectingBuyer();

        rejecting.create(seller, AMOUNT, DURATION, arbiter);

        Escrow target = rejecting.escrow();

        vm.prank(buyer);
        rejecting.fund{value: AMOUNT}();

        vm.prank(seller);
        target.markDelivered();

        rejecting.openDispute();

        vm.prank(arbiter);
        vm.expectRevert(Escrow.ETHTransferFailed.selector);
        target.resolveDispute(false);

        assertEq(address(target).balance, AMOUNT);

        assertEq(uint256(target.state()), uint256(Escrow.State.DISPUTED));
    }

    // REENTRANCY

    function testReentrantBuyerCannotRefundTwice() public {
        ReenteringBuyer malicious = new ReenteringBuyer();

        malicious.create(seller, AMOUNT, DURATION, arbiter);

        Escrow target = malicious.escrow();

        vm.prank(buyer);
        malicious.fund{value: AMOUNT}();

        vm.warp(target.deadline());

        malicious.requestRefund();

        assertEq(malicious.receiveCount(), 1);
        assertTrue(malicious.reentryBlocked());

        assertEq(address(malicious).balance, AMOUNT);
        assertEq(address(target).balance, 0);

        assertEq(uint256(target.state()), uint256(Escrow.State.REFUNDED));
    }

    // FUZZ: PAYMENT AMOUNTS

    function testFuzzExactPayment(uint96 rawAmount) public {
        uint256 agreed = bound(uint256(rawAmount), 1, 100 ether);

        vm.prank(buyer);
        Escrow target = new Escrow(seller, agreed, DURATION, arbiter);

        vm.deal(buyer, agreed);

        vm.prank(buyer);
        target.fund{value: agreed}();

        assertEq(address(target).balance, agreed);

        assertEq(uint256(target.state()), uint256(Escrow.State.FUNDED));
    }

    function testFuzzIncorrectPayment(uint96 rawAmount) public {
        uint256 provided = bound(uint256(rawAmount), 0, 2 ether);

        if (provided == AMOUNT) {
            provided += 1;
        }

        vm.deal(buyer, provided);

        vm.prank(buyer);
        vm.expectRevert(Escrow.IncorrectAmount.selector);
        escrow.fund{value: provided}();

        assertEq(address(escrow).balance, 0);

        assertEq(uint256(escrow.state()), uint256(Escrow.State.CREATED));
    }

    // FUZZ: DEADLINES

    function testFuzzCannotRefundBeforeDeadline(uint32 rawSeconds) public {
        _fund();

        uint256 elapsed = bound(uint256(rawSeconds), 0, DURATION - 1);

        vm.warp(block.timestamp + elapsed);

        vm.prank(buyer);
        vm.expectRevert(Escrow.DeadlineNotReached.selector);
        escrow.refund();

        assertEq(address(escrow).balance, AMOUNT);
    }

    function testFuzzCanRefundAfterDeadline(uint32 rawSeconds) public {
        _fund();

        uint256 additionalTime = bound(uint256(rawSeconds), 0, 365 days);

        vm.warp(escrow.deadline() + additionalTime);

        vm.prank(buyer);
        escrow.refund();

        assertEq(address(escrow).balance, 0);

        assertEq(uint256(escrow.state()), uint256(Escrow.State.REFUNDED));
    }

    function testFuzzBuyerCanApproveDuringReview(uint32 rawSeconds) public {
        _deliver();

        uint256 elapsed = bound(uint256(rawSeconds), 0, 3 days - 1);

        vm.warp(block.timestamp + elapsed);

        vm.prank(buyer);
        escrow.approveDelivery();

        assertEq(uint256(escrow.state()), uint256(Escrow.State.APPROVED));
    }

    function testFuzzSilenceNeverAutomaticallyPaysSeller(uint32 rawSeconds) public {
        _deliver();

        uint256 additionalTime = bound(uint256(rawSeconds), 0, 365 days);

        vm.warp(escrow.reviewDeadline() + additionalTime);

        // Silence alone cannot authorize payment.
        vm.prank(seller);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.claimPayment();

        // Anybody can request arbitration instead.
        vm.prank(attacker);
        escrow.triggerDispute();

        assertEq(uint256(escrow.state()), uint256(Escrow.State.DISPUTED));

        assertEq(address(escrow).balance, AMOUNT);
    }
}
