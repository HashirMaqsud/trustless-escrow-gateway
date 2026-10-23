// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";
import {EscrowFactory} from "../../src/EscrowFactory.sol";

contract EscrowSigTest is Test {
    Escrow public escrow;
    EscrowFactory public factory;

    uint256 internal clientPk = 0xA11CE;
    uint256 internal freelancerPk = 0xB0B;
    uint256 internal arbiterPk = 0xCAFE;

    address public client;
    address public freelancer;
    address public arbiter;
    address public feeRecipient = makeAddr("feeRecipient");
    address public relayer = makeAddr("relayer");

    uint256 public constant MILESTONE_1_AMOUNT = 0.5 ether;
    uint256 public constant MILESTONE_2_AMOUNT = 0.5 ether;
    uint256 public constant TOTAL_AMOUNT = 1 ether;
    uint256 public constant FEE_BPS = 100; // 1% = 0.01 ether
    uint256 public constant RELAYER_FEE_PER_TX = 0.0001 ether;

    // Relayer Pool = (2 milestones * (3 revisions + 1) + 2 buffer) * 0.0001 = 10 * 0.0001 = 0.001 ether
    uint256 public constant TOTAL_RELAYER_POOL = RELAYER_FEE_PER_TX * 10;
    uint256 public constant TOTAL_REQUIRED = TOTAL_AMOUNT + ((TOTAL_AMOUNT * FEE_BPS) / 10000) + TOTAL_RELAYER_POOL;

    string public constant URL = "https://github.com/project/completed-work";
    string public constant IPFS_CID = "ipfs://bafybeicg2oxqozr75w3xjoxj4zsvygl4q752k4z626j5z4y25n7e4q4n4y";
    string public constant NOTES = "Production build delivery";

    // EIP-712 Typehashes matching updated Escrow.sol exactly
    bytes32 private constant SUBMIT_DELIVERABLE_TYPEHASH =
        keccak256("SubmitDeliverable(address freelancer,string deliverableUrl,string ipfsHash,string submissionNotes,uint256 milestoneIndex,uint256 nonce,uint256 deadline)");

    bytes32 private constant RELEASE_MILESTONE_TYPEHASH =
        keccak256("ReleaseMilestone(address client,uint256 milestoneIndex,uint256 nonce,uint256 deadline)");

    bytes32 private constant RELEASE_ALL_FUNDS_TYPEHASH =
        keccak256("ReleaseAllFunds(address client,uint256 nonce,uint256 deadline)");

    bytes32 private constant RAISE_DISPUTE_TYPEHASH =
        keccak256("RaiseDispute(address sender,uint256 nonce,uint256 deadline)");

    bytes32 private constant RESOLVE_DISPUTE_TYPEHASH =
        keccak256("ResolveDispute(address arbiter,uint256 clientRefund,uint256 freelancerPayout,uint256 nonce,uint256 deadline)");

    function setUp() public {
        client = vm.addr(clientPk);
        freelancer = vm.addr(freelancerPk);
        arbiter = vm.addr(arbiterPk);

        vm.deal(client, 10 ether);
        vm.deal(relayer, 1 ether);

        factory = new EscrowFactory(feeRecipient, FEE_BPS, RELAYER_FEE_PER_TX);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = MILESTONE_1_AMOUNT;
        amounts[1] = MILESTONE_2_AMOUNT;

        string[] memory descriptions = new string[](2);
        descriptions[0] = "Milestone 1";
        descriptions[1] = "Milestone 2";

        escrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(0),
            amounts,
            descriptions,
            FEE_BPS,
            RELAYER_FEE_PER_TX
        );

        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();
    }

    function _getEIP712DomainSeparator(address contractAddress) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("TrustlessEscrow")),
                keccak256(bytes("1")),
                block.chainid,
                contractAddress
            )
        );
    }

    // --- Deliverable Gasless Submission Tests ---

    function test_Gasless_SubmitDeliverableWithSig_Success_And_ReimburseRelayer() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = escrow.nonces(freelancer);
        uint256 relayerBalBefore = relayer.balance;

        bytes32 structHash = keccak256(
            abi.encode(
                SUBMIT_DELIVERABLE_TYPEHASH,
                freelancer,
                keccak256(bytes(URL)),
                keccak256(bytes(IPFS_CID)),
                keccak256(bytes(NOTES)),
                0, // milestoneIndex
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(freelancerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Relayer broadcasts the meta-transaction
        vm.prank(relayer);
        escrow.submitDeliverableWithSig(URL, IPFS_CID, NOTES, 0, deadline, signature);

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Delivered));
        assertEq(escrow.nonces(freelancer), 1);
        assertEq(escrow.getLatestSubmission().deliverableUrl, URL);

        // Verify Autonomous Relayer Reimbursement
        assertEq(relayer.balance, relayerBalBefore + RELAYER_FEE_PER_TX);
    }

    function test_Gasless_SubmitDeliverable_RevertIf_SignatureExpired() public {
        uint256 deadline = block.timestamp - 1; // Expired

        bytes32 structHash = keccak256(
            abi.encode(
                SUBMIT_DELIVERABLE_TYPEHASH,
                freelancer,
                keccak256(bytes(URL)),
                keccak256(bytes(IPFS_CID)),
                keccak256(bytes(NOTES)),
                0,
                0,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(freelancerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Escrow.SignatureExpired.selector);
        vm.prank(relayer);
        escrow.submitDeliverableWithSig(URL, IPFS_CID, NOTES, 0, deadline, signature);
    }

    function test_Gasless_SubmitDeliverable_RevertIf_InvalidSigner() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(
                SUBMIT_DELIVERABLE_TYPEHASH,
                freelancer,
                keccak256(bytes(URL)),
                keccak256(bytes(IPFS_CID)),
                keccak256(bytes(NOTES)),
                0,
                0,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));

        // Signed by an unauthorized key
        uint256 attackerPk = 0xBAD;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Escrow.InvalidSignature.selector);
        vm.prank(relayer);
        escrow.submitDeliverableWithSig(URL, IPFS_CID, NOTES, 0, deadline, signature);
    }

    // --- Milestone & All Funds Gasless Release Tests ---

    function test_Gasless_ReleaseMilestoneWithSig_Success() public {
        // Freelancer submits deliverable
        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = escrow.nonces(client);
        uint256 freelancerBalBefore = freelancer.balance;
        uint256 relayerBalBefore = relayer.balance;

        bytes32 structHash = keccak256(
            abi.encode(RELEASE_MILESTONE_TYPEHASH, client, 0, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(clientPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(relayer);
        escrow.releaseMilestoneWithSig(0, deadline, signature);

        assertEq(freelancer.balance, freelancerBalBefore + MILESTONE_1_AMOUNT);
        assertEq(escrow.nonces(client), 1);
        assertEq(relayer.balance, relayerBalBefore + RELAYER_FEE_PER_TX);

        // State transitions back to Funded because Milestone 1 is still pending
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));
    }

    function test_Gasless_ReleaseAllFundsWithSig_Success() public {
        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = escrow.nonces(client);
        uint256 freelancerBalBefore = freelancer.balance;
        uint256 relayerBalBefore = relayer.balance;
        uint256 clientBalBefore = client.balance;

        bytes32 structHash = keccak256(
            abi.encode(RELEASE_ALL_FUNDS_TYPEHASH, client, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(clientPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(relayer);
        escrow.releaseFundsWithSig(deadline, signature);

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(freelancer.balance, freelancerBalBefore + TOTAL_AMOUNT);
        assertEq(escrow.nonces(client), 1);
        assertEq(relayer.balance, relayerBalBefore + RELAYER_FEE_PER_TX);

        // Leftover relayer pool (TOTAL_RELAYER_POOL - RELAYER_FEE_PER_TX) swept back to client
        uint256 expectedClientRefund = TOTAL_RELAYER_POOL - RELAYER_FEE_PER_TX;
        assertEq(client.balance, clientBalBefore + expectedClientRefund);
        assertEq(address(escrow).balance, 0);

        // All milestones marked approved
        (,, bool m0Approved) = escrow.milestones(0);
        (,, bool m1Approved) = escrow.milestones(1);
        assertTrue(m0Approved);
        assertTrue(m1Approved);
    }

    // --- Dispute Gasless Raise & Resolve Tests ---

    function test_Gasless_RaiseDisputeWithSig_Success() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = escrow.nonces(client);
        uint256 relayerBalBefore = relayer.balance;

        bytes32 structHash = keccak256(
            abi.encode(RAISE_DISPUTE_TYPEHASH, client, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(clientPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(relayer);
        escrow.raiseDisputeWithSig(client, deadline, signature);

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Disputed));
        assertEq(escrow.nonces(client), 1);
        assertEq(relayer.balance, relayerBalBefore + RELAYER_FEE_PER_TX);
    }

    function test_Gasless_ResolveDisputeWithSig_Success() public {
        vm.prank(client);
        escrow.raiseDispute();

        uint256 clientRefund = 0.6 ether;
        uint256 freelancerPayout = 0.4 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = escrow.nonces(arbiter);
        uint256 relayerBalBefore = relayer.balance;
        uint256 clientBalBefore = client.balance;
        uint256 freelancerBalBefore = freelancer.balance;

        bytes32 structHash = keccak256(
            abi.encode(
                RESOLVE_DISPUTE_TYPEHASH,
                arbiter,
                clientRefund,
                freelancerPayout,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(arbiterPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(relayer);
        escrow.resolveDisputeWithSig(clientRefund, freelancerPayout, deadline, signature);

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(escrow.nonces(arbiter), 1);
        assertEq(relayer.balance, relayerBalBefore + RELAYER_FEE_PER_TX);
        assertEq(freelancer.balance, freelancerBalBefore + freelancerPayout);

        // Client gets dispute refund + leftover pool (TOTAL_RELAYER_POOL - RELAYER_FEE_PER_TX)
        uint256 expectedClientSweep = clientRefund + (TOTAL_RELAYER_POOL - RELAYER_FEE_PER_TX);
        assertEq(client.balance, clientBalBefore + expectedClientSweep);
        assertEq(address(escrow).balance, 0);
    }

    function test_Gasless_ResolveDisputeWithSig_RevertIf_Expired() public {
        vm.prank(client);
        escrow.raiseDispute();

        uint256 deadline = block.timestamp - 1; // Expired
        bytes32 structHash = keccak256(
            abi.encode(RESOLVE_DISPUTE_TYPEHASH, arbiter, 0.5 ether, 0.5 ether, 0, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(arbiterPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Escrow.SignatureExpired.selector);
        vm.prank(relayer);
        escrow.resolveDisputeWithSig(0.5 ether, 0.5 ether, deadline, signature);
    }

    function test_Gasless_ResolveDisputeWithSig_RevertIf_InvalidSigner() public {
        vm.prank(client);
        escrow.raiseDispute();

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(RESOLVE_DISPUTE_TYPEHASH, arbiter, 0.5 ether, 0.5 ether, 0, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));

        uint256 attackerPk = 0xBAD;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Escrow.InvalidSignature.selector);
        vm.prank(relayer);
        escrow.resolveDisputeWithSig(0.5 ether, 0.5 ether, deadline, signature);
    }
}