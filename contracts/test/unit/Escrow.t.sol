// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";

contract EscrowUnitTest is Test {
    Escrow public escrow;

    // Test accounts
    address public client = makeAddr("client");
    address public freelancer = makeAddr("freelancer");
    address public arbiter = makeAddr("arbiter");

    uint256 public constant ESCROW_AMOUNT = 1 ether;

    function setUp() public {
        vm.deal(client, 10 ether);

        escrow = new Escrow(
            client,
            freelancer,
            arbiter,
            address(0),
            ESCROW_AMOUNT
        );
    }

    function test_InitialState() public view {
        assertEq(escrow.CLIENT(), client);
        assertEq(escrow.FREELANCER(), freelancer);
        assertEq(escrow.ARBITER(), arbiter);
        assertEq(address(escrow.TOKEN()), address(0));
        assertEq(escrow.AMOUNT(), ESCROW_AMOUNT);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Pending));
    }

    function test_RevertIf_ZeroAddressOnDeploy() public {
        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(address(0), freelancer, arbiter, address(0), ESCROW_AMOUNT);

        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(client, address(0), arbiter, address(0), ESCROW_AMOUNT);

        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(client, freelancer, address(0), address(0), ESCROW_AMOUNT);
    }

    function test_Fund_NativeEth_Success() public {
        vm.prank(client);

        escrow.fund{value: ESCROW_AMOUNT}();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));
        assertEq(address(escrow).balance, ESCROW_AMOUNT);
        assertEq(client.balance, 10 ether - ESCROW_AMOUNT);
    }

    function test_RevertIf_FundNotClient() public {
        // Deal funds to a random attacker
        address attacker = makeAddr("attacker");
        vm.deal(attacker, 5 ether);

        // Expect revert because msg.sender is not the client
        vm.expectRevert(Escrow.Unauthorized.selector);

        vm.prank(attacker);
        escrow.fund{value: ESCROW_AMOUNT}();
    }

    function test_RevertIf_FundWrongAmount() public {
        uint256 incorrectAmount = 0.5 ether;

        // Expect revert due to incorrect deposit value
        vm.expectRevert(Escrow.InvalidDepositAmount.selector);

        vm.prank(client);
        escrow.fund{value: incorrectAmount}();
    }

    function test_SubmitDeliverable_Success() public {
        // Step 1: Fund the contract first
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        // Step 2: Freelancer submits proof of work
        string memory sampleUrl = "https://github.com/project/deliverable";

        vm.prank(freelancer);
        escrow.submitDeliverable(sampleUrl);

        // Assertions: Verify stored URL and updated state
        assertEq(escrow.deliverableUrl(), sampleUrl);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Delivered));
    }

    function test_RevertIf_SubmitNotFreelancer() public {
        // Fund the contract
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        // Client attempts to submit deliverable instead of freelancer
        vm.expectRevert(Escrow.Unauthorized.selector);

        vm.prank(client);
        escrow.submitDeliverable("https://invalid-submission.com");
    }

    function test_ReleaseFunds_Success() public {
        // Step 1: Fund the contract
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        // Step 2: Freelancer submits deliverable
        vm.prank(freelancer);
        escrow.submitDeliverable("https://github.com/project/deliverable");

        // Record initial freelancer balance before release
        uint256 freelancerInitialBalance = freelancer.balance;

        // Step 3: Client releases funds
        vm.prank(client);
        escrow.releaseFunds();

        // Assertions: State, contract balance, and freelancer payout
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(address(escrow).balance, 0);
        assertEq(freelancer.balance, freelancerInitialBalance + ESCROW_AMOUNT);
    }

    function test_RevertIf_ReleaseNotClient() public {
        // Step 1: Fund the contract
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        // Step 2: Freelancer submits deliverable
        vm.prank(freelancer);
        escrow.submitDeliverable("https://github.com/project/deliverable");

        // Step 3: Freelancer attempts to release funds directly
        vm.expectRevert(Escrow.Unauthorized.selector);

        vm.prank(freelancer);
        escrow.releaseFunds();
    }

    function test_RevertIf_ReleaseBeforeDelivery() public {
        // Step 1: Fund the contract (Current state: Funded)
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        // Step 2: Client attempts to release funds before freelancer delivers
        // Expect revert due to invalid state transition
        vm.expectRevert(
            abi.encodeWithSelector(
                Escrow.InvalidState.selector,
                Escrow.State.Delivered,
                Escrow.State.Funded
            )
        );

        vm.prank(client);
        escrow.releaseFunds();
    }

    function test_RevertIf_SubmitNotInFundedState() public {
        // Contract is in State.Pending (not funded yet)
        // Expect revert because work cannot be submitted before funding
        vm.expectRevert(
            abi.encodeWithSelector(
                Escrow.InvalidState.selector,
                Escrow.State.Funded,
                Escrow.State.Pending
            )
        );

        vm.prank(freelancer);
        escrow.submitDeliverable("https://github.com/project/premature-work");
    }

    function test_Dispute_FullLifecycleAndSplit() public {
        // Step 1: Fund the contract
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        // Step 2: Client raises dispute
        vm.prank(client);
        escrow.raiseDispute();
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Disputed));

        // Record balances prior to resolution
        uint256 clientInitialBalance = client.balance;
        uint256 freelancerInitialBalance = freelancer.balance;

        // Step 3: Arbiter resolves dispute with a 50/50 split
        uint256 clientRefund = 0.5 ether;
        uint256 freelancerPayout = 0.5 ether;

        vm.prank(arbiter);
        escrow.resolveDispute(clientRefund, freelancerPayout);

        // Assertions: Final state, vault balance, and split payouts
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(address(escrow).balance, 0);
        assertEq(client.balance, clientInitialBalance + clientRefund);
        assertEq(freelancer.balance, freelancerInitialBalance + freelancerPayout);
    }

    function test_RevertIf_DisputeRaisedByUnauthorized() public {
        // Fund the contract
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        // An external attacker attempts to raise dispute
        address attacker = makeAddr("attacker");
        vm.expectRevert(Escrow.Unauthorized.selector);

        vm.prank(attacker);
        escrow.raiseDispute();
    }

    function test_RevertIf_DisputeSplitMismatch() public {
        // Fund and raise dispute
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        vm.prank(freelancer);
        escrow.raiseDispute();

        // Arbiter attempts to resolve with an invalid sum (0.4 ETH + 0.4 ETH != 1 ETH)
        uint256 invalidRefund = 0.4 ether;
        uint256 invalidPayout = 0.4 ether;

        vm.expectRevert(Escrow.InvalidSplitAmount.selector);

        vm.prank(arbiter);
        escrow.resolveDispute(invalidRefund, invalidPayout);
    }

    function test_Dispute_RaisedByFreelancer() public {
        // Fund the contract
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        // Freelancer raises dispute
        vm.prank(freelancer);
        escrow.raiseDispute();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Disputed));
    }

    function test_Dispute_ResolveFullRefundToClient() public {
        // Fund and raise dispute
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        vm.prank(client);
        escrow.raiseDispute();

        uint256 clientInitialBalance = client.balance;
        uint256 freelancerInitialBalance = freelancer.balance;

        // Arbiter gives 100% refund to client, 0 to freelancer
        vm.prank(arbiter);
        escrow.resolveDispute(ESCROW_AMOUNT, 0);

        assertEq(client.balance, clientInitialBalance + ESCROW_AMOUNT);
        assertEq(freelancer.balance, freelancerInitialBalance);
    }

    function test_Dispute_ResolveFullPayoutToFreelancer() public {
        // Fund and raise dispute
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        vm.prank(client);
        escrow.raiseDispute();

        uint256 clientInitialBalance = client.balance;
        uint256 freelancerInitialBalance = freelancer.balance;

        // Arbiter gives 0 to client, 100% to freelancer
        vm.prank(arbiter);
        escrow.resolveDispute(0, ESCROW_AMOUNT);

        assertEq(client.balance, clientInitialBalance);
        assertEq(freelancer.balance, freelancerInitialBalance + ESCROW_AMOUNT);
    }
}