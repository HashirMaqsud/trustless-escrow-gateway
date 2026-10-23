// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {EscrowFactory} from "../src/EscrowFactory.sol";

contract DeployEscrowFactory is Script {
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address feeRecipient = vm.envOr("FEE_RECIPIENT", vm.addr(deployerPrivateKey));
        uint256 feeBps = vm.envOr("FEE_BPS", uint256(100)); // Default 1%
        uint256 relayerFeePerTx = vm.envOr("RELAYER_FEE_PER_TX", uint256(0.0001 ether)); // Default 0.0001 ETH per tx

        vm.startBroadcast(deployerPrivateKey);

        // Deploy with all 3 constructor parameters
        EscrowFactory factory = new EscrowFactory(feeRecipient, feeBps, relayerFeePerTx);
        console.log("EscrowFactory deployed at:", address(factory));
        console.log("Fee Recipient set to:", feeRecipient);
        console.log("Fee Bps set to:", feeBps);
        console.log("Relayer Fee Per Tx set to:", relayerFeePerTx);

        vm.stopBroadcast();
        return address(factory);
    }
}