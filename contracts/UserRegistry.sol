// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Errors.sol";

/**
 * @title UserRegistry
 * @dev Manages user statistics and emits events for leaderboard tracking
 */
contract UserRegistry is Ownable {


    // Struct to store user statistics
    struct UserStats {
        uint256 totalGiven;      // Total amount given by user
        uint256 totalReceived;   // Total amount received by user
        uint256 timesReceived;   // Number of times user received kindness
        uint256 lastActionTime;  // Timestamp of last action
        string name;             // User's display name
        bool isInReceiverPool;   // Whether user is currently in receiver pool
    }

    // State variables
    address public system;             // Address of the KindnessSystem contract
    mapping(address => UserStats) public userStats;  // User statistics

    // Events
    event UserStatsUpdated(
        address indexed user,
        bool isGiving,
        uint256 amount,
        uint256 totalGiven,
        uint256 totalReceived,
        int256 netAmount
    );
    event UserNameUpdated(address indexed user, string name);
    event ReceiverPoolStatusUpdated(address indexed user, bool isInReceiverPool);
    event SystemUpdated(address indexed newSystem);
    /**
     * @dev Constructor sets the UserRegistry contract address
     * @param _system Address of the UserRegistry contract
     */
    constructor(address _system) Ownable(_system) {
        system = _system;
    }

    /**
     * @dev Modifier to restrict access to KindnessSystem contract
     */
    modifier onlySystem() {
        if (msg.sender != system) revert NotSystem();
        _;
    }

    /**
     * @dev Updates user statistics
     * @param user Address of the user
     * @param isGiving Whether the action is giving (true) or receiving (false)
     * @param amount Amount involved in the action
     */
    function updateUserStats(address user, bool isGiving, uint256 amount) external {
        // Allow calls from system or owner
        if (msg.sender != system && msg.sender != owner()) revert NotSystem();

        UserStats storage stats = userStats[user];

        if (isGiving) {
            unchecked { stats.totalGiven += amount; }
        } else {
            unchecked {
                stats.totalReceived += amount;
                stats.timesReceived++;
            }
        }

        stats.lastActionTime = block.timestamp;

        // Calculate net amount (positive if given more than received, negative if received more than given)
        int256 netAmount = int256(stats.totalGiven) - int256(stats.totalReceived);

        emit UserStatsUpdated(
            user,
            isGiving,
            amount,
            stats.totalGiven,
            stats.totalReceived,
            netAmount
        );
    }

    /**
     * @dev Sets or updates a user's display name
     * @param name The display name to set
     */
    function setName(string calldata name) external {
        uint256 nameLength = bytes(name).length;
        if (nameLength == 0) revert EmptyName();
        if (nameLength > 32) revert NameTooLong();

        userStats[msg.sender].name = name;
        emit UserNameUpdated(msg.sender, name);
    }

    /**
     * @dev Updates user's receiver pool status
     * @param user Address of the user
     * @param _isInReceiverPool New receiver pool status
     */
    function updateReceiverPoolStatus(address user, bool _isInReceiverPool) external {
        // Allow calls from system or owner
        if (msg.sender != system && msg.sender != owner()) revert NotSystem();

        userStats[user].isInReceiverPool = _isInReceiverPool;
        emit ReceiverPoolStatusUpdated(user, _isInReceiverPool);
    }

    /**
     * @dev Returns user statistics
     * @param user Address of the user
     * @return UserStats struct containing user's statistics
     */
    function getUserStats(address user) external view returns (UserStats memory) {
        return userStats[user];
    }

    /**
     * @dev Returns net amount for a user (positive for net givers, negative for net receivers)
     * @param user Address of the user
     * @return Net amount (positive if given more than received, negative if received more than given)
     */
    function getNetAmount(address user) external view returns (int256) {
        UserStats storage stats = userStats[user];
        return int256(stats.totalGiven) - int256(stats.totalReceived);
    }

    /**
     * @dev Checks if a user is in the receiver pool
     * @param user Address of the user
     * @return bool True if user is in receiver pool
     */
    function isInReceiverPool(address user) external view returns (bool) {
        return userStats[user].isInReceiverPool;
    }

    /**
     * @dev Updates the system address (only owner)
     * @param _newSystem Address of the new system contract
     */
    function updateSystem(address _newSystem) external onlyOwner {
        if (_newSystem == address(0)) revert ZeroAddress();
        system = _newSystem;
        emit SystemUpdated(_newSystem);
    }
}