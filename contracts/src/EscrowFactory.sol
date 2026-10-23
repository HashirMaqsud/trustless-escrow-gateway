// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Escrow} from "./Escrow.sol";

/**
 * @title EscrowFactory
 * @notice Factory registry for deploying and tracking deterministic Escrow contract instances
 *         with protocol fee, dynamic relayer reimbursement pool, and complete indexing for all roles.
 */
contract EscrowFactory {
    address public feeRecipient;
    uint256 public feeBps; // 100 = 1%
    uint256 public relayerFeePerTx; // Reimbursement unit per gasless meta-transaction
    address public immutable owner;

    uint256 public constant MAX_FEE_BPS = 1000; // 10% maximum fee cap

    address[] public allEscrows;
    mapping(address => address[]) public userEscrows;

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
    event FeeConfigUpdated(address indexed newRecipient, uint256 newFeeBps, uint256 newRelayerFee);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only factory owner");
        _;
    }

    constructor(address _feeRecipient, uint256 _feeBps, uint256 _relayerFeePerTx) {
        require(_feeRecipient != address(0), "Zero address fee recipient");
        require(_feeBps <= MAX_FEE_BPS, "Fee bps exceeds maximum");
        owner = msg.sender;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
        relayerFeePerTx = _relayerFeePerTx;
    }

    function setFeeConfig(address _newRecipient, uint256 _newFeeBps, uint256 _newRelayerFee) external onlyOwner {
        require(_newRecipient != address(0), "Zero address fee recipient");
        require(_newFeeBps <= MAX_FEE_BPS, "Fee bps exceeds maximum");
        feeRecipient = _newRecipient;
        feeBps = _newFeeBps;
        relayerFeePerTx = _newRelayerFee;
        emit FeeConfigUpdated(_newRecipient, _newFeeBps, _newRelayerFee);
    }

    /**
     * @notice Deploys a new Escrow contract instance and registers it for Client, Freelancer, and Arbiter.
     */
    function createEscrow(
        address _freelancer,
        address _arbiter,
        address _token,
        uint256[] calldata _milestoneAmounts,
        string[] calldata _milestoneDescriptions
    ) external returns (address escrowAddress) {
        Escrow newEscrow = new Escrow(
            msg.sender,
            _freelancer,
            _arbiter,
            feeRecipient,
            _token,
            _milestoneAmounts,
            _milestoneDescriptions,
            feeBps,
            relayerFeePerTx
        );

        escrowAddress = address(newEscrow);

        allEscrows.push(escrowAddress);

        // Indexing for all 3 stakeholders (Fixes Bug 2)[cite: 3, 6]
        userEscrows[msg.sender].push(escrowAddress);
        userEscrows[_freelancer].push(escrowAddress);
        userEscrows[_arbiter].push(escrowAddress);

        emit EscrowCreated(
            escrowAddress,
            msg.sender,
            _freelancer,
            _arbiter,
            _token,
            newEscrow.TOTAL_AMOUNT(),
            feeBps,
            newEscrow.RELAYER_FEE_PER_TX(),
            newEscrow.TOTAL_RELAYER_POOL()
        );
    }

    function getAllEscrows() external view returns (address[] memory) {
        return allEscrows;
    }

    function getUserEscrows(address _user) external view returns (address[] memory) {
        return userEscrows[_user];
    }
}