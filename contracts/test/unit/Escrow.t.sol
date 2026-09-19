// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 Token for testing token branches
contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Contract that reverts on receiving ETH to test TransferFailed branch
contract RejectEther {
    receive() external payable {
        revert("RejectEther: Cannot accept ETH");
    }
}

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

    function test_RevertIf_ClientZeroAddressOnDeploy() public {
        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(address(0), freelancer, arbiter, address(0), ESCROW_AMOUNT);
    }

    function test_RevertIf_FreelancerZeroAddressOnDeploy() public {
        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(client, address(0), arbiter, address(0), ESCROW_AMOUNT);
    }

    function test_RevertIf_ArbiterZeroAddressOnDeploy() public {
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

    function test_RevertIf_ZeroAmountOnDeploy() public {
        // Constructor must revert when amount is zero
        vm.expectRevert(Escrow.InvalidDepositAmount.selector);
        new Escrow(client, freelancer, arbiter, address(0), 0);
    }

    function test_RevertIf_DepositEtherWhenTokenConfigured() public {
        // Deploy escrow configured for an ERC20 token
        MockERC20 mockToken = new MockERC20();
        Escrow tokenEscrow = new Escrow(
            client,
            freelancer,
            arbiter,
            address(mockToken),
            ESCROW_AMOUNT
        );

        // Attempt to send native ETH when token is configured
        vm.expectRevert(Escrow.InvalidDepositAmount.selector);
        vm.prank(client);
        tokenEscrow.fund{value: 1 ether}();
    }

    function test_TokenEscrow_FullLifecycle_Success() public {
        // Deploy Mock ERC-20 and mint tokens to client
        MockERC20 mockToken = new MockERC20();
        mockToken.mint(client, ESCROW_AMOUNT);

        // Deploy token-configured Escrow contract
        Escrow tokenEscrow = new Escrow(
            client,
            freelancer,
            arbiter,
            address(mockToken),
            ESCROW_AMOUNT
        );

        // Client approves escrow to pull tokens and funds the escrow
        vm.startPrank(client);
        mockToken.approve(address(tokenEscrow), ESCROW_AMOUNT);
        tokenEscrow.fund();
        vm.stopPrank();

        assertEq(mockToken.balanceOf(address(tokenEscrow)), ESCROW_AMOUNT);
        assertEq(uint256(tokenEscrow.currentState()), uint256(Escrow.State.Funded));

        // Freelancer submits deliverable
        vm.prank(freelancer);
        tokenEscrow.submitDeliverable("https://github.com/project/token-work");

        // Client releases funds
        vm.prank(client);
        tokenEscrow.releaseFunds();

        // Assert final balances and state
        assertEq(uint256(tokenEscrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(mockToken.balanceOf(address(tokenEscrow)), 0);
        assertEq(mockToken.balanceOf(freelancer), ESCROW_AMOUNT);
    }

    function test_TokenEscrow_Dispute_ResolveSplit() public {
        MockERC20 mockToken = new MockERC20();
        mockToken.mint(client, ESCROW_AMOUNT);

        Escrow tokenEscrow = new Escrow(
            client,
            freelancer,
            arbiter,
            address(mockToken),
            ESCROW_AMOUNT
        );

        // Fund via ERC-20
        vm.startPrank(client);
        mockToken.approve(address(tokenEscrow), ESCROW_AMOUNT);
        tokenEscrow.fund();
        vm.stopPrank();

        // Raise dispute
        vm.prank(client);
        tokenEscrow.raiseDispute();

        // Arbiter splits token balance (0.5 tokens each)
        uint256 clientRefund = 0.5 ether;
        uint256 freelancerPayout = 0.5 ether;

        vm.prank(arbiter);
        tokenEscrow.resolveDispute(clientRefund, freelancerPayout);

        assertEq(uint256(tokenEscrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(mockToken.balanceOf(client), clientRefund);
        assertEq(mockToken.balanceOf(freelancer), freelancerPayout);
        assertEq(mockToken.balanceOf(address(tokenEscrow)), 0);
    }

    function test_Dispute_RaisedInDeliveredState() public {
        // Fund and deliver
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        vm.prank(freelancer);
        escrow.submitDeliverable("https://github.com/project/work");

        // Client raises dispute after delivery
        vm.prank(client);
        escrow.raiseDispute();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Disputed));
    }

    function test_RevertIf_DisputeRaisedInInvalidState() public {
        // Attempt to raise dispute while contract is still in State.Pending
        vm.expectRevert(
            abi.encodeWithSelector(
                Escrow.InvalidState.selector,
                Escrow.State.Delivered,
                Escrow.State.Pending
            )
        );

        vm.prank(client);
        escrow.raiseDispute();
    }

    function test_RevertIf_NativeEthTransferFails() public {
        RejectEther rejectingFreelancer = new RejectEther();

        // Deploy escrow where freelancer rejects ETH
        Escrow failEscrow = new Escrow(
            client,
            address(rejectingFreelancer),
            arbiter,
            address(0),
            ESCROW_AMOUNT
        );

        // Fund and deliver
        vm.prank(client);
        failEscrow.fund{value: ESCROW_AMOUNT}();

        vm.prank(address(rejectingFreelancer));
        failEscrow.submitDeliverable("https://github.com/project/rejected");

        // Expect TransferFailed revert when releasing funds to the rejecting contract
        vm.expectRevert(Escrow.TransferFailed.selector);
        vm.prank(client);
        failEscrow.releaseFunds();
    }

    function test_Dispute_RaisedByFreelancerInDeliveredState() public {
        // Step 1: Fund the contract
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        // Step 2: Freelancer submits deliverable
        vm.prank(freelancer);
        escrow.submitDeliverable("https://github.com/project/delivered-work");

        // Step 3: Freelancer raises dispute while in Delivered state
        vm.prank(freelancer);
        escrow.raiseDispute();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Disputed));
    }

    function test_RevertIf_NativeEthTransferFailsOnDispute() public {
        RejectEther rejectingClient = new RejectEther();

        // Deploy escrow where client rejects incoming ETH transfers
        Escrow failEscrow = new Escrow(
            address(rejectingClient),
            freelancer,
            arbiter,
            address(0),
            ESCROW_AMOUNT
        );

        // Fund escrow from rejectingClient address
        vm.deal(address(rejectingClient), 5 ether);
        vm.prank(address(rejectingClient));
        failEscrow.fund{value: ESCROW_AMOUNT}();

        // Raise dispute
        vm.prank(freelancer);
        failEscrow.raiseDispute();

        // Arbiter attempts to refund ETH to rejectingClient -> must revert
        vm.expectRevert(Escrow.TransferFailed.selector);
        vm.prank(arbiter);
        failEscrow.resolveDispute(ESCROW_AMOUNT, 0);
    }

    function test_RevertIf_DirectEthTransfer() public {
        // Contract has no receive() or fallback() function
        // Sending raw ETH directly without calldata must revert
        vm.deal(client, 1 ether);
        vm.prank(client);
        (bool success, ) = address(escrow).call{value: 1 ether}("");
        assertFalse(success);
    }

    function test_Deploy_SuccessWhenAllAddressesValid() public {
        // Explicitly verify the false-branch of all zero-address checks
        address validClient = makeAddr("validClient");
        address validFreelancer = makeAddr("validFreelancer");
        address validArbiter = makeAddr("validArbiter");

        Escrow validEscrow = new Escrow(
            validClient,
            validFreelancer,
            validArbiter,
            address(0),
            ESCROW_AMOUNT
        );

        assertEq(validEscrow.CLIENT(), validClient);
        assertEq(validEscrow.FREELANCER(), validFreelancer);
        assertEq(validEscrow.ARBITER(), validArbiter);
    }

    function test_RevertIf_FundNotInPendingState() public {
        // Fund once to move to State.Funded
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        // Attempting to fund again must revert with InvalidState
        vm.expectRevert(
            abi.encodeWithSelector(
                Escrow.InvalidState.selector,
                Escrow.State.Pending,
                Escrow.State.Funded
            )
        );

        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();
    }

    function test_RevertIf_NativeEthTransferFailsToFreelancerOnDispute() public {
        RejectEther rejectingFreelancer = new RejectEther();

        // Escrow where freelancer rejects ETH payouts
        Escrow failEscrow = new Escrow(
            client,
            address(rejectingFreelancer),
            arbiter,
            address(0),
            ESCROW_AMOUNT
        );

        vm.deal(client, 5 ether);
        vm.prank(client);
        failEscrow.fund{value: ESCROW_AMOUNT}();

        vm.prank(client);
        failEscrow.raiseDispute();

        // Arbiter refunds 0 to client, full amount to rejecting freelancer -> must revert
        vm.expectRevert(Escrow.TransferFailed.selector);
        vm.prank(arbiter);
        failEscrow.resolveDispute(0, ESCROW_AMOUNT);
    }

    function test_Constructor_ExplicitValidAddresses() public {
        // Explicitly triggers the non-reverting branch of the constructor in an isolated test
        address validClient = address(0xAAAA);
        address validFreelancer = address(0xBBBB);
        address validArbiter = address(0xCCCC);

        Escrow explicitEscrow = new Escrow(
            validClient,
            validFreelancer,
            validArbiter,
            address(0),
            1 ether
        );

        assertEq(explicitEscrow.CLIENT(), validClient);
        assertEq(explicitEscrow.FREELANCER(), validFreelancer);
        assertEq(explicitEscrow.ARBITER(), validArbiter);
    }
}