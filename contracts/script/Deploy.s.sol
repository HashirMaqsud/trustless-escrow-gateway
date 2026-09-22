// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {EscrowFactory} from "../src/EscrowFactory.sol";

contract DeployEscrowFactory is Script {
    function run() external returns (EscrowFactory factory) {
        // Read private key or deployer configuration from environment
        vm.startBroadcast();

        factory = new EscrowFactory();
        console.log("EscrowFactory deployed at:", address(factory));

        vm.stopBroadcast();
    }
}