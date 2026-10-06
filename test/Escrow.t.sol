// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../src/Escrow.sol";

contract EscrowTest is Test {
    Escrow public escrow;

    address public buyer = address(0xB1);
    address public seller = address(0x51);
    address public attacker = address(0xA1);

    uint256 public constant AMOUNT = 1 ether;

    function setUp() public {
        vm.deal(buyer, 10 ether);

        vm.prank(buyer);
        escrow = new Escrow(seller, AMOUNT);
    }

    function testInitialState() public view {
        assertEq(escrow.buyer(), buyer);
        assertEq(escrow.seller(), seller);
        assertEq(escrow.amount(), AMOUNT);
        assertEq(uint256(escrow.state()), uint256(Escrow.State.CREATED));
    }

    function testBuyerCanFundEscrow() public {
        vm.prank(buyer);
        escrow.fund{value: AMOUNT}();

        assertEq(address(escrow).balance, AMOUNT);
        assertEq(uint256(escrow.state()), uint256(Escrow.State.FUNDED));
    }

    function testNonBuyerCannotFund() public {
        vm.deal(attacker, AMOUNT);

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
}
