// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {EscrowFactory} from "../../src/EscrowFactory.sol";
import {Escrow} from "../../src/Escrow.sol";

contract EscrowFactoryUnitTest is Test {
    EscrowFactory public factory;

    // Test parties
    address public client = makeAddr("client");
    address public freelancer = makeAddr("freelancer");
    address public arbiter = makeAddr("arbiter");

    uint256 public constant ESCROW_AMOUNT = 1 ether;

    // Event signature matching EscrowFactory.EscrowCreated
    event EscrowCreated(
        address indexed escrowAddress,
        address indexed client,
        address indexed freelancer,
        address arbiter,
        address token,
        uint256 amount
    );

    function setUp() public {
        factory = new EscrowFactory();
    }

    function test_InitialState() public view {
        assertEq(factory.getAllEscrows().length, 0);
        assertEq(factory.getUserEscrows(client).length, 0);
        assertEq(factory.getUserEscrows(freelancer).length, 0);
    }

    function test_CreateEscrow_NativeEth_Success() public {
        vm.prank(client);

        // Expect EscrowCreated event (escrowAddress check is skipped via false since it is generated at runtime)
        vm.expectEmit(false, true, true, true);
        emit EscrowCreated(
            address(0),
            client,
            freelancer,
            arbiter,
            address(0),
            ESCROW_AMOUNT
        );

        address deployedEscrow = factory.createEscrow(
            freelancer,
            arbiter,
            address(0),
            ESCROW_AMOUNT
        );

        assertTrue(deployedEscrow != address(0));

        // Verify state variables on the deployed Escrow instance
        Escrow escrowInstance = Escrow(deployedEscrow);
        assertEq(escrowInstance.CLIENT(), client);
        assertEq(escrowInstance.FREELANCER(), freelancer);
        assertEq(escrowInstance.ARBITER(), arbiter);
        assertEq(escrowInstance.AMOUNT(), ESCROW_AMOUNT);

        // Verify global and user registries
        address[] memory allEscrows = factory.getAllEscrows();
        assertEq(allEscrows.length, 1);
        assertEq(allEscrows[0], deployedEscrow);

        address[] memory clientEscrows = factory.getUserEscrows(client);
        assertEq(clientEscrows.length, 1);
        assertEq(clientEscrows[0], deployedEscrow);

        address[] memory freelancerEscrows = factory.getUserEscrows(freelancer);
        assertEq(freelancerEscrows.length, 1);
        assertEq(freelancerEscrows[0], deployedEscrow);
    }

    function test_CreateEscrow_MultipleDeploymentsTracking() public {
        // Deploy first escrow from client
        vm.prank(client);
        address firstEscrow = factory.createEscrow(
            freelancer,
            arbiter,
            address(0),
            ESCROW_AMOUNT
        );

        // Deploy second escrow with a different freelancer
        address freelancer2 = makeAddr("freelancer2");
        vm.prank(client);
        address secondEscrow = factory.createEscrow(
            freelancer2,
            arbiter,
            address(0),
            2 ether
        );

        address[] memory allEscrows = factory.getAllEscrows();
        assertEq(allEscrows.length, 2);
        assertEq(allEscrows[0], firstEscrow);
        assertEq(allEscrows[1], secondEscrow);

        // Client should have 2 escrows
        address[] memory clientEscrows = factory.getUserEscrows(client);
        assertEq(clientEscrows.length, 2);
        assertEq(clientEscrows[0], firstEscrow);
        assertEq(clientEscrows[1], secondEscrow);

        // Freelancer 1 should have 1 escrow
        assertEq(factory.getUserEscrows(freelancer).length, 1);
        // Freelancer 2 should have 1 escrow
        assertEq(factory.getUserEscrows(freelancer2).length, 1);
    }

    function test_RevertIf_UnderlyingEscrowRevertsOnZeroAddress() public {
        // Passing address(0) as freelancer triggers Escrow's constructor revert
        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(client);
        factory.createEscrow(address(0), arbiter, address(0), ESCROW_AMOUNT);
    }

    function test_RevertIf_UnderlyingEscrowRevertsOnZeroAmount() public {
        // Passing 0 as amount triggers Escrow's InvalidDepositAmount
        vm.expectRevert(Escrow.InvalidDepositAmount.selector);
        vm.prank(client);
        factory.createEscrow(freelancer, arbiter, address(0), 0);
    }
}