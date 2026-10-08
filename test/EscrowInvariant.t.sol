// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Vm} from "forge-std/Vm.sol";
import {Escrow} from "../src/Escrow.sol";

contract EscrowHandler {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Escrow public escrow;

    address public constant SELLER = address(0x51);
    address public constant ARBITER = address(0xA2);

    uint256 public constant AMOUNT = 1 ether;
    uint256 public constant DURATION = 7 days;

    constructor() {
        escrow = new Escrow(SELLER, AMOUNT, DURATION, ARBITER);
    }

    function fund() external {
        if (escrow.state() != Escrow.State.CREATED) return;
        if (address(this).balance < AMOUNT) return;

        escrow.fund{value: AMOUNT}();
    }

    function cancel() external {
        if (escrow.state() != Escrow.State.CREATED) return;

        escrow.cancel();
    }

    function release() external {
        if (escrow.state() != Escrow.State.FUNDED) return;

        escrow.release();
    }

    function markDelivered() external {
        if (escrow.state() != Escrow.State.FUNDED) return;
        if (block.timestamp >= escrow.deadline()) return;

        vm.prank(SELLER);
        escrow.markDelivered();
    }

    function approveDelivery() external {
        if (escrow.state() != Escrow.State.DELIVERED) return;
        if (block.timestamp >= escrow.reviewDeadline()) return;

        escrow.approveDelivery();
    }

    function openDispute() external {
        if (escrow.state() != Escrow.State.DELIVERED) return;
        if (block.timestamp >= escrow.reviewDeadline()) return;

        escrow.openDispute();
    }

    function triggerDispute() external {
        if (escrow.state() != Escrow.State.DELIVERED) return;
        if (block.timestamp < escrow.reviewDeadline()) return;

        escrow.triggerDispute();
    }

    function claimPayment() external {
        if (escrow.state() != Escrow.State.APPROVED) return;

        vm.prank(SELLER);
        escrow.claimPayment();
    }

    function refund() external {
        if (escrow.state() != Escrow.State.FUNDED) return;
        if (block.timestamp < escrow.deadline()) return;

        escrow.refund();
    }

    function resolveDispute(bool paySeller) external {
        if (escrow.state() != Escrow.State.DISPUTED) return;

        vm.prank(ARBITER);
        escrow.resolveDispute(paySeller);
    }

    function advanceTime(uint32 rawSeconds) external {
        uint256 elapsed = (uint256(rawSeconds) % (30 days)) + 1;

        vm.warp(block.timestamp + elapsed);
    }

    function startNewAgreement() external {
        Escrow.State current = escrow.state();

        bool finished =
            (current == Escrow.State.RELEASED || current == Escrow.State.REFUNDED || current == Escrow.State.CANCELLED);

        if (!finished) return;

        escrow = new Escrow(SELLER, AMOUNT, DURATION, ARBITER);
    }

    receive() external payable {}
}

contract EscrowInvariantTest is StdInvariant, Test {
    EscrowHandler public handler;

    uint256 public constant INITIAL_BALANCE = 100 ether;

    function setUp() public {
        handler = new EscrowHandler();

        vm.deal(address(handler), INITIAL_BALANCE);

        targetContract(address(handler));
    }

    function invariant_BalanceMatchesState() public view {
        Escrow current = handler.escrow();
        Escrow.State currentState = current.state();

        bool fundsLocked =
            (currentState == Escrow.State.FUNDED || currentState == Escrow.State.DELIVERED
                || currentState == Escrow.State.APPROVED || currentState == Escrow.State.DISPUTED);

        if (fundsLocked) {
            assertEq(address(current).balance, 1 ether);
        } else {
            assertEq(address(current).balance, 0);
        }
    }

    function invariant_ETHIsConserved() public view {
        Escrow current = handler.escrow();

        address seller = handler.SELLER();

        uint256 totalETH = address(handler).balance + seller.balance + address(current).balance;

        assertEq(totalETH, INITIAL_BALANCE);
    }
}
