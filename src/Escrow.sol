// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Escrow is ReentrancyGuard {
    enum State {
        CREATED,
        FUNDED,
        RELEASED,
        REFUNDED,
        CANCELLED
    }

    address public immutable buyer;
    address public immutable seller;

    uint256 public immutable amount;
    uint256 public immutable duration;

    uint256 public deadline;

    State public state;

    error OnlyBuyer();
    error InvalidState();
    error IncorrectAmount();
    error DeadlineNotReached();
    error ETHTransferFailed();

    event EscrowFunded(address indexed buyer, uint256 amount, uint256 deadline);

    event EscrowReleased(address indexed seller, uint256 amount);

    event EscrowRefunded(address indexed buyer, uint256 amount);

    event EscrowCancelled(address indexed buyer);

    constructor(address _seller, uint256 _amount, uint256 _duration) {
        buyer = msg.sender;
        seller = _seller;
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

        emit EscrowFunded(msg.sender, msg.value, deadline);
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

    function cancel() external {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.CREATED) revert InvalidState();

        state = State.CANCELLED;

        emit EscrowCancelled(msg.sender);
    }
}
