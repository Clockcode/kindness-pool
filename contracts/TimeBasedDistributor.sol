// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./Pool.sol";
import "./Errors.sol";

/**
 * @title TimeBasedDistributor
 * @dev Contract that handles the time-based distribution of the pool
 * This contract is responsible for calling the distributePool function
 * only during the designated distribution window
 */
contract TimeBasedDistributor is AccessControl {
    // Rename for clarity
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Add failed transfer handling
    function handleFailedTransfers() external {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();

        // Get all failed transfers
        address[] memory failedAddresses = pool.getFailedTransfers();

        for (uint256 i = 0; i < failedAddresses.length; i++) {
            address receiver = failedAddresses[i];
            uint256 amount = pool.getFailedTransferAmount(receiver);

            // Try to retry the transfer
            try pool.retryFailedTransfer(receiver) {
                emit TransferRetried(receiver, amount, true);
            } catch {
                // If retry fails, request emergency withdrawal
                pool.requestEmergencyWithdrawal(receiver);
                emit EmergencyWithdrawalRequested(receiver, amount);
            }
        }
    }

    // Add the DISTRIBUTOR_ROLE constant
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    // The Pool contract that this distributor will interact with
    Pool public pool; // Cannot be immutable as it needs to be updatable

    // Events for tracking important actions
    event DistributionAttempted(uint256 timestamp, bool success);
    event PoolAddressUpdated(address oldPool, address newPool);
    event FailedTransfersAttempted(address[] failedTransfers);
    event TransferRetried(address receiver, uint256 amount, bool success);
    event EmergencyWithdrawalRequested(address receiver, uint256 amount);

    /**
     * @dev Constructor sets the initial pool address
     * @param _pool Address of the Pool contract
     */
    constructor(address _pool) {
        if (_pool == address(0)) revert ZeroAddress();
        pool = Pool(_pool);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Attempts to distribute the pool if within the distribution window
     * This function can be called by anyone, but will only succeed if:
     * 1. We're within the distribution window
     * 2. Distribution hasn't happened today
     * 3. The pool has funds to distribute
     */
    function attemptDistribution() external {
        if (!hasRole(DISTRIBUTOR_ROLE, msg.sender)) revert NotDistributor();
        if (!pool.isWithinDistributionWindow()) revert NotInDistributionWindow();
        if (pool.hasDistributedToday()) revert AlreadyDistributedToday();

        // Attempt to distribute the pool
        try pool.distributePool() {
            emit DistributionAttempted(block.timestamp, true);
        } catch {
            emit DistributionAttempted(block.timestamp, false);
            revert DistributionFailed();
        }
    }

    /**
     * @dev Updates the pool address (only owner)
     * @param _newPool Address of the new Pool contract
     */
    function setPool(address _newPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newPool == address(0)) revert ZeroAddress();
        address oldPool = address(pool);
        pool = Pool(_newPool);
        emit PoolAddressUpdated(oldPool, _newPool);
    }

    /**
     * @dev Returns the next distribution time
     * @return uint256 Timestamp of the next distribution window
     */
    function getNextDistributionTime() external view returns (uint256) {
        return pool.getNextDistributionTime();
    }

    function attemptFailedTransfers() external {
        // Get all failed transfers
        address[] memory failedAddresses = pool.getFailedTransfers();
        // Attempt to retry each one
        for (uint256 i = 0; i < failedAddresses.length; i++) {
            address receiver = failedAddresses[i];
            pool.retryFailedTransfer(receiver);
        }
        // Log results
        emit FailedTransfersAttempted(failedAddresses);
    }
}
