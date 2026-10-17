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

    uint256 public constant ESCROW_AMOUNT = 1 ether;
    uint256 public constant FEE_BPS = 100;
    uint256 public constant TOTAL_REQUIRED = ESCROW_AMOUNT + ((ESCROW_AMOUNT * FEE_BPS) / 10000);

    bytes32 private constant SUBMIT_DELIVERABLE_TYPEHASH =
        keccak256("SubmitDeliverable(address freelancer,string deliverableUrl,uint256 nonce,uint256 deadline)");

    bytes32 private constant RESOLVE_DISPUTE_TYPEHASH =
        keccak256("ResolveDispute(address arbiter,uint256 clientRefund,uint256 freelancerPayout,uint256 nonce,uint256 deadline)");

    function setUp() public {
        client = vm.addr(clientPk);
        freelancer = vm.addr(freelancerPk);
        arbiter = vm.addr(arbiterPk);

        vm.deal(client, 10 ether);

        factory = new EscrowFactory(feeRecipient, FEE_BPS);

        escrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(0),
            ESCROW_AMOUNT,
            FEE_BPS
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

    function test_Gasless_SubmitDeliverableWithSig_Success() public {
        string memory url = "https://github.com/project/completed-work";
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = escrow.nonces(freelancer);

        bytes32 structHash = keccak256(
            abi.encode(SUBMIT_DELIVERABLE_TYPEHASH, freelancer, keccak256(bytes(url)), nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(freelancerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Relayer broadcasts the transaction
        address relayer = makeAddr("relayer");
        vm.prank(relayer);
        escrow.submitDeliverableWithSig(url, deadline, signature);

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Delivered));
        assertEq(escrow.deliverableUrl(), url);
        assertEq(escrow.nonces(freelancer), 1);
    }

    function test_Gasless_RevertIf_SignatureExpired() public {
        string memory url = "https://github.com/project/work";
        uint256 deadline = block.timestamp - 1; // Expired deadline

        bytes32 structHash = keccak256(
            abi.encode(SUBMIT_DELIVERABLE_TYPEHASH, freelancer, keccak256(bytes(url)), 0, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(freelancerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Escrow.SignatureExpired.selector);
        escrow.submitDeliverableWithSig(url, deadline, signature);
    }

    function test_Gasless_RevertIf_InvalidSigner() public {
        string memory url = "https://github.com/project/work";
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(SUBMIT_DELIVERABLE_TYPEHASH, freelancer, keccak256(bytes(url)), 0, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));

        // Signed by attacker instead of freelancer
        uint256 attackerPk = 0xBAD;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Escrow.InvalidSignature.selector);
        escrow.submitDeliverableWithSig(url, deadline, signature);
    }

    function test_Gasless_ResolveDisputeWithSig_Success() public {
        vm.prank(client);
        escrow.raiseDispute();

        uint256 clientRefund = 0.6 ether;
        uint256 freelancerPayout = 0.4 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = escrow.nonces(arbiter);

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

        address relayer = makeAddr("relayer");
        vm.prank(relayer);
        escrow.resolveDisputeWithSig(clientRefund, freelancerPayout, deadline, signature);

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(escrow.nonces(arbiter), 1);
        assertEq(address(escrow).balance, 0);
    }

    function test_Factory_SetFeeConfig_SuccessAndRevert() public {
        address newTreasury = makeAddr("newTreasury");

        // Factory owner updates config successfully
        factory.setFeeConfig(newTreasury, 200);
        assertEq(factory.feeRecipient(), newTreasury);
        assertEq(factory.feeBps(), 200);

        // Non-owner gets rejected
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert("Only factory owner");
        factory.setFeeConfig(attacker, 500);

        // Zero address fee recipient reverts
        vm.expectRevert("Zero address fee recipient");
        factory.setFeeConfig(address(0), 100);
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
        escrow.resolveDisputeWithSig(0.5 ether, 0.5 ether, deadline, signature);
    }

    function test_Factory_RevertIf_FeeBpsExceedsMaximum() public {
        // Ensure execution is dispatched by factory owner
        vm.prank(address(this));
        vm.expectRevert("Fee bps exceeds maximum");
        factory.setFeeConfig(feeRecipient, 1001);
    }
}