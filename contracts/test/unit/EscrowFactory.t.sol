// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EscrowFactory} from "../../src/EscrowFactory.sol";
import {Escrow} from "../../src/Escrow.sol";

contract EscrowFactoryUnitTest is Test {
    EscrowFactory public factory;

    // Test parties
    address public client = makeAddr("client");
    address public freelancer = makeAddr("freelancer");
    address public arbiter = makeAddr("arbiter");
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 public constant ESCROW_AMOUNT = 1 ether;
    uint256 public constant PROTOCOL_FEE_BPS = 100; // 1%
    uint256 public constant RELAYER_FEE_PER_TX = 0.0001 ether;

    // Event signature matching updated EscrowFactory.EscrowCreated
    event EscrowCreated(
        address indexed escrowAddress,
        address indexed client,
        address indexed freelancer,
        address arbiter,
        address token,
        uint256 totalAmount,
        uint256 feeBps,
        uint256 relayerFeePerTx,
        uint256 totalRelayerPool
    );

    function setUp() public {
        factory = new EscrowFactory(feeRecipient, PROTOCOL_FEE_BPS, RELAYER_FEE_PER_TX);
    }

    function test_InitialState() public view {
        assertEq(factory.getAllEscrows().length, 0);
        assertEq(factory.getUserEscrows(client).length, 0);
        assertEq(factory.getUserEscrows(freelancer).length, 0);
        assertEq(factory.getUserEscrows(arbiter).length, 0);
        assertEq(factory.feeRecipient(), feeRecipient);
        assertEq(factory.feeBps(), PROTOCOL_FEE_BPS);
        assertEq(factory.relayerFeePerTx(), RELAYER_FEE_PER_TX);
    }

    function test_CreateEscrow_NativeEth_Success() public {
        vm.prank(client);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ESCROW_AMOUNT;

        string[] memory descriptions = new string[](1);
        descriptions[0] = "Milestone 1";

        // Expected Relayer Pool calculation: (1 milestone * (3 revisions + 1) + 2 buffer) * 0.0001 = 6 * 0.0001 = 0.0006 ether
        uint256 expectedRelayerPool = RELAYER_FEE_PER_TX * 6;

        vm.expectEmit(false, true, true, true);
        emit EscrowCreated(
            address(0),
            client,
            freelancer,
            arbiter,
            address(0),
            ESCROW_AMOUNT,
            PROTOCOL_FEE_BPS,
            RELAYER_FEE_PER_TX,
            expectedRelayerPool
        );

        address deployedEscrow = factory.createEscrow(
            freelancer,
            arbiter,
            address(0),
            amounts,
            descriptions
        );

        assertTrue(deployedEscrow != address(0));

        // Verify state variables on deployed instance
        Escrow escrowInstance = Escrow(deployedEscrow);
        assertEq(escrowInstance.CLIENT(), client);
        assertEq(escrowInstance.FREELANCER(), freelancer);
        assertEq(escrowInstance.ARBITER(), arbiter);
        assertEq(escrowInstance.FEE_RECIPIENT(), feeRecipient);
        assertEq(escrowInstance.TOTAL_AMOUNT(), ESCROW_AMOUNT);
        assertEq(escrowInstance.RELAYER_FEE_PER_TX(), RELAYER_FEE_PER_TX);
        assertEq(escrowInstance.TOTAL_RELAYER_POOL(), expectedRelayerPool);

        // Verify global and user registries (Including Arbiter index verification)
        address[] memory allEscrows = factory.getAllEscrows();
        assertEq(allEscrows.length, 1);
        assertEq(allEscrows[0], deployedEscrow);

        address[] memory clientEscrows = factory.getUserEscrows(client);
        assertEq(clientEscrows.length, 1);
        assertEq(clientEscrows[0], deployedEscrow);

        address[] memory freelancerEscrows = factory.getUserEscrows(freelancer);
        assertEq(freelancerEscrows.length, 1);
        assertEq(freelancerEscrows[0], deployedEscrow);

        address[] memory arbiterEscrows = factory.getUserEscrows(arbiter);
        assertEq(arbiterEscrows.length, 1);
        assertEq(arbiterEscrows[0], deployedEscrow);
    }

    function test_CreateEscrow_MultipleDeploymentsTracking() public {
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = ESCROW_AMOUNT;
        string[] memory descriptions1 = new string[](1);
        descriptions1[0] = "Milestone 1";

        vm.prank(client);
        address firstEscrow = factory.createEscrow(
            freelancer,
            arbiter,
            address(0),
            amounts1,
            descriptions1
        );

        address freelancer2 = makeAddr("freelancer2");
        address arbiter2 = makeAddr("arbiter2");

        uint256[] memory amounts2 = new uint256[](2);
        amounts2[0] = 1 ether;
        amounts2[1] = 1 ether;
        string[] memory descriptions2 = new string[](2);
        descriptions2[0] = "Phase 1";
        descriptions2[1] = "Phase 2";

        vm.prank(client);
        address secondEscrow = factory.createEscrow(
            freelancer2,
            arbiter2,
            address(0),
            amounts2,
            descriptions2
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

        // Individual stakeholder index counts
        assertEq(factory.getUserEscrows(freelancer).length, 1);
        assertEq(factory.getUserEscrows(freelancer2).length, 1);
        assertEq(factory.getUserEscrows(arbiter).length, 1);
        assertEq(factory.getUserEscrows(arbiter2).length, 1);
    }

    function test_SetFeeConfig_OwnerSuccess() public {
        address newRecipient = makeAddr("newRecipient");
        uint256 newFeeBps = 200; // 2%
        uint256 newRelayerFee = 0.0002 ether;

        factory.setFeeConfig(newRecipient, newFeeBps, newRelayerFee);

        assertEq(factory.feeRecipient(), newRecipient);
        assertEq(factory.feeBps(), newFeeBps);
        assertEq(factory.relayerFeePerTx(), newRelayerFee);
    }

    function test_RevertIf_SetFeeConfig_NonOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Only factory owner");
        factory.setFeeConfig(makeAddr("any"), 200, 0.0002 ether);
    }

    function test_RevertIf_UnderlyingEscrowRevertsOnZeroAddress() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ESCROW_AMOUNT;
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Milestone 1";

        vm.expectRevert(Escrow.Unauthorized.selector);
        vm.prank(client);
        factory.createEscrow(address(0), arbiter, address(0), amounts, descriptions);
    }

    function test_RevertIf_UnderlyingEscrowRevertsOnZeroAmount() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Milestone 1";

        vm.expectRevert(Escrow.InvalidDepositAmount.selector);
        vm.prank(client);
        factory.createEscrow(freelancer, arbiter, address(0), amounts, descriptions);
    }

    function test_RevertIf_UnderlyingEscrowRevertsOnArrayLengthMismatch() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 1 ether;

        string[] memory descriptions = new string[](1);
        descriptions[0] = "Milestone 1";

        vm.expectRevert(Escrow.InvalidDepositAmount.selector);
        vm.prank(client);
        factory.createEscrow(freelancer, arbiter, address(0), amounts, descriptions);
    }

    function test_RevertIf_ConstructorZeroAddressFeeRecipient() public {
        vm.expectRevert("Zero address fee recipient");
        new EscrowFactory(address(0), PROTOCOL_FEE_BPS, RELAYER_FEE_PER_TX);
    }

    function test_RevertIf_ConstructorFeeBpsExceedsMaximum() public {
        vm.expectRevert("Fee bps exceeds maximum");
        new EscrowFactory(feeRecipient, 1001, RELAYER_FEE_PER_TX);
    }
}