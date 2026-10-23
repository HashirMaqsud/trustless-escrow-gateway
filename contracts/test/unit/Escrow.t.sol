// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Mock ERC20 Token
contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock ERC20 Token that intentionally fails transfers
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

// Contract that reverts on receiving ETH
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

    uint256 public constant MILESTONE_1_AMOUNT = 0.4 ether;
    uint256 public constant MILESTONE_2_AMOUNT = 0.6 ether;
    uint256 public constant TOTAL_AMOUNT = 1 ether;
    uint256 public constant PROTOCOL_FEE_BPS = 100; // 1%
    uint256 public constant FEE_AMOUNT = (TOTAL_AMOUNT * PROTOCOL_FEE_BPS) / 10000; // 0.01 ether
    uint256 public constant RELAYER_FEE_PER_TX = 0.0001 ether;

    // Relayer Pool = (2 milestones * (3 revisions + 1) + 2 buffer) * 0.0001 = 10 * 0.0001 = 0.001 ether
    uint256 public constant TOTAL_RELAYER_POOL = RELAYER_FEE_PER_TX * 10;
    uint256 public constant TOTAL_REQUIRED = TOTAL_AMOUNT + FEE_AMOUNT + TOTAL_RELAYER_POOL;

    string public constant URL = "https://github.com/project/deliverable";
    string public constant IPFS_CID = "ipfs://bafybeicg2oxqozr75w3xjoxj4zsvygl4q752k4z626j5z4y25n7e4q4n4y";
    string public constant NOTES = "Deliverable draft submission notes";

    function setUp() public {
        vm.deal(client, 10 ether);

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
            PROTOCOL_FEE_BPS,
            RELAYER_FEE_PER_TX
        );
    }

    // --- Deployment & Initialization Tests ---

    function test_InitialState() public view {
        assertEq(escrow.CLIENT(), client);
        assertEq(escrow.FREELANCER(), freelancer);
        assertEq(escrow.ARBITER(), arbiter);
        assertEq(escrow.FEE_RECIPIENT(), feeRecipient);
        assertEq(address(escrow.TOKEN()), address(0));
        assertEq(escrow.TOTAL_AMOUNT(), TOTAL_AMOUNT);
        assertEq(escrow.PROTOCOL_FEE(), FEE_AMOUNT);
        assertEq(escrow.RELAYER_FEE_PER_TX(), RELAYER_FEE_PER_TX);
        assertEq(escrow.TOTAL_RELAYER_POOL(), TOTAL_RELAYER_POOL);
        assertEq(escrow.getMilestonesCount(), 2);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Pending));
    }

    function test_RevertIf_ZeroAddressOnDeploy() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Milestone 1";

        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(address(0), freelancer, arbiter, feeRecipient, address(0), amounts, descriptions, 100, 0.0001 ether);

        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(client, address(0), arbiter, feeRecipient, address(0), amounts, descriptions, 100, 0.0001 ether);

        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(client, freelancer, address(0), feeRecipient, address(0), amounts, descriptions, 100, 0.0001 ether);

        vm.expectRevert(Escrow.Unauthorized.selector);
        new Escrow(client, freelancer, arbiter, address(0), address(0), amounts, descriptions, 100, 0.0001 ether);
    }

    function test_RevertIf_InvalidMilestoneConfigOnDeploy() public {
        uint256[] memory amountsEmpty = new uint256[](0);
        string[] memory descriptionsEmpty = new string[](0);
        vm.expectRevert(Escrow.InvalidDepositAmount.selector);
        new Escrow(client, freelancer, arbiter, feeRecipient, address(0), amountsEmpty, descriptionsEmpty, 100, 0.0001 ether);

        uint256[] memory amountsZero = new uint256[](1);
        amountsZero[0] = 0;
        string[] memory descriptionsValid = new string[](1);
        descriptionsValid[0] = "Milestone 1";
        vm.expectRevert(Escrow.InvalidDepositAmount.selector);
        new Escrow(client, freelancer, arbiter, feeRecipient, address(0), amountsZero, descriptionsValid, 100, 0.0001 ether);
    }

    // --- Native ETH Funding Tests ---

    function test_Fund_NativeEth_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));
        assertEq(address(escrow).balance, TOTAL_AMOUNT + TOTAL_RELAYER_POOL);
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
        vm.expectRevert(Escrow.InvalidDepositAmount.selector);
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED - 1}();
    }

    function test_RevertIf_FundNotInPendingState() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidState.selector, Escrow.State.Pending, Escrow.State.Funded));
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();
    }

    // --- Hybrid Submissions & Revisions Cap Tests ---

    function test_SubmitDeliverable_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Delivered));
        assertEq(escrow.getSubmissionsCount(), 1);
        assertEq(escrow.milestoneSubmissionCount(0), 1);

        Escrow.Submission memory sub = escrow.getLatestSubmission();
        assertEq(sub.deliverableUrl, URL);
        assertEq(sub.ipfsHash, IPFS_CID);
        assertEq(sub.submissionNotes, NOTES);
        assertEq(sub.milestoneIndex, 0);
    }

    function test_RevertIf_SubmitExceedsRevisionsCap() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.startPrank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0); // Rev 1
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0); // Rev 2
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0); // Rev 3

        // 4th Revision must revert
        vm.expectRevert(Escrow.RevisionsLimitExceeded.selector);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);
        vm.stopPrank();
    }

    function test_RevertIf_SubmitInvalidMilestoneIndex() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.expectRevert(Escrow.InvalidMilestoneIndex.selector);
        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 99);
    }

    // --- Tranches / Milestone Release Tests ---

    function test_ReleaseMilestone_Sequential_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        // Submit and Release Milestone 0 (0.4 ETH)
        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        uint256 freelancerBalBefore = freelancer.balance;
        vm.prank(client);
        escrow.releaseMilestone(0);

        assertEq(freelancer.balance, freelancerBalBefore + MILESTONE_1_AMOUNT);
        assertEq(escrow.totalReleased(), MILESTONE_1_AMOUNT);

        // State transitions back to Funded so freelancer cannot drain remaining balance
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));

        // Submit and Release Milestone 1 (0.6 ETH)
        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 1);

        uint256 clientBalBeforeFinalRelease = client.balance;

        vm.prank(client);
        escrow.releaseMilestone(1);

        assertEq(freelancer.balance, freelancerBalBefore + TOTAL_AMOUNT);
        assertEq(escrow.totalReleased(), TOTAL_AMOUNT);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));

        // Unused relayer pool is refunded to client
        assertEq(client.balance, clientBalBeforeFinalRelease + TOTAL_RELAYER_POOL);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertIf_ReleaseMilestoneAlreadyApproved() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        vm.startPrank(client);
        escrow.releaseMilestone(0);

        vm.expectRevert(Escrow.MilestoneAlreadyApproved.selector);
        escrow.releaseMilestone(0);
        vm.stopPrank();
    }

    function test_ReleaseAllFunds_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        uint256 freelancerBalBefore = freelancer.balance;
        uint256 clientBalBefore = client.balance;

        vm.prank(client);
        escrow.releaseFunds();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(freelancer.balance, freelancerBalBefore + TOTAL_AMOUNT);
        assertEq(escrow.totalReleased(), TOTAL_AMOUNT);

        // Unused pool swept back to client
        assertEq(client.balance, clientBalBefore + TOTAL_RELAYER_POOL);
        assertEq(address(escrow).balance, 0);

        // Check all milestones are marked approved
        (,, bool m0Approved) = escrow.milestones(0);
        (,, bool m1Approved) = escrow.milestones(1);
        assertTrue(m0Approved);
        assertTrue(m1Approved);
    }

    // --- Dispute Lifecycle Tests ---

    function test_Dispute_ResolveSplit_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        vm.prank(client);
        escrow.raiseDispute();
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Disputed));

        uint256 clientBalBefore = client.balance;
        uint256 freelancerBalBefore = freelancer.balance;

        uint256 clientRefund = 0.4 ether;
        uint256 freelancerPayout = 0.6 ether;

        vm.prank(arbiter);
        escrow.resolveDispute(clientRefund, freelancerPayout);

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        // Client gets refund + unused relayer pool
        assertEq(client.balance, clientBalBefore + clientRefund + TOTAL_RELAYER_POOL);
        assertEq(freelancer.balance, freelancerBalBefore + freelancerPayout);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertIf_DisputeSplitMismatch() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(client);
        escrow.raiseDispute();

        // Under-allocation (0.4 + 0.4 = 0.8 != 1.0) must revert
        vm.expectRevert(Escrow.InvalidSplitAmount.selector);
        vm.prank(arbiter);
        escrow.resolveDispute(0.4 ether, 0.4 ether);

        // Over-allocation (0.6 + 0.5 = 1.1 != 1.0) must revert
        vm.expectRevert(Escrow.InvalidSplitAmount.selector);
        vm.prank(arbiter);
        escrow.resolveDispute(0.6 ether, 0.5 ether);
    }

    // --- Emergency Timelocks Tests ---

    function test_ClaimInactivityRefund_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days);

        uint256 clientBalBefore = client.balance;
        uint256 vaultRemaining = address(escrow).balance;

        vm.prank(client);
        escrow.claimInactivityRefund();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(client.balance, clientBalBefore + vaultRemaining);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertIf_ClaimInactivityRefundBeforeTimelock() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.warp(block.timestamp + 29 days);

        vm.expectRevert(Escrow.TimelockNotExpired.selector);
        vm.prank(client);
        escrow.claimInactivityRefund();
    }

    function test_RevertIf_ClaimInactivityRefundWhenSubmissionsExist() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        vm.warp(block.timestamp + 31 days);

        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidState.selector, Escrow.State.Funded, Escrow.State.Delivered));
        vm.prank(client);
        escrow.claimInactivityRefund();
    }

    function test_ClaimReviewTimeoutPayout_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        // Fast forward 14 days review timeout
        vm.warp(block.timestamp + 14 days);

        uint256 freelancerBalBefore = freelancer.balance;
        uint256 clientBalBefore = client.balance;

        vm.prank(freelancer);
        escrow.claimReviewTimeoutPayout();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(freelancer.balance, freelancerBalBefore + TOTAL_AMOUNT);
        // Client receives leftover pool back
        assertEq(client.balance, clientBalBefore + TOTAL_RELAYER_POOL);
        assertEq(address(escrow).balance, 0);

        // Check all milestones are marked approved
        (,, bool m0Approved) = escrow.milestones(0);
        (,, bool m1Approved) = escrow.milestones(1);
        assertTrue(m0Approved);
        assertTrue(m1Approved);
    }

    function test_RevertIf_ClaimReviewTimeoutPayoutBeforeTimelock() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        vm.warp(block.timestamp + 13 days);

        vm.expectRevert(Escrow.TimelockNotExpired.selector);
        vm.prank(freelancer);
        escrow.claimReviewTimeoutPayout();
    }

    // --- ERC-20 Token Integration Tests ---

    function test_TokenEscrow_FullTrancheLifecycle() public {
        MockERC20 token = new MockERC20();
        token.mint(client, TOTAL_REQUIRED);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = MILESTONE_1_AMOUNT;
        amounts[1] = MILESTONE_2_AMOUNT;

        string[] memory descriptions = new string[](2);
        descriptions[0] = "Milestone 1";
        descriptions[1] = "Milestone 2";

        Escrow tokenEscrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(token),
            amounts,
            descriptions,
            PROTOCOL_FEE_BPS,
            RELAYER_FEE_PER_TX
        );

        vm.startPrank(client);
        token.approve(address(tokenEscrow), TOTAL_REQUIRED);
        tokenEscrow.fund();
        vm.stopPrank();

        assertEq(token.balanceOf(address(tokenEscrow)), TOTAL_AMOUNT + TOTAL_RELAYER_POOL);
        assertEq(token.balanceOf(feeRecipient), FEE_AMOUNT);

        // Submit and Release Milestone 0
        vm.prank(freelancer);
        tokenEscrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        vm.prank(client);
        tokenEscrow.releaseMilestone(0);
        assertEq(token.balanceOf(freelancer), MILESTONE_1_AMOUNT);
        assertEq(uint256(tokenEscrow.currentState()), uint256(Escrow.State.Funded));

        // Submit and Release Milestone 1
        vm.prank(freelancer);
        tokenEscrow.submitDeliverable(URL, IPFS_CID, NOTES, 1);

        uint256 clientTokenBalBeforeFinal = token.balanceOf(client);

        vm.prank(client);
        tokenEscrow.releaseMilestone(1);
        assertEq(token.balanceOf(freelancer), TOTAL_AMOUNT);
        assertEq(uint256(tokenEscrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(token.balanceOf(client), clientTokenBalBeforeFinal + TOTAL_RELAYER_POOL);
        assertEq(token.balanceOf(address(tokenEscrow)), 0);
    }
}