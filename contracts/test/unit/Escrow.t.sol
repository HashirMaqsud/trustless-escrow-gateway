// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Mock ERC20 Token for testing token branches
contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock ERC20 Token that intentionally fails transfers to test revert branches
contract FailingMockERC20 is ERC20 {
    bool public shouldFail;

    constructor() ERC20("FailToken", "FTK") {
        _mint(msg.sender, 1000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setShouldFail(bool _fail) external {
        shouldFail = _fail;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (shouldFail) {
            return false;
        }
        return super.transfer(to, amount);
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
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 public constant ESCROW_AMOUNT = 1 ether;
    uint256 public constant PROTOCOL_FEE_BPS = 100; // 1%
    uint256 public constant FEE_AMOUNT = (ESCROW_AMOUNT * PROTOCOL_FEE_BPS) / 10000;
    uint256 public constant TOTAL_REQUIRED = ESCROW_AMOUNT + FEE_AMOUNT;

    function setUp() public {
        vm.deal(client, 10 ether);

        escrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(0),
            ESCROW_AMOUNT,
            PROTOCOL_FEE_BPS
        );
    }

    // --- Deployment Tests ---

    function test_InitialState() public view {
        assertEq(escrow.CLIENT(), client);
        assertEq(escrow.FREELANCER(), freelancer);
        assertEq(escrow.ARBITER(), arbiter);
        assertEq(escrow.FEE_RECIPIENT(), feeRecipient);
        assertEq(address(escrow.TOKEN()), address(0));
        assertEq(escrow.AMOUNT(), ESCROW_AMOUNT);
        assertEq(escrow.FEE_AMOUNT(), FEE_AMOUNT);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Pending));
    }

    function test_RevertIf_ClientZeroAddressOnDeploy() public {
        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(address(0), freelancer, arbiter, feeRecipient, address(0), ESCROW_AMOUNT, PROTOCOL_FEE_BPS);
    }

    function test_RevertIf_FreelancerZeroAddressOnDeploy() public {
        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(client, address(0), arbiter, feeRecipient, address(0), ESCROW_AMOUNT, PROTOCOL_FEE_BPS);
    }

    function test_RevertIf_ArbiterZeroAddressOnDeploy() public {
        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(client, freelancer, address(0), feeRecipient, address(0), ESCROW_AMOUNT, PROTOCOL_FEE_BPS);
    }

    function test_RevertIf_FeeRecipientZeroAddressOnDeploy() public {
        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(client, freelancer, arbiter, address(0), address(0), ESCROW_AMOUNT, PROTOCOL_FEE_BPS);
    }

    function test_RevertIf_ZeroAmountOnDeploy() public {
        vm.expectRevert(Escrow.InvalidDepositAmount.selector);
        new Escrow(client, freelancer, arbiter, feeRecipient, address(0), 0, PROTOCOL_FEE_BPS);
    }

    // --- Native ETH Funding Tests ---

    function test_Fund_NativeEth_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));
        assertEq(address(escrow).balance, ESCROW_AMOUNT);
        assertEq(feeRecipient.balance, FEE_AMOUNT);
        assertEq(client.balance, 10 ether - TOTAL_REQUIRED);
    }

    function test_RevertIf_FundNotClient() public {
        address attacker = makeAddr("attacker");
        vm.deal(attacker, 5 ether);

        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(attacker);
        escrow.fund{value: TOTAL_REQUIRED}();
    }

    function test_RevertIf_FundWrongAmount() public {
        uint256 incorrectAmount = 0.5 ether;

        vm.expectRevert(Escrow.InvalidDepositAmount.selector);
        vm.prank(client);
        escrow.fund{value: incorrectAmount}();
    }

    function test_RevertIf_FundNotInPendingState() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.expectRevert(
            abi.encodeWithSelector(
                Escrow.InvalidState.selector,
                Escrow.State.Pending,
                Escrow.State.Funded
            )
        );
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();
    }

    function test_RevertIf_DirectEthTransfer() public {
        vm.deal(client, 1 ether);
        vm.prank(client);
        (bool success, ) = address(escrow).call{value: 1 ether}("");
        assertFalse(success);
    }

    // --- Deliverable Submission Tests ---

    function test_SubmitDeliverable_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        string memory sampleUrl = "https://github.com/project/deliverable";
        vm.prank(freelancer);
        escrow.submitDeliverable(sampleUrl);

        assertEq(escrow.deliverableUrl(), sampleUrl);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Delivered));
    }

    function test_RevertIf_SubmitNotFreelancer() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(client);
        escrow.submitDeliverable("https://invalid-submission.com");
    }

    function test_RevertIf_SubmitNotInFundedState() public {
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

    // --- Fund Release Tests ---

    function test_ReleaseFunds_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable("https://github.com/project/deliverable");

        uint256 freelancerInitialBalance = freelancer.balance;

        vm.prank(client);
        escrow.releaseFunds();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(address(escrow).balance, 0);
        assertEq(freelancer.balance, freelancerInitialBalance + ESCROW_AMOUNT);
    }

    function test_RevertIf_ReleaseNotClient() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable("https://github.com/project/deliverable");

        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(freelancer);
        escrow.releaseFunds();
    }

    function test_RevertIf_ReleaseBeforeDelivery() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

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

    function test_RevertIf_NativeEthTransferFailsOnRelease() public {
        RejectEther rejectingFreelancer = new RejectEther();

        Escrow failEscrow = new Escrow(
            client,
            address(rejectingFreelancer),
            arbiter,
            feeRecipient,
            address(0),
            ESCROW_AMOUNT,
            PROTOCOL_FEE_BPS
        );

        vm.prank(client);
        failEscrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(address(rejectingFreelancer));
        failEscrow.submitDeliverable("https://github.com/project/rejected");

        vm.expectRevert(Escrow.TransferFailed.selector);
        vm.prank(client);
        failEscrow.releaseFunds();
    }

    // --- Dispute Tests ---

    function test_Dispute_RaisedByFreelancer() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.raiseDispute();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Disputed));
    }

    function test_Dispute_RaisedInDeliveredState() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable("https://github.com/project/work");

        vm.prank(client);
        escrow.raiseDispute();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Disputed));
    }

    function test_RevertIf_DisputeRaisedByUnauthorized() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        address attacker = makeAddr("attacker");
        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(attacker);
        escrow.raiseDispute();
    }

    function test_RevertIf_DisputeRaisedInInvalidState() public {
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

    function test_Dispute_FullLifecycleAndSplit() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(client);
        escrow.raiseDispute();

        uint256 clientInitialBalance = client.balance;
        uint256 freelancerInitialBalance = freelancer.balance;

        uint256 clientRefund = 0.5 ether;
        uint256 freelancerPayout = 0.5 ether;

        vm.prank(arbiter);
        escrow.resolveDispute(clientRefund, freelancerPayout);

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(address(escrow).balance, 0);
        assertEq(client.balance, clientInitialBalance + clientRefund);
        assertEq(freelancer.balance, freelancerInitialBalance + freelancerPayout);
    }

    function test_Dispute_ResolveFullRefundToClient() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(client);
        escrow.raiseDispute();

        uint256 clientInitialBalance = client.balance;
        uint256 freelancerInitialBalance = freelancer.balance;

        vm.prank(arbiter);
        escrow.resolveDispute(ESCROW_AMOUNT, 0);

        assertEq(client.balance, clientInitialBalance + ESCROW_AMOUNT);
        assertEq(freelancer.balance, freelancerInitialBalance);
    }

    function test_Dispute_ResolveFullPayoutToFreelancer() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(client);
        escrow.raiseDispute();

        uint256 clientInitialBalance = client.balance;
        uint256 freelancerInitialBalance = freelancer.balance;

        vm.prank(arbiter);
        escrow.resolveDispute(0, ESCROW_AMOUNT);

        assertEq(client.balance, clientInitialBalance);
        assertEq(freelancer.balance, freelancerInitialBalance + ESCROW_AMOUNT);
    }

    function test_RevertIf_DisputeSplitMismatch() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.raiseDispute();

        uint256 invalidRefund = 0.4 ether;
        uint256 invalidPayout = 0.4 ether;

        vm.expectRevert(Escrow.InvalidSplitAmount.selector);
        vm.prank(arbiter);
        escrow.resolveDispute(invalidRefund, invalidPayout);
    }

    function test_RevertIf_NativeEthTransferFailsOnDispute() public {
        RejectEther rejectingClient = new RejectEther();

        Escrow failEscrow = new Escrow(
            address(rejectingClient),
            freelancer,
            arbiter,
            feeRecipient,
            address(0),
            ESCROW_AMOUNT,
            PROTOCOL_FEE_BPS
        );

        vm.deal(address(rejectingClient), 5 ether);
        vm.prank(address(rejectingClient));
        failEscrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        failEscrow.raiseDispute();

        vm.expectRevert(Escrow.TransferFailed.selector);
        vm.prank(arbiter);
        failEscrow.resolveDispute(ESCROW_AMOUNT, 0);
    }

    // --- ERC-20 Token Integration Tests ---

    function test_RevertIf_DepositEtherWhenTokenConfigured() public {
        MockERC20 mockToken = new MockERC20();
        Escrow tokenEscrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(mockToken),
            ESCROW_AMOUNT,
            PROTOCOL_FEE_BPS
        );

        vm.expectRevert(Escrow.InvalidDepositAmount.selector);
        vm.prank(client);
        tokenEscrow.fund{value: 1 ether}();
    }

    function test_TokenEscrow_FullLifecycle_Success() public {
        MockERC20 mockToken = new MockERC20();
        mockToken.mint(client, TOTAL_REQUIRED);

        Escrow tokenEscrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(mockToken),
            ESCROW_AMOUNT,
            PROTOCOL_FEE_BPS
        );

        vm.startPrank(client);
        mockToken.approve(address(tokenEscrow), TOTAL_REQUIRED);
        tokenEscrow.fund();
        vm.stopPrank();

        assertEq(mockToken.balanceOf(address(tokenEscrow)), ESCROW_AMOUNT);
        assertEq(mockToken.balanceOf(feeRecipient), FEE_AMOUNT);
        assertEq(uint256(tokenEscrow.currentState()), uint256(Escrow.State.Funded));

        vm.prank(freelancer);
        tokenEscrow.submitDeliverable("https://github.com/project/token-work");

        vm.prank(client);
        tokenEscrow.releaseFunds();

        assertEq(uint256(tokenEscrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(mockToken.balanceOf(address(tokenEscrow)), 0);
        assertEq(mockToken.balanceOf(freelancer), ESCROW_AMOUNT);
    }

    function test_TokenEscrow_Dispute_ResolveSplit() public {
        MockERC20 mockToken = new MockERC20();
        mockToken.mint(client, TOTAL_REQUIRED);

        Escrow tokenEscrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(mockToken),
            ESCROW_AMOUNT,
            PROTOCOL_FEE_BPS
        );

        vm.startPrank(client);
        mockToken.approve(address(tokenEscrow), TOTAL_REQUIRED);
        tokenEscrow.fund();
        vm.stopPrank();

        vm.prank(client);
        tokenEscrow.raiseDispute();

        uint256 clientRefund = 0.5 ether;
        uint256 freelancerPayout = 0.5 ether;

        vm.prank(arbiter);
        tokenEscrow.resolveDispute(clientRefund, freelancerPayout);

        assertEq(uint256(tokenEscrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(mockToken.balanceOf(client), clientRefund);
        assertEq(mockToken.balanceOf(freelancer), freelancerPayout);
        assertEq(mockToken.balanceOf(address(tokenEscrow)), 0);
    }

    function test_RevertIf_TokenTransferFailsOnRelease() public {
        FailingMockERC20 failingToken = new FailingMockERC20();
        
        Escrow failTokenEscrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(failingToken),
            ESCROW_AMOUNT,
            0
        );

        // Mint tokens to client
        failingToken.mint(client, ESCROW_AMOUNT);

        // Approve and fund
        vm.startPrank(client);
        failingToken.approve(address(failTokenEscrow), ESCROW_AMOUNT);
        failTokenEscrow.fund();
        vm.stopPrank();

        // Deliver work
        vm.prank(freelancer);
        failTokenEscrow.submitDeliverable("https://github.com/project/work");

        // Enable transfer failure on the mock token
        failingToken.setShouldFail(true);

        // SafeERC20 throws SafeERC20FailedOperation when transfer returns false
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20.SafeERC20FailedOperation.selector,
                address(failingToken)
            )
        );
        vm.prank(client);
        failTokenEscrow.releaseFunds();
    }
}