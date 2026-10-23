// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";

// Malicious Freelancer contract designed to reenter Escrow on receiving ETH
contract MaliciousFreelancer {
    Escrow public targetEscrow;
    uint256 public attackCount;

    function setTarget(address _escrow) external {
        targetEscrow = Escrow(_escrow);
    }

    function submitWork(
        string calldata url,
        string calldata ipfsHash,
        string calldata notes,
        uint256 milestoneIndex
    ) external {
        targetEscrow.submitDeliverable(url, ipfsHash, notes, milestoneIndex);
    }

    // Fallback attempts reentrant call back into releaseFunds()
    receive() external payable {
        if (attackCount < 2) {
            attackCount++;
            targetEscrow.releaseFunds();
        }
    }
}

// Malicious Client contract designed to reenter Escrow during dispute payout
contract MaliciousDisputeAttacker {
    Escrow public targetEscrow;
    uint256 public attackCount;

    function setTarget(address _escrow) external {
        targetEscrow = Escrow(_escrow);
    }

    // Fallback attempts reentrant call into resolveDispute
    receive() external payable {
        if (attackCount < 2) {
            attackCount++;
            targetEscrow.resolveDispute(1 ether, 0);
        }
    }
}

contract EscrowReentrancyTest is Test {
    Escrow public escrow;
    MaliciousFreelancer public attackerFreelancer;
    MaliciousDisputeAttacker public attackerClient;

    address public client = makeAddr("client");
    address public arbiter = makeAddr("arbiter");
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 public constant ESCROW_AMOUNT = 1 ether;
    uint256 public constant PROTOCOL_FEE_BPS = 100; // 1%
    uint256 public constant RELAYER_FEE_PER_TX = 0.0001 ether;

    function setUp() public {
        attackerFreelancer = new MaliciousFreelancer();
        attackerClient = new MaliciousDisputeAttacker();

        vm.deal(client, 10 ether);
        vm.deal(address(attackerClient), 10 ether);
    }

    function test_Security_ReentrancyBlocked_OnReleaseFunds() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ESCROW_AMOUNT;
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Scope";

        escrow = new Escrow(
            client,
            address(attackerFreelancer),
            arbiter,
            feeRecipient,
            address(0),
            amounts,
            descriptions,
            PROTOCOL_FEE_BPS,
            RELAYER_FEE_PER_TX
        );

        attackerFreelancer.setTarget(address(escrow));

        uint256 fee = (ESCROW_AMOUNT * PROTOCOL_FEE_BPS) / 10000;
        uint256 relayerPool = escrow.TOTAL_RELAYER_POOL();
        uint256 totalRequired = ESCROW_AMOUNT + fee + relayerPool;

        // Client funds escrow
        vm.prank(client);
        escrow.fund{value: totalRequired}();

        // Freelancer submits deliverable
        attackerFreelancer.submitWork(
            "https://malicious-exploit.com",
            "ipfs://QmMalicious",
            "Exploit payload",
            0
        );

        // Call reverts due to ReentrancyGuard triggering on the recursive releaseFunds call
        vm.expectRevert(Escrow.TransferFailed.selector);

        vm.prank(client);
        escrow.releaseFunds();

        // Ensure locked escrow funds were not drained
        assertEq(address(escrow).balance, ESCROW_AMOUNT + relayerPool);
    }

    function test_Security_ReentrancyBlocked_OnDisputeResolution() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ESCROW_AMOUNT;
        string[] memory descriptions = new string[](1);
        descriptions[0] = "Scope";

        escrow = new Escrow(
            address(attackerClient),
            makeAddr("honestFreelancer"),
            arbiter,
            feeRecipient,
            address(0),
            amounts,
            descriptions,
            PROTOCOL_FEE_BPS,
            RELAYER_FEE_PER_TX
        );

        attackerClient.setTarget(address(escrow));

        uint256 fee = (ESCROW_AMOUNT * PROTOCOL_FEE_BPS) / 10000;
        uint256 relayerPool = escrow.TOTAL_RELAYER_POOL();
        uint256 totalRequired = ESCROW_AMOUNT + fee + relayerPool;

        // Attacker client funds and disputes
        vm.prank(address(attackerClient));
        escrow.fund{value: totalRequired}();

        vm.prank(address(attackerClient));
        escrow.raiseDispute();

        // Call reverts due to ReentrancyGuard triggering on the recursive resolveDispute call
        vm.expectRevert(Escrow.TransferFailed.selector);

        vm.prank(arbiter);
        escrow.resolveDispute(ESCROW_AMOUNT, 0);

        // Ensure vault balance remains fully intact
        assertEq(address(escrow).balance, ESCROW_AMOUNT + relayerPool);
    }
}