// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Escrow is ReentrancyGuard {
    enum State {
        CREATED,
        FUNDED,
        RELEASED
    }

    address public immutable buyer;
    address public immutable seller;

    uint256 public immutable amount;

    State public state;

    error OnlyBuyer();
    error InvalidState();
    error IncorrectAmount();
    error ETHTransferFailed();

    event EscrowFunded(address indexed buyer, uint256 amount);
    event EscrowReleased(address indexed seller, uint256 amount);

    constructor(address _seller, uint256 _amount) {
        buyer = msg.sender;
        seller = _seller;
        amount = _amount;

        state = State.CREATED;
    }

    function fund() external payable {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.CREATED) revert InvalidState();
        if (msg.value != amount) revert IncorrectAmount();

        state = State.FUNDED;

        emit EscrowFunded(msg.sender, msg.value);
    }

    function release() external nonReentrant {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (state != State.FUNDED) revert InvalidState();

        state = State.RELEASED;

        (bool success,) = payable(seller).call{value: amount}("");

        if (!success) revert ETHTransferFailed();

        emit EscrowReleased(seller, amount);
    }
}
