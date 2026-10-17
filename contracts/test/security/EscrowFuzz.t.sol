// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";

contract EscrowFuzzTest is Test {
    Escrow public escrow;

    address public client = makeAddr("client");
    address public freelancer = makeAddr("freelancer");
    address public arbiter = makeAddr("arbiter");
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 public constant PROTOCOL_FEE_BPS = 100; // 1%

    function setUp() public {}

    // Fuzz 1: Test valid deployment and funding across arbitrary non-zero amounts
    function testFuzz_Fund_ArbitraryEthAmount(uint96 amount) public {
        vm.assume(amount > 10000); // Prevent zero-fee rounding

        uint256 fee = (uint256(amount) * PROTOCOL_FEE_BPS) / 10000;
        uint256 totalRequired = uint256(amount) + fee;

        escrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(0),
            amount,
            PROTOCOL_FEE_BPS
        );

        vm.deal(client, totalRequired);

        vm.prank(client);
        escrow.fund{value: totalRequired}();

        // Mathematical invariants
        assertEq(address(escrow).balance, amount);
        assertEq(feeRecipient.balance, fee);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));
    }

    // Fuzz 2: Mathematical Invariant on Dispute Split
    function testFuzz_Dispute_ValidArbitrarySplit(uint96 amount, uint96 clientShare) public {
        vm.assume(amount > 10000);
        vm.assume(clientShare <= amount);

        uint256 fee = (uint256(amount) * PROTOCOL_FEE_BPS) / 10000;
        uint256 totalRequired = uint256(amount) + fee;

        uint256 refundAmount = uint256(clientShare);
        uint256 payoutAmount = uint256(amount) - refundAmount;

        escrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(0),
            amount,
            PROTOCOL_FEE_BPS
        );

        vm.deal(client, totalRequired);
        vm.prank(client);
        escrow.fund{value: totalRequired}();

        vm.prank(client);
        escrow.raiseDispute();

        uint256 clientInitialBalance = client.balance;
        uint256 freelancerInitialBalance = freelancer.balance;

        vm.prank(arbiter);
        escrow.resolveDispute(refundAmount, payoutAmount);

        // Strict post-conditions
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(address(escrow).balance, 0, "Vault balance must be zero after resolution");
        assertEq(client.balance, clientInitialBalance + refundAmount, "Client balance mismatch");
        assertEq(freelancer.balance, freelancerInitialBalance + payoutAmount, "Freelancer balance mismatch");
    }

    // Fuzz 3: Strict Revert on Invalid Split Sum (even 1 wei mismatch must fail)
    function testFuzz_RevertIf_DisputeSplitMismatch(uint96 amount, uint96 refundAmount, uint96 payoutAmount) public {
        vm.assume(amount > 10000);
        vm.assume(uint256(refundAmount) + uint256(payoutAmount) != uint256(amount));

        uint256 fee = (uint256(amount) * PROTOCOL_FEE_BPS) / 10000;
        uint256 totalRequired = uint256(amount) + fee;

        escrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(0),
            amount,
            PROTOCOL_FEE_BPS
        );

        vm.deal(client, totalRequired);
        vm.prank(client);
        escrow.fund{value: totalRequired}();

        vm.prank(client);
        escrow.raiseDispute();

        vm.expectRevert(Escrow.InvalidSplitAmount.selector);
        vm.prank(arbiter);
        escrow.resolveDispute(refundAmount, payoutAmount);
    }
}