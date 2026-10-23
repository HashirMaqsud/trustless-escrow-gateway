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
    bytes32 private constant SUBMIT_DELIVERABLE_TYPEHASH =
        keccak256("SubmitDeliverable(address freelancer,string deliverableUrl,string ipfsHash,string submissionNotes,uint256 milestoneIndex,uint256 nonce,uint256 deadline)");

    function _buildDigest(
        address escrow,
        address freelancer,
        string memory url,
        string memory ipfsHash,
        string memory notes,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("TrustlessEscrow")),
                keccak256(bytes("1")),
                block.chainid,
                escrow
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                SUBMIT_DELIVERABLE_TYPEHASH,
                freelancer,
                keccak256(bytes(url)),
                keccak256(bytes(ipfsHash)),
                keccak256(bytes(notes)),
                0,
                IEscrow(escrow).nonces(freelancer),
                deadline
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function run() external {
        address escrow = 0xaC4c5f10903BF8d729aFA82D9459b212176BDeF6;
        uint256 freelancerPk = 0xed71ca8a83e536b8bc398d647615f60496e7cfa75c459e4ddb46f2700f880e3b;
        address freelancer = vm.addr(freelancerPk);
        uint256 relayerPk = 0x27f9f0b0fd193953e58df20cd0c690dd12beb3595fbd503e08a286ecb9c5b80c;

        string memory url = "https://github.com/HashirMaqsud/trustless-escrow-gateway/pull/1";
        string memory ipfsHash = "ipfs://bafybeicg2oxqozr75w3xjoxj4zsvygl4q752k4z626j5z4y25n7e4q4n4y";
        string memory notes = "Initial milestone deliverable with codebase review and automated tests.";
        uint256 deadline = block.timestamp + 86400;

        bytes32 digest = _buildDigest(escrow, freelancer, url, ipfsHash, notes, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(freelancerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        console.log("Freelancer:", freelancer);
        console.log("Deadline:", deadline);

        vm.startBroadcast(relayerPk);
        IEscrow(escrow).submitDeliverableWithSig{gas: 1000000}(
            url,
            ipfsHash,
            notes,
            0,
            deadline,
            signature
        );
        vm.stopBroadcast();
    }
}