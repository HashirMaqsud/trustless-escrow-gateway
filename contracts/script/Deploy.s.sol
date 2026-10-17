// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {EscrowFactory} from "../src/EscrowFactory.sol";

contract DeployEscrowFactory is Script {
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address feeRecipient = vm.envOr("FEE_RECIPIENT", vm.addr(deployerPrivateKey));
        uint256 feeBps = vm.envOr("FEE_BPS", uint256(100));

        vm.startBroadcast(deployerPrivateKey);

        EscrowFactory factory = new EscrowFactory(feeRecipient, feeBps);
        console.log("EscrowFactory deployed at:", address(factory));

        vm.stopBroadcast();
        return address(factory);
    }
}