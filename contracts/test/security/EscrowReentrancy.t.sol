// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";

// Malicious Freelancer contract designed to reenter Escrow on receiving ETH
contract MaliciousFreelancer {
    Escrow public targetEscrow;
    uint256 public attackCount;

    constructor() {}

    function setTarget(address _escrow) external {
        targetEscrow = Escrow(_escrow);
    }

    function submitWork(string calldata url) external {
        targetEscrow.submitDeliverable(url);
    }

    // Fallback attempts reentrant call back into releaseFunds()
    receive() external payable {
        if (attackCount < 2) {
            attackCount++;
            // Reentrancy attempt: call releaseFunds again while execution is inside previous call
            targetEscrow.releaseFunds();
        }
    }
}

// Malicious Client contract designed to reenter Escrow during dispute payout
contract MaliciousDisputeAttacker {
    Escrow public targetEscrow;
    uint256 public attackCount;

    constructor() {}

    function setTarget(address _escrow) external {
        targetEscrow = Escrow(_escrow);
    }

    // Fallback attempts reentrant call into resolveDispute
    receive() external payable {
        if (attackCount < 2) {
            attackCount++;
            // Reentrancy attempt: call resolveDispute again during payout
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

    uint256 public constant ESCROW_AMOUNT = 1 ether;

    function setUp() public {
        attackerFreelancer = new MaliciousFreelancer();
        attackerClient = new MaliciousDisputeAttacker();

        vm.deal(client, 10 ether);
        vm.deal(address(attackerClient), 10 ether);
    }

    function test_Security_ReentrancyBlocked_OnReleaseFunds() public {
        escrow = new Escrow(
            client,
            address(attackerFreelancer),
            arbiter,
            address(0),
            ESCROW_AMOUNT
        );

        attackerFreelancer.setTarget(address(escrow));

        // Client funds escrow
        vm.prank(client);
        escrow.fund{value: ESCROW_AMOUNT}();

        // Freelancer submits deliverable
        attackerFreelancer.submitWork("https://malicious-exploit.com");

        // The reentrant call triggers ReentrancyGuard, causing low-level call to return false,
        // which reverts execution strictly with TransferFailed
        vm.expectRevert(Escrow.TransferFailed.selector);

        vm.prank(client);
        escrow.releaseFunds();

        // State check: Ensure funds were not stolen
        assertEq(address(escrow).balance, ESCROW_AMOUNT);
    }

    function test_Security_ReentrancyBlocked_OnDisputeResolution() public {
        escrow = new Escrow(
            address(attackerClient),
            makeAddr("honestFreelancer"),
            arbiter,
            address(0),
            ESCROW_AMOUNT
        );

        attackerClient.setTarget(address(escrow));

        // Attacker client funds and disputes
        vm.prank(address(attackerClient));
        escrow.fund{value: ESCROW_AMOUNT}();

        vm.prank(address(attackerClient));
        escrow.raiseDispute();

        // The reentrant call triggers ReentrancyGuard, causing low-level call to return false,
        // which reverts execution strictly with TransferFailed
        vm.expectRevert(Escrow.TransferFailed.selector);

        vm.prank(arbiter);
        escrow.resolveDispute(ESCROW_AMOUNT, 0);

        // State check: Ensure vault balance remains fully intact
        assertEq(address(escrow).balance, ESCROW_AMOUNT);
    }
}