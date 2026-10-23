// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Mock ERC20 Token with customizable decimals
contract MockERC20 is ERC20 {
    uint8 private _customDecimals;

    constructor() ERC20("MockToken", "MTK") {
        _customDecimals = 18;
        _mint(msg.sender, 100000 ether);
    }

    function setDecimals(uint8 dec) external {
        _customDecimals = dec;
    }

    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Token with no decimals function to trigger try/catch fallback branch
contract NoDecimalsToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address to, uint256 amt) external returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }
}

// Contract that strictly reverts on receiving ETH
contract RejectEther {
    receive() external payable {
        revert("RejectEther: Cannot accept ETH");
    }
}

contract EscrowUnitTest is Test {
    Escrow public escrow;

    uint256 internal clientPk = 0xA11CE;
    uint256 internal freelancerPk = 0xB0B;
    uint256 internal arbiterPk = 0xCAFE;

    address public client;
    address public freelancer;
    address public arbiter;
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 public constant MILESTONE_1_AMOUNT = 0.4 ether;
    uint256 public constant MILESTONE_2_AMOUNT = 0.6 ether;
    uint256 public constant TOTAL_AMOUNT = 1 ether;
    uint256 public constant PROTOCOL_FEE_BPS = 100; // 1%
    uint256 public constant FEE_AMOUNT = (TOTAL_AMOUNT * PROTOCOL_FEE_BPS) / 10000;
    uint256 public constant RELAYER_FEE_PER_TX = 0.0001 ether;
    uint256 public constant TOTAL_RELAYER_POOL = RELAYER_FEE_PER_TX * 10;
    uint256 public constant TOTAL_REQUIRED = TOTAL_AMOUNT + FEE_AMOUNT + TOTAL_RELAYER_POOL;

    string public constant URL = "https://github.com/project/deliverable";
    string public constant IPFS_CID = "ipfs://bafybeicg2oxqozr75w3xjoxj4zsvygl4q752k4z626j5z4y25n7e4q4n4y";
    string public constant NOTES = "Deliverable draft submission notes";

    bytes32 private constant SUBMIT_DELIVERABLE_TYPEHASH =
        keccak256("SubmitDeliverable(address freelancer,string deliverableUrl,string ipfsHash,string submissionNotes,uint256 milestoneIndex,uint256 nonce,uint256 deadline)");

    function setUp() public {
        client = vm.addr(clientPk);
        freelancer = vm.addr(freelancerPk);
        arbiter = vm.addr(arbiterPk);

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

    function test_Fund_NativeEth_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));
        assertEq(address(escrow).balance, TOTAL_AMOUNT + TOTAL_RELAYER_POOL);
        assertEq(feeRecipient.balance, FEE_AMOUNT);
        assertEq(client.balance, 10 ether - TOTAL_REQUIRED);
    }

    function test_Fund_ZeroProtocolFee() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Milestone 1";

        Escrow zeroFeeEscrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(0),
            amounts,
            descriptions,
            0,
            RELAYER_FEE_PER_TX
        );

        uint256 required = 1 ether + zeroFeeEscrow.TOTAL_RELAYER_POOL();
        vm.prank(client);
        zeroFeeEscrow.fund{value: required}();

        assertEq(uint256(zeroFeeEscrow.currentState()), uint256(Escrow.State.Funded));
        assertEq(zeroFeeEscrow.PROTOCOL_FEE(), 0);
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

        Escrow.Submission memory subByIndex = escrow.getSubmission(0);
        assertEq(subByIndex.deliverableUrl, URL);
    }

    function test_RevertIf_SubmitDeliverable_NotFreelancer() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(client);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);
    }

    function test_RevertIf_SubmitExceedsRevisionsCap() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.startPrank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

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

    function test_ReleaseMilestone_Sequential_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        uint256 freelancerBalBefore = freelancer.balance;
        vm.prank(client);
        escrow.releaseMilestone(0);

        assertEq(freelancer.balance, freelancerBalBefore + MILESTONE_1_AMOUNT);
        assertEq(escrow.totalReleased(), MILESTONE_1_AMOUNT);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));

        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 1);

        uint256 clientBalBeforeFinalRelease = client.balance;

        vm.prank(client);
        escrow.releaseMilestone(1);

        assertEq(freelancer.balance, freelancerBalBefore + TOTAL_AMOUNT);
        assertEq(escrow.totalReleased(), TOTAL_AMOUNT);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(client.balance, clientBalBeforeFinalRelease + TOTAL_RELAYER_POOL);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertIf_ReleaseMilestone_NotClient() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(freelancer);
        escrow.releaseMilestone(0);
    }

    function test_RevertIf_ReleaseMilestone_InvalidIndex() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.expectRevert(Escrow.InvalidMilestoneIndex.selector);
        vm.prank(client);
        escrow.releaseMilestone(99);
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
        assertEq(client.balance, clientBalBefore + TOTAL_RELAYER_POOL);
        assertEq(address(escrow).balance, 0);

        (,, bool m0Approved) = escrow.milestones(0);
        (,, bool m1Approved) = escrow.milestones(1);
        assertTrue(m0Approved);
        assertTrue(m1Approved);
    }

    function test_RevertIf_ReleaseFunds_NotClient() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(freelancer);
        escrow.releaseFunds();
    }

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
        assertEq(client.balance, clientBalBefore + clientRefund + TOTAL_RELAYER_POOL);
        assertEq(freelancer.balance, freelancerBalBefore + freelancerPayout);
        assertEq(address(escrow).balance, 0);
    }

    function test_Dispute_ResolveAllToClient_ZeroPayoutBranch() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(client);
        escrow.raiseDispute();

        uint256 clientBalBefore = client.balance;

        // 100% refund to client, 0 to freelancer (tests _freelancerPayout == 0 branch)
        vm.prank(arbiter);
        escrow.resolveDispute(TOTAL_AMOUNT, 0);

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(client.balance, clientBalBefore + TOTAL_AMOUNT + TOTAL_RELAYER_POOL);
    }

    function test_Dispute_ResolveAllToFreelancer_ZeroRefundBranch() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(client);
        escrow.raiseDispute();

        uint256 freelancerBalBefore = freelancer.balance;

        // 0 refund to client, 100% payout to freelancer (tests _clientRefund == 0 branch)
        vm.prank(arbiter);
        escrow.resolveDispute(0, TOTAL_AMOUNT);

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(freelancer.balance, freelancerBalBefore + TOTAL_AMOUNT);
    }

    function test_RevertIf_RaiseDispute_Unauthorized() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(makeAddr("attacker"));
        escrow.raiseDispute();
    }

    function test_RevertIf_ResolveDispute_NotArbiter() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(client);
        escrow.raiseDispute();

        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(client);
        escrow.resolveDispute(0.5 ether, 0.5 ether);
    }

    function test_RevertIf_DisputeSplitMismatch() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(client);
        escrow.raiseDispute();

        vm.expectRevert(Escrow.InvalidSplitAmount.selector);
        vm.prank(arbiter);
        escrow.resolveDispute(0.4 ether, 0.4 ether);

        vm.expectRevert(Escrow.InvalidSplitAmount.selector);
        vm.prank(arbiter);
        escrow.resolveDispute(0.6 ether, 0.5 ether);
    }

    function test_ClaimInactivityRefund_Success() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.warp(block.timestamp + 30 days);

        uint256 clientBalBefore = client.balance;
        uint256 vaultRemaining = address(escrow).balance;

        vm.prank(client);
        escrow.claimInactivityRefund();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(client.balance, clientBalBefore + vaultRemaining);
        assertEq(address(escrow).balance, 0);
    }

    function test_RevertIf_ClaimInactivityRefund_NotClient() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.warp(block.timestamp + 30 days);

        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(freelancer);
        escrow.claimInactivityRefund();
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

        vm.warp(block.timestamp + 14 days);

        uint256 freelancerBalBefore = freelancer.balance;
        uint256 clientBalBefore = client.balance;

        vm.prank(freelancer);
        escrow.claimReviewTimeoutPayout();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(freelancer.balance, freelancerBalBefore + TOTAL_AMOUNT);
        assertEq(client.balance, clientBalBefore + TOTAL_RELAYER_POOL);
        assertEq(address(escrow).balance, 0);

        (,, bool m0Approved) = escrow.milestones(0);
        (,, bool m1Approved) = escrow.milestones(1);
        assertTrue(m0Approved);
        assertTrue(m1Approved);
    }

    function test_RevertIf_ClaimReviewTimeoutPayout_NotFreelancer() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        vm.warp(block.timestamp + 14 days);

        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(client);
        escrow.claimReviewTimeoutPayout();
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

    function test_GetLatestSubmission_EmptySubmissions() public view {
        Escrow.Submission memory sub = escrow.getLatestSubmission();
        assertEq(bytes(sub.deliverableUrl).length, 0);
        assertEq(sub.milestoneIndex, 0);
    }

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

        vm.expectRevert(Escrow.InvalidDepositAmount.selector);
        vm.prank(client);
        tokenEscrow.fund{value: 1 ether}();

        vm.startPrank(client);
        token.approve(address(tokenEscrow), TOTAL_REQUIRED);
        tokenEscrow.fund();
        vm.stopPrank();

        assertEq(token.balanceOf(address(tokenEscrow)), TOTAL_AMOUNT + TOTAL_RELAYER_POOL);
        assertEq(token.balanceOf(feeRecipient), FEE_AMOUNT);

        vm.prank(freelancer);
        tokenEscrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        vm.prank(client);
        tokenEscrow.releaseMilestone(0);
        assertEq(token.balanceOf(freelancer), MILESTONE_1_AMOUNT);
        assertEq(uint256(tokenEscrow.currentState()), uint256(Escrow.State.Funded));

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

    function test_TokenEscrow_IntermediateDecimalsBranch() public {
        MockERC20 token8 = new MockERC20();
        token8.setDecimals(8);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 * 10 ** 8;
        string[] memory desc = new string[](1);
        desc[0] = "Decimals 8";

        Escrow e = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(token8),
            amounts,
            desc,
            0,
            RELAYER_FEE_PER_TX
        );

        assertTrue(e.RELAYER_FEE_PER_TX() > 0);
    }

    function test_TokenEscrow_ZeroFeeBranch() public {
        MockERC20 token = new MockERC20();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;
        string[] memory desc = new string[](1);
        desc[0] = "Zero Fee Token";

        Escrow e = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(token),
            amounts,
            desc,
            0,
            RELAYER_FEE_PER_TX
        );

        token.mint(client, 100 ether + e.TOTAL_RELAYER_POOL());
        vm.startPrank(client);
        token.approve(address(e), 100 ether + e.TOTAL_RELAYER_POOL());
        e.fund();
        vm.stopPrank();

        assertEq(uint256(e.currentState()), uint256(Escrow.State.Funded));
    }

    function test_TokenEscrow_NoDecimalsCatchBranch() public {
        NoDecimalsToken noDecToken = new NoDecimalsToken();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;
        string[] memory desc = new string[](1);
        desc[0] = "NoDec";

        // Deploys with token that throws when querying decimals (triggers catch {} branch)
        Escrow e = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(noDecToken),
            amounts,
            desc,
            100,
            RELAYER_FEE_PER_TX
        );

        assertEq(e.RELAYER_FEE_PER_TX(), RELAYER_FEE_PER_TX);
    }

    function test_RevertIf_EthTransferFailed_OnPayout() public {
        RejectEther rejectContract = new RejectEther();

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        string[] memory desc = new string[](1);
        desc[0] = "Scope";

        Escrow e = new Escrow(
            client,
            address(rejectContract),
            arbiter,
            feeRecipient,
            address(0),
            amounts,
            desc,
            100,
            RELAYER_FEE_PER_TX
        );

        uint256 req = 1 ether + (1 ether * 100) / 10000 + e.TOTAL_RELAYER_POOL();
        vm.prank(client);
        e.fund{value: req}();

        vm.prank(client);
        vm.expectRevert(Escrow.TransferFailed.selector);
        e.releaseFunds();
    }

    function test_RelayerReimbursement_SkipIfStakeholderIsSender() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        // Sign deliverable with freelancer key
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(freelancerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // When CLIENT directly relays the transaction (tests msg.sender == CLIENT branch)
        uint256 clientBalBefore = client.balance;
        vm.prank(client);
        escrow.submitDeliverableWithSig(URL, IPFS_CID, NOTES, 0, deadline, signature);

        // Client should NOT be reimbursed relayer fee
        assertEq(client.balance, clientBalBefore);
    }

    function test_RelayerReimbursement_ZeroRelayerFeeBranch() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        string[] memory desc = new string[](1);
        desc[0] = "Scope";

        // Deployed with RELAYER_FEE_PER_TX == 0 (tests RELAYER_FEE_PER_TX == 0 early return branch)
        Escrow zeroRelayerEscrow = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(0),
            amounts,
            desc,
            100,
            0 // zero relayer fee
        );

        vm.prank(client);
        zeroRelayerEscrow.fund{value: 1.01 ether}();

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
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(zeroRelayerEscrow)), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(freelancerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        address externalRelayer = makeAddr("externalRelayer");
        vm.deal(externalRelayer, 1 ether);
        uint256 relayerBalBefore = externalRelayer.balance;

        vm.prank(externalRelayer);
        zeroRelayerEscrow.submitDeliverableWithSig(URL, IPFS_CID, NOTES, 0, deadline, signature);

        assertEq(externalRelayer.balance, relayerBalBefore);
    }

    // --- 1. Line 160: 6-Decimal Token (USDC/USDT) Branch ---
    function test_TokenEscrow_6DecimalsBranch() public {
        MockERC20 usdc = new MockERC20();
        usdc.setDecimals(6); // Hits Line 160 (RELAYER_FEE_PER_TX = 250_000)

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 * 10 ** 6;
        string[] memory desc = new string[](1);
        desc[0] = "USDC Scope";

        Escrow e = new Escrow(
            client,
            freelancer,
            arbiter,
            feeRecipient,
            address(usdc),
            amounts,
            desc,
            PROTOCOL_FEE_BPS,
            0.0001 ether
        );

        assertEq(e.RELAYER_FEE_PER_TX(), 250_000);
    }

    // --- 2. Line 269: Submit Deliverable Invalid State Revert ---
    function test_RevertIf_SubmitDeliverable_InvalidState() public {
        // Contract is in Pending state (not Funded or Delivered)
        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidState.selector, Escrow.State.Funded, Escrow.State.Pending));
        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);
    }

    // --- 3. Line 272: Submit Deliverable on Already Approved Milestone Revert ---
    function test_RevertIf_SubmitDeliverable_MilestoneAlreadyApproved() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        // Approve milestone 0
        vm.prank(client);
        escrow.releaseMilestone(0);

        // Attempting to submit another deliverable for already approved milestone 0
        vm.expectRevert(Escrow.MilestoneAlreadyApproved.selector);
        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);
    }

    // --- 4. Line 337: Release Milestone Invalid State Revert ---
    function test_RevertIf_ReleaseMilestone_InvalidState() public {
        // Contract is in Pending state
        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidState.selector, Escrow.State.Delivered, Escrow.State.Pending));
        vm.prank(client);
        escrow.releaseMilestone(0);
    }

    // --- 5. Line 434: Raise Dispute Invalid State Revert ---
    function test_RevertIf_RaiseDispute_InvalidState() public {
        // Contract is in Pending state
        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidState.selector, Escrow.State.Funded, Escrow.State.Pending));
        vm.prank(client);
        escrow.raiseDispute();
    }

    // --- 1. Line 206: Protocol Fee Native Transfer Failed Revert ---
    function test_RevertIf_Fund_ProtocolFeeTransferFailed() public {
        RejectEther rejectFeeRecipient = new RejectEther();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        string[] memory desc = new string[](1);
        desc[0] = "Fee Fail Test";

        Escrow feeFailEscrow = new Escrow(
            client,
            freelancer,
            arbiter,
            address(rejectFeeRecipient),
            address(0),
            amounts,
            desc,
            100,
            RELAYER_FEE_PER_TX
        );

        uint256 required = 1 ether + feeFailEscrow.PROTOCOL_FEE() + feeFailEscrow.TOTAL_RELAYER_POOL();
        vm.deal(client, required);
        vm.prank(client);
        vm.expectRevert(Escrow.TransferFailed.selector);
        feeFailEscrow.fund{value: required}();
    }

    // --- 2. Line 321 & 329: releaseMilestoneWithSig Errors ---
    function test_Gasless_ReleaseMilestoneWithSig_Reverts() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        // Expired signature check (Line 321)
        vm.warp(1000);
        uint256 expiredDeadline = block.timestamp - 1;
        bytes memory dummySig = new bytes(65);
        vm.expectRevert(Escrow.SignatureExpired.selector);
        escrow.releaseMilestoneWithSig(0, expiredDeadline, dummySig);

        // Invalid signer check (Line 329)
        uint256 validDeadline = block.timestamp + 1 hours;
        bytes32 typeHash = keccak256("ReleaseMilestone(address client,uint256 milestoneIndex,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(typeHash, client, 0, 0, validDeadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));
        
        // Signed with attacker key instead of client
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert(Escrow.InvalidSignature.selector);
        escrow.releaseMilestoneWithSig(0, validDeadline, badSig);
    }

    // --- 3. Line 369 & 377: releaseFundsWithSig Errors ---
    function test_Gasless_ReleaseFundsWithSig_Reverts() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        // Expired signature check (Line 369)
        vm.warp(1000);
        uint256 expiredDeadline = block.timestamp - 1;
        bytes memory dummySig = new bytes(65);
        vm.expectRevert(Escrow.SignatureExpired.selector);
        escrow.releaseFundsWithSig(expiredDeadline, dummySig);

        // Invalid signer check (Line 377)
        uint256 validDeadline = block.timestamp + 1 hours;
        bytes32 typeHash = keccak256("ReleaseAllFunds(address client,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(typeHash, client, 0, validDeadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));
        
        // Signed with attacker key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert(Escrow.InvalidSignature.selector);
        escrow.releaseFundsWithSig(validDeadline, badSig);
    }

    // --- 4. Line 417, 418 & 426: raiseDisputeWithSig Errors ---
    function test_Gasless_RaiseDisputeWithSig_Reverts() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        bytes memory dummySig = new bytes(65);

        // Unauthorized sender check (Line 417)
        vm.expectRevert(Escrow.Unauthorized.selector);
        escrow.raiseDisputeWithSig(makeAddr("stranger"), block.timestamp + 1 hours, dummySig);

        // Expired signature check (Line 418)
        vm.warp(1000);
        vm.expectRevert(Escrow.SignatureExpired.selector);
        escrow.raiseDisputeWithSig(client, block.timestamp - 1, dummySig);

        // Invalid signer check (Line 426)
        uint256 validDeadline = block.timestamp + 1 hours;
        bytes32 typeHash = keccak256("RaiseDispute(address sender,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(typeHash, client, 0, validDeadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getEIP712DomainSeparator(address(escrow)), structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert(Escrow.InvalidSignature.selector);
        escrow.raiseDisputeWithSig(client, validDeadline, badSig);
    }

    // --- 5. Line 441 & 451: Resolve Dispute Invalid State Reverts ---
    function test_RevertIf_ResolveDispute_InvalidState() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        // Contract is in Funded state, not Disputed (Line 441)
        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidState.selector, Escrow.State.Disputed, Escrow.State.Funded));
        vm.prank(arbiter);
        escrow.resolveDispute(0.5 ether, 0.5 ether);

        // Gasless resolution when not Disputed (Line 451)
        bytes memory dummySig = new bytes(65);
        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidState.selector, Escrow.State.Disputed, Escrow.State.Funded));
        escrow.resolveDisputeWithSig(0.5 ether, 0.5 ether, block.timestamp + 1 hours, dummySig);
    }

    // --- 6. Line 503: Claim Review Timeout Invalid State Revert ---
    function test_RevertIf_ClaimReviewTimeout_InvalidState() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        // Contract is in Funded state, not Delivered (Line 503)
        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidState.selector, Escrow.State.Delivered, Escrow.State.Funded));
        vm.prank(freelancer);
        escrow.claimReviewTimeoutPayout();
    }

    // --- 7. Line 580: getSubmission Out of Bounds Revert ---
    function test_RevertIf_GetSubmission_OutOfBounds() public {
        vm.expectRevert("Invalid index");
        escrow.getSubmission(0);
    }

    function test_RevertIf_ClaimInactivityRefund_SubmissionsExistInFundedState() public {
        vm.prank(client);
        escrow.fund{value: TOTAL_REQUIRED}();

        // Milestone 0 submit and release (resets state back to Funded, but submissions.length == 1)
        vm.prank(freelancer);
        escrow.submitDeliverable(URL, IPFS_CID, NOTES, 0);

        vm.prank(client);
        escrow.releaseMilestone(0);

        // Contract is now in State.Funded and submissions.length == 1
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));
        assertEq(escrow.getSubmissionsCount(), 1);

        // Warp past 30 days
        vm.warp(block.timestamp + 31 days);

        // Hits Line 492 revert branch
        vm.expectRevert(Escrow.SubmissionsAlreadyExist.selector);
        vm.prank(client);
        escrow.claimInactivityRefund();
    }
}