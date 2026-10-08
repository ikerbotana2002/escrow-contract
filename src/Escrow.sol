// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Escrow is ReentrancyGuard {
    enum State {
        CREATED,
        FUNDED,
        DELIVERED,
        APPROVED,
        DISPUTED,
        RELEASED,
        REFUNDED,
        CANCELLED
    }

    address public immutable buyer;
    address public immutable seller;
    address public immutable arbiter;

    uint256 public immutable amount;
    uint256 public immutable duration;

    uint256 public constant REVIEW_PERIOD = 3 days;

    uint256 public deadline;
    uint256 public reviewDeadline;

    State public state;

    error OnlyBuyer();
    error OnlySeller();
    error OnlyArbiter();
    error InvalidState();
    error IncorrectAmount();
    error InvalidSeller();
    error InvalidArbiter();
    error InvalidAmount();
    error InvalidDuration();
    error DeadlineNotReached();
    error DeliveryDeadlinePassed();
    error ReviewPeriodNotFinished();
    error ReviewPeriodFinished();
    error ETHTransferFailed();

    event EscrowFunded(address indexed buyer, uint256 amount, uint256 deadline);
    event EscrowReleased(address indexed seller, uint256 amount);
    event EscrowRefunded(address indexed buyer, uint256 amount);
    event EscrowCancelled(address indexed buyer);
    event WorkDelivered(address indexed seller, uint256 reviewDeadline);
    event DeliveryApproved(address indexed buyer);
    event DisputeOpened(address indexed initiatedBy);
    event DisputeResolved(address indexed recipient, uint256 amount);

    constructor(address _seller, uint256 _amount, uint256 _duration, address _arbiter) {
        if (_seller == address(0) || _seller == msg.sender) {
            revert InvalidSeller();
        }

        if (_arbiter == address(0) || _arbiter == msg.sender || _arbiter == _seller) {
            revert InvalidArbiter();
        }

        if (_amount == 0) revert InvalidAmount();
        if (_duration == 0) revert InvalidDuration();

        buyer = msg.sender;
        seller = _seller;
        arbiter = _arbiter;
        amount = _amount;
        duration = _duration;

        state = State.CREATED;
    }

    function fund() external payable {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.CREATED) revert InvalidState();
        if (msg.value != amount) revert IncorrectAmount();

        deadline = block.timestamp + duration;
        state = State.FUNDED;

        emit EscrowFunded(buyer, amount, deadline);
    }

    function markDelivered() external {
        if (msg.sender != seller) revert OnlySeller();
        if (state != State.FUNDED) revert InvalidState();
        if (block.timestamp >= deadline) revert DeliveryDeadlinePassed();

        reviewDeadline = block.timestamp + REVIEW_PERIOD;
        state = State.DELIVERED;

        emit WorkDelivered(seller, reviewDeadline);
    }

    function approveDelivery() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.DELIVERED) revert InvalidState();

        if (block.timestamp >= reviewDeadline) {
            revert ReviewPeriodFinished();
        }

        state = State.APPROVED;

        emit DeliveryApproved(buyer);
    }

    function release() external nonReentrant {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.FUNDED) revert InvalidState();

        state = State.RELEASED;

        (bool success,) = payable(seller).call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        emit EscrowReleased(seller, amount);
    }

    function refund() external nonReentrant {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.FUNDED) revert InvalidState();
        if (block.timestamp < deadline) revert DeadlineNotReached();

        state = State.REFUNDED;

        (bool success,) = payable(buyer).call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        emit EscrowRefunded(buyer, amount);
    }

    function openDispute() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.DELIVERED) revert InvalidState();

        if (block.timestamp >= reviewDeadline) {
            revert ReviewPeriodFinished();
        }

        state = State.DISPUTED;

        emit DisputeOpened(msg.sender);
    }

    function triggerDispute() external {
        if (state != State.DELIVERED) revert InvalidState();

        if (block.timestamp < reviewDeadline) {
            revert ReviewPeriodNotFinished();
        }

        state = State.DISPUTED;

        emit DisputeOpened(msg.sender);
    }

    function claimPayment() external nonReentrant {
        if (msg.sender != seller) revert OnlySeller();
        if (state != State.APPROVED) revert InvalidState();

        state = State.RELEASED;

        (bool success,) = payable(seller).call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        emit EscrowReleased(seller, amount);
    }

    function resolveDispute(bool paySeller) external nonReentrant {
        if (msg.sender != arbiter) revert OnlyArbiter();
        if (state != State.DISPUTED) revert InvalidState();

        address recipient = paySeller ? seller : buyer;

        state = paySeller ? State.RELEASED : State.REFUNDED;

        (bool success,) = payable(recipient).call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        emit DisputeResolved(recipient, amount);
    }

    function cancel() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.CREATED) revert InvalidState();

        state = State.CANCELLED;

        emit EscrowCancelled(buyer);
    }
}
