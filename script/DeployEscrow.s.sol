// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Escrow} from "../src/Escrow.sol";

contract DeployEscrow is Script {
    function run() external returns (Escrow escrow) {
        address seller = vm.envAddress("SELLER_ADDRESS");
        uint256 amount = vm.envUint("ESCROW_AMOUNT");

        vm.startBroadcast();

        escrow = new Escrow(seller, amount);

        vm.stopBroadcast();
    }
}
