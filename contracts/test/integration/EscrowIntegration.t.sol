// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EscrowFactory} from "../../src/EscrowFactory.sol";
import {Escrow} from "../../src/Escrow.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 Token for integration testing
contract IntegrationMockERC20 is ERC20 {
    constructor() ERC20("ProjectToken", "PTK") {
        _mint(msg.sender, 10000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract EscrowIntegrationTest is Test {
    EscrowFactory public factory;
    IntegrationMockERC20 public token;

    // Parties
    address public clientA = makeAddr("clientA");
    address public freelancerA = makeAddr("freelancerA");
    address public clientB = makeAddr("clientB");
    address public freelancerB = makeAddr("freelancerB");
    address public arbiter = makeAddr("arbiter");
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 public constant ETH_PAYMENT = 2 ether;
    uint256 public constant TOKEN_PAYMENT = 500 ether;
    uint256 public constant FEE_BPS = 100; // 1%
    uint256 public constant RELAYER_FEE_PER_TX = 0.0001 ether;

    string public constant IPFS_CID = "ipfs://bafybeicg2oxqozr75w3xjoxj4zsvygl4q752k4z626j5z4y25n7e4q4n4y";
    string public constant NOTES = "Integration test submission notes";

    function setUp() public {
        factory = new EscrowFactory(feeRecipient, FEE_BPS, RELAYER_FEE_PER_TX);
        token = new IntegrationMockERC20();

        // Fund accounts
        vm.deal(clientA, 10 ether);
        vm.deal(clientB, 10 ether);

        token.mint(clientA, 2000 ether);
        token.mint(clientB, 2000 ether);
    }

    function test_Integration_NativeEth_FullHappyPath() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ETH_PAYMENT;
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Full Project Scope";

        // Step 1: Client A deploys Escrow via Factory
        vm.prank(clientA);
        address escrowAddr = factory.createEscrow(
            freelancerA,
            arbiter,
            address(0),
            amounts,
            descriptions
        );

        Escrow escrow = Escrow(escrowAddr);
        uint256 fee = (ETH_PAYMENT * FEE_BPS) / 10000;
        uint256 relayerPool = escrow.TOTAL_RELAYER_POOL();
        uint256 totalRequired = ETH_PAYMENT + fee + relayerPool;

        // Step 2: Client A funds the deployed Escrow directly with deposit + fee + relayerPool
        vm.prank(clientA);
        escrow.fund{value: totalRequired}();
        assertEq(address(escrow).balance, ETH_PAYMENT + relayerPool);
        assertEq(feeRecipient.balance, fee);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));

        // Step 3: Freelancer A submits work
        string memory proofOfWork = "https://github.com/clientA/final-project-v1";
        vm.prank(freelancerA);
        escrow.submitDeliverable(proofOfWork, IPFS_CID, NOTES, 0);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Delivered));
        assertEq(escrow.getLatestSubmission().deliverableUrl, proofOfWork);

        // Step 4: Client A approves and releases funds
        uint256 freelancerInitialBalance = freelancerA.balance;
        uint256 clientInitialBalance = clientA.balance;

        vm.prank(clientA);
        escrow.releaseFunds();

        // Step 5: Final settlement checks
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(freelancerA.balance, freelancerInitialBalance + ETH_PAYMENT);
        // Unused dynamic relayer pool returned to Client A
        assertEq(clientA.balance, clientInitialBalance + relayerPool);
        assertEq(address(escrow).balance, 0);

        (,, bool approved) = escrow.milestones(0);
        assertTrue(approved);
    }

    function test_Integration_Token_DisputeAndSplitWorkflow() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = TOKEN_PAYMENT;
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Design Sprint";

        // Step 1: Client B deploys Token-based Escrow via Factory
        vm.prank(clientB);
        address escrowAddr = factory.createEscrow(
            freelancerB,
            arbiter,
            address(token),
            amounts,
            descriptions
        );

        Escrow escrow = Escrow(escrowAddr);
        uint256 fee = (TOKEN_PAYMENT * FEE_BPS) / 10000;
        uint256 relayerPool = escrow.TOTAL_RELAYER_POOL();
        uint256 totalRequired = TOKEN_PAYMENT + fee + relayerPool;

        // Step 2: Client B approves token transfer and funds Escrow
        vm.startPrank(clientB);
        token.approve(escrowAddr, totalRequired);
        escrow.fund();
        vm.stopPrank();

        assertEq(token.balanceOf(escrowAddr), TOKEN_PAYMENT + relayerPool);
        assertEq(token.balanceOf(feeRecipient), fee);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));

        // Step 3: Freelancer B submits work
        vm.prank(freelancerB);
        escrow.submitDeliverable("https://figma.com/design-submission", IPFS_CID, NOTES, 0);

        // Step 4: Client B raises dispute
        vm.prank(clientB);
        escrow.raiseDispute();
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Disputed));

        // Step 5: Arbiter mediates and splits tokens (300 to client refund, 200 to freelancer payout)
        uint256 refundAmount = 300 ether;
        uint256 payoutAmount = 200 ether;

        uint256 clientInitialTokenBalance = token.balanceOf(clientB);
        uint256 freelancerInitialTokenBalance = token.balanceOf(freelancerB);

        vm.prank(arbiter);
        escrow.resolveDispute(refundAmount, payoutAmount);

        // Step 6: Verify final token accounting (Client gets refund + unused relayer pool)
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(token.balanceOf(clientB), clientInitialTokenBalance + refundAmount + relayerPool);
        assertEq(token.balanceOf(freelancerB), freelancerInitialTokenBalance + payoutAmount);
        assertEq(token.balanceOf(escrowAddr), 0);
    }

    function test_Integration_FactoryMultiPartyIsolation() public {
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = 1 ether;
        string[] memory desc1 = new string[](1);
        desc1[0] = "M1";

        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = 2 ether;
        string[] memory desc2 = new string[](1);
        desc2[0] = "M2";

        uint256[] memory amounts3 = new uint256[](1);
        amounts3[0] = 3 ether;
        string[] memory desc3 = new string[](1);
        desc3[0] = "M3";

        // Deploy Escrow 1 for Client A & Freelancer A
        vm.prank(clientA);
        address escrow1 = factory.createEscrow(freelancerA, arbiter, address(0), amounts1, desc1);

        // Deploy Escrow 2 for Client B & Freelancer B
        vm.prank(clientB);
        address escrow2 = factory.createEscrow(freelancerB, arbiter, address(0), amounts2, desc2);

        // Deploy Escrow 3 for Client A & Freelancer B
        vm.prank(clientA);
        address escrow3 = factory.createEscrow(freelancerB, arbiter, address(0), amounts3, desc3);

        // Verify total registry count
        assertEq(factory.getAllEscrows().length, 3);

        // Verify Client A has exactly escrow 1 and 3
        address[] memory clientAEscrows = factory.getUserEscrows(clientA);
        assertEq(clientAEscrows.length, 2);
        assertEq(clientAEscrows[0], escrow1);
        assertEq(clientAEscrows[1], escrow3);

        // Verify Client B has only escrow 2
        address[] memory clientBEscrows = factory.getUserEscrows(clientB);
        assertEq(clientBEscrows.length, 1);
        assertEq(clientBEscrows[0], escrow2);

        // Verify Freelancer B is mapped to escrow 2 and 3
        address[] memory freelancerBEscrows = factory.getUserEscrows(freelancerB);
        assertEq(freelancerBEscrows.length, 2);
        assertEq(freelancerBEscrows[0], escrow2);
        assertEq(freelancerBEscrows[1], escrow3);

        // Verify Arbiter is mapped to all 3 escrows
        address[] memory arbiterEscrows = factory.getUserEscrows(arbiter);
        assertEq(arbiterEscrows.length, 3);
    }

    function test_Integration_ConcurrentEscrows_IndependentLifecycles() public {
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = 1 ether;
        string[] memory desc1 = new string[](1);
        desc1[0] = "Scope 1";

        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = 100 ether;
        string[] memory desc2 = new string[](1);
        desc2[0] = "Scope 2";

        // Client A deploys Escrow 1 (ETH)
        vm.prank(clientA);
        address escrow1Addr = factory.createEscrow(freelancerA, arbiter, address(0), amounts1, desc1);
        Escrow escrow1 = Escrow(escrow1Addr);

        // Client B deploys Escrow 2 (Tokens)
        vm.prank(clientB);
        address escrow2Addr = factory.createEscrow(freelancerB, arbiter, address(token), amounts2, desc2);
        Escrow escrow2 = Escrow(escrow2Addr);

        uint256 fee1 = (1 ether * FEE_BPS) / 10000;
        uint256 fee2 = (100 ether * FEE_BPS) / 10000;
        uint256 pool1 = escrow1.TOTAL_RELAYER_POOL();
        uint256 pool2 = escrow2.TOTAL_RELAYER_POOL();

        // Both fund concurrently
        vm.prank(clientA);
        escrow1.fund{value: 1 ether + fee1 + pool1}();

        vm.startPrank(clientB);
        token.approve(escrow2Addr, 100 ether + fee2 + pool2);
        escrow2.fund();
        vm.stopPrank();

        // Verify independent vault balances
        assertEq(address(escrow1).balance, 1 ether + pool1);
        assertEq(token.balanceOf(escrow2Addr), 100 ether + pool2);

        // Escrow 1 goes through standard completion
        vm.prank(freelancerA);
        escrow1.submitDeliverable("https://work.com/a", IPFS_CID, NOTES, 0);
        vm.prank(clientA);
        escrow1.releaseFunds();

        // Escrow 2 goes through dispute and full refund to Client B
        vm.prank(clientB);
        escrow2.raiseDispute();
        vm.prank(arbiter);
        escrow2.resolveDispute(100 ether, 0);

        // Final independent state assertions
        assertEq(uint256(escrow1.currentState()), uint256(Escrow.State.Completed));
        assertEq(uint256(escrow2.currentState()), uint256(Escrow.State.Completed));
        assertEq(address(escrow1).balance, 0);
        assertEq(token.balanceOf(escrow2Addr), 0);
    }

    function test_Integration_FactoryDeployed_RevertIf_PrematureRelease() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        string[] memory desc = new string[](1);
        desc[0] = "Scope";

        // Factory deployed escrow - Client attempts to release before delivery
        vm.prank(clientA);
        address escrowAddr = factory.createEscrow(freelancerA, arbiter, address(0), amounts, desc);
        Escrow escrow = Escrow(escrowAddr);

        uint256 fee = (1 ether * FEE_BPS) / 10000;
        uint256 pool = escrow.TOTAL_RELAYER_POOL();
        vm.prank(clientA);
        escrow.fund{value: 1 ether + fee + pool}();

        // Must revert because state is Funded, not Delivered
        vm.expectRevert(
            abi.encodeWithSelector(
                Escrow.InvalidState.selector,
                Escrow.State.Delivered,
                Escrow.State.Funded
            )
        );
        vm.prank(clientA);
        escrow.releaseFunds();
    }
}