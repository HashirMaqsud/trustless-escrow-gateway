// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Escrow} from "./Escrow.sol";

/**
 * @title EscrowFactory
 * @notice Factory registry for deploying and tracking deterministic Escrow contract instances
 *         with protocol fee and EIP-712 support.
 */
contract EscrowFactory {
    // --- State Variables ---
    address public feeRecipient;
    uint256 public feeBps; // 100 = 1%
    address public immutable owner;

    uint256 public constant MAX_FEE_BPS = 1000; // Hard cap protocol fee to maximum 10%

    address[] public allEscrows;
    mapping(address => address[]) public userEscrows;

    // --- Events ---
    event EscrowCreated(
        address indexed escrowAddress,
        address indexed client,
        address indexed freelancer,
        address arbiter,
        address token,
        uint256 amount,
        uint256 feeBps
    );
    event FeeConfigUpdated(address indexed newRecipient, uint256 newFeeBps);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only factory owner");
        _;
    }

    /**
     * @notice Initializes factory with default fee parameters.
     * @param _feeRecipient Address collecting protocol fees for relayer operations.
     * @param _feeBps Initial protocol fee in basis points (e.g. 100 for 1%).
     */
    constructor(address _feeRecipient, uint256 _feeBps) {
        require(_feeRecipient != address(0), "Zero address fee recipient");
        require(_feeBps <= MAX_FEE_BPS, "Fee bps exceeds maximum");
        owner = msg.sender;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
    }

    /**
     * @notice Allows owner to update treasury destination or fee rate.
     */
    function setFeeConfig(address _newRecipient, uint256 _newFeeBps) external onlyOwner {
        require(_newRecipient != address(0), "Zero address fee recipient");
        require(_newFeeBps <= MAX_FEE_BPS, "Fee bps exceeds maximum");
        feeRecipient = _newRecipient;
        feeBps = _newFeeBps;
        emit FeeConfigUpdated(_newRecipient, _newFeeBps);
    }

    /**
     * @notice Deploys a new Escrow contract instance and registers it.
     * @param _freelancer Address of the service provider.
     * @param _arbiter Address of the dispute mediator.
     * @param _token Token address (address(0) for native ETH).
     * @param _amount Agreed contract value.
     * @return escrowAddress Address of the deployed Escrow instance.
     */
    function createEscrow(
        address _freelancer,
        address _arbiter,
        address _token,
        uint256 _amount
    ) external returns (address escrowAddress) {
        Escrow newEscrow = new Escrow(
            msg.sender,
            _freelancer,
            _arbiter,
            feeRecipient,
            _token,
            _amount,
            feeBps
        );

        escrowAddress = address(newEscrow);

        allEscrows.push(escrowAddress);
        userEscrows[msg.sender].push(escrowAddress);
        userEscrows[_freelancer].push(escrowAddress);

        emit EscrowCreated(
            escrowAddress,
            msg.sender,
            _freelancer,
            _arbiter,
            _token,
            _amount,
            feeBps
        );
    }

    /**
     * @notice Returns all deployed escrow addresses.
     */
    function getAllEscrows() external view returns (address[] memory) {
        return allEscrows;
    }

    /**
     * @notice Returns all escrow instances associated with a specific user.
     * @param _user Address of the client or freelancer.
     */
    function getUserEscrows(address _user) external view returns (address[] memory) {
        return userEscrows[_user];
    }
}