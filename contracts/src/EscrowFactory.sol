// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Escrow} from "./Escrow.sol";

/**
 * @title EscrowFactory
 * @notice Factory registry for deploying and tracking deterministic Escrow contract instances.
 */
contract EscrowFactory {
    // --- State Variables ---
    address[] public allEscrows;
    mapping(address => address[]) public userEscrows;

    // --- Events ---
    event EscrowCreated(
        address indexed escrowAddress,
        address indexed client,
        address indexed freelancer,
        address arbiter,
        address token,
        uint256 amount
    );

    // --- Custom Errors ---
    error DeploymentFailed();

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
            _token,
            _amount
        );

        escrowAddress = address(newEscrow);
        if (escrowAddress == address(0)) revert DeploymentFailed();

        allEscrows.push(escrowAddress);
        userEscrows[msg.sender].push(escrowAddress);
        userEscrows[_freelancer].push(escrowAddress);

        emit EscrowCreated(
            escrowAddress,
            msg.sender,
            _freelancer,
            _arbiter,
            _token,
            _amount
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