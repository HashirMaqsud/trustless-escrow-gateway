// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

    uint256 public constant ETH_PAYMENT = 2 ether;
    uint256 public constant TOKEN_PAYMENT = 500 ether;

    function setUp() public {
        factory = new EscrowFactory();
        token = new IntegrationMockERC20();

        // Fund accounts
        vm.deal(clientA, 10 ether);
        vm.deal(clientB, 10 ether);

        token.mint(clientA, 2000 ether);
        token.mint(clientB, 2000 ether);
    }

    function test_Integration_NativeEth_FullHappyPath() public {
        // Step 1: Client A deploys Escrow via Factory
        vm.prank(clientA);
        address escrowAddr = factory.createEscrow(
            freelancerA,
            arbiter,
            address(0),
            ETH_PAYMENT
        );

        Escrow escrow = Escrow(escrowAddr);

        // Step 2: Client A funds the deployed Escrow directly
        vm.prank(clientA);
        escrow.fund{value: ETH_PAYMENT}();
        assertEq(address(escrow).balance, ETH_PAYMENT);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));

        // Step 3: Freelancer A submits work
        string memory proofOfWork = "https://github.com/clientA/final-project-v1";
        vm.prank(freelancerA);
        escrow.submitDeliverable(proofOfWork);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Delivered));
        assertEq(escrow.deliverableUrl(), proofOfWork);

        // Step 4: Client A approves and releases funds
        uint256 freelancerInitialBalance = freelancerA.balance;

        vm.prank(clientA);
        escrow.releaseFunds();

        // Step 5: Final settlement checks
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(address(escrow).balance, 0);
        assertEq(freelancerA.balance, freelancerInitialBalance + ETH_PAYMENT);
    }

    function test_Integration_Token_DisputeAndSplitWorkflow() public {
        // Step 1: Client B deploys Token-based Escrow via Factory
        vm.prank(clientB);
        address escrowAddr = factory.createEscrow(
            freelancerB,
            arbiter,
            address(token),
            TOKEN_PAYMENT
        );

        Escrow escrow = Escrow(escrowAddr);

        // Step 2: Client B approves token transfer and funds Escrow
        vm.startPrank(clientB);
        token.approve(escrowAddr, TOKEN_PAYMENT);
        escrow.fund();
        vm.stopPrank();

        assertEq(token.balanceOf(escrowAddr), TOKEN_PAYMENT);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Funded));

        // Step 3: Freelancer B submits work
        vm.prank(freelancerB);
        escrow.submitDeliverable("https://figma.com/design-submission");

        // Step 4: Client B is dissatisfied and raises dispute
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

        // Step 6: Verify final token accounting
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.Completed));
        assertEq(token.balanceOf(escrowAddr), 0);
        assertEq(token.balanceOf(clientB), clientInitialTokenBalance + refundAmount);
        assertEq(token.balanceOf(freelancerB), freelancerInitialTokenBalance + payoutAmount);
    }

    function test_Integration_FactoryMultiPartyIsolation() public {
        // Deploy Escrow 1 for Client A & Freelancer A
        vm.prank(clientA);
        address escrow1 = factory.createEscrow(
            freelancerA,
            arbiter,
            address(0),
            1 ether
        );

        // Deploy Escrow 2 for Client B & Freelancer B
        vm.prank(clientB);
        address escrow2 = factory.createEscrow(
            freelancerB,
            arbiter,
            address(0),
            2 ether
        );

        // Deploy Escrow 3 for Client A & Freelancer B
        vm.prank(clientA);
        address escrow3 = factory.createEscrow(
            freelancerB,
            arbiter,
            address(0),
            3 ether
        );

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
    }

    function test_Integration_ConcurrentEscrows_IndependentLifecycles() public {
        // Client A deploys Escrow 1 (ETH)
        vm.prank(clientA);
        address escrow1Addr = factory.createEscrow(freelancerA, arbiter, address(0), 1 ether);
        Escrow escrow1 = Escrow(escrow1Addr);

        // Client B deploys Escrow 2 (Tokens)
        vm.prank(clientB);
        address escrow2Addr = factory.createEscrow(freelancerB, arbiter, address(token), 100 ether);
        Escrow escrow2 = Escrow(escrow2Addr);

        // Both fund concurrently
        vm.prank(clientA);
        escrow1.fund{value: 1 ether}();

        vm.startPrank(clientB);
        token.approve(escrow2Addr, 100 ether);
        escrow2.fund();
        vm.stopPrank();

        // Verify independent vault balances
        assertEq(address(escrow1).balance, 1 ether);
        assertEq(token.balanceOf(escrow2Addr), 100 ether);

        // Escrow 1 goes through standard completion
        vm.prank(freelancerA);
        escrow1.submitDeliverable("https://work.com/a");
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
        // Factory deployed escrow - Client attempts to release before delivery
        vm.prank(clientA);
        address escrowAddr = factory.createEscrow(freelancerA, arbiter, address(0), 1 ether);
        Escrow escrow = Escrow(escrowAddr);

        vm.prank(clientA);
        escrow.fund{value: 1 ether}();

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