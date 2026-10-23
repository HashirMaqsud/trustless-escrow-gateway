// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

interface IEscrow {
    function nonces(address) external view returns (uint256);
    function submitDeliverableWithSig(
        string calldata deliverableUrl,
        string calldata ipfsHash,
        string calldata notes,
        uint256 milestoneIndex,
        uint256 deadline,
        bytes calldata signature
    ) external;
}

contract SignDeliverableScript is Script {
    // EIP-712 TypeHash matching updated Escrow.sol exactly
    bytes32 private constant SUBMIT_DELIVERABLE_TYPEHASH =
        keccak256("SubmitDeliverable(address freelancer,string deliverableUrl,string ipfsHash,string submissionNotes,uint256 milestoneIndex,uint256 nonce,uint256 deadline)");

    function run() external {
        address escrow = 0xaC4c5f10903BF8d729aFA82D9459b212176BDeF6;
        uint256 freelancerPk = 0xed71ca8a83e536b8bc398d647615f60496e7cfa75c459e4ddb46f2700f880e3b;
        address freelancer = vm.addr(freelancerPk);
        uint256 relayerPk = 0x27f9f0b0fd193953e58df20cd0c690dd12beb3595fbd503e08a286ecb9c5b80c;

        // Deliverable Payload
        string memory url = "https://github.com/HashirMaqsud/trustless-escrow-gateway/pull/1";
        string memory ipfsHash = "ipfs://bafybeicg2oxqozr75w3xjoxj4zsvygl4q752k4z626j5z4y25n7e4q4n4y";
        string memory notes = "Initial milestone deliverable with codebase review and automated tests.";
        uint256 milestoneIndex = 0; // First milestone
        uint256 deadline = block.timestamp + 86400; // 24 hours validity
        uint256 nonce = IEscrow(escrow).nonces(freelancer);

        // OpenZeppelin v5 exact domain separator calculation
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("TrustlessEscrow")),
                keccak256(bytes("1")),
                block.chainid,
                escrow
            )
        );

        // StructHash with IPFS, notes, and milestoneIndex
        bytes32 structHash = keccak256(
            abi.encode(
                SUBMIT_DELIVERABLE_TYPEHASH,
                freelancer,
                keccak256(bytes(url)),
                keccak256(bytes(ipfsHash)),
                keccak256(bytes(notes)),
                milestoneIndex,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(freelancerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        console.log("Freelancer:", freelancer);
        console.log("Current Nonce:", nonce);
        console.log("Milestone Index:", milestoneIndex);
        console.log("Deadline:", deadline);

        // Broadcast by relayer with safe gas limit
        vm.startBroadcast(relayerPk);
        IEscrow(escrow).submitDeliverableWithSig{gas: 1000000}(
            url,
            ipfsHash,
            notes,
            milestoneIndex,
            deadline,
            signature
        );
        vm.stopBroadcast();
    }
}