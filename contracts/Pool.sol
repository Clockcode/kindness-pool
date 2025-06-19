// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./UserRegistry.sol";
import "./Errors.sol";

/**
 * @title Pool
 * @dev Manages the daily pool of contributions and distributions
 */
contract Pool is AccessControl {

    // Add the DISTRIBUTOR_ROLE constant
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    // State variables
    uint256 public dailyPool;                    // Current day's pool amount
    uint256 public lastDistributionTime;         // Timestamp of last distribution
    address[] public receivers;                  // List of current receivers
    // Question: Why is UserRegistry immutable? and why is it gas saving?
    UserRegistry public immutable userRegistry;  // Make immutable for gas savings
    mapping(address => uint256) public lastActionTime;
    uint256 public constant ACTION_COOLDOWN = 1 hours;
    mapping(address => uint256) public transactionCount;
    uint256 public constant MAX_TRANSACTIONS_PER_DAY = 10;
    mapping(address => uint256) public dailyContributions;  // Track daily contributions per user
    uint256 public unclaimedFunds;                         // Track unclaimed funds
    bool public distributionWindowOpen;                    // Track if distribution window is open

    // Track failed transfers
    struct FailedTransfer {
        address receiver;
        uint256 amount;
        uint256 timestamp;
        uint256 retryCount;
    }

    // Mapping to track failed transfers
    mapping(address => FailedTransfer) public failedTransfers;
    // Array of addresses with failed transfers for easy iteration
    address[] public failedReceivers;
    // Index mapping for efficient removal from failedReceivers array
    mapping(address => uint256) private failedReceiverIndex;

    // Events
    event KindnessGiven(address indexed giver, uint256 amount);
    event KindnessReceived(address indexed receiver, uint256 amount);
    event PoolDistributed(uint256 totalAmount, uint256 receiverCount);
    event EnteredReceiverPool(address indexed receiver);
    event TransferFailed(address indexed receiver, uint256 amount);
    event TransferRetried(address indexed receiver, uint256 amount, bool success);
    event UnclaimedFundsUpdated(uint256 amount);
    event DistributionWindowUpdated(bool isOpen);
    event EmergencyWithdrawalRequested(address indexed receiver, uint256 amount);
    event EmergencyWithdrawalCompleted(address indexed receiver, uint256 amount);

    // Constants
    uint256 public constant DISTRIBUTION_INTERVAL = 1 days;
    uint256 public constant DISTRIBUTION_WINDOW = 5 minutes;  // 5-minute window for distribution
    uint256 public constant MAX_RECEIVERS = 100; // Adjust based on your needs
    uint256 public constant MIN_KINDNESS_AMOUNT = 0.001 ether; // Minimum amount of 0.001 ETH
    uint256 public constant MAX_KINDNESS_AMOUNT = 1 ether;     // Maximum amount of 1 ETH
    uint256 public constant MAX_RETRIES = 3;
    uint256 public constant RETRY_COOLDOWN = 1 hours;

    /**
     * @dev Internal helper to add a failed receiver to tracking array
     */
    function _addFailedReceiver(address receiver) internal {
        if (failedReceiverIndex[receiver] == 0) {
            failedReceivers.push(receiver);
            failedReceiverIndex[receiver] = failedReceivers.length; // index + 1
        }
    }

    /**
     * @dev Internal helper to remove a failed receiver from tracking array
     */
    function _removeFailedReceiver(address receiver) internal {
        uint256 index = failedReceiverIndex[receiver];
        if (index > 0) {
            uint256 lastIndex = failedReceivers.length - 1;
            address lastReceiver = failedReceivers[lastIndex];
            failedReceivers[index - 1] = lastReceiver;
            failedReceiverIndex[lastReceiver] = index;
            failedReceivers.pop();
            delete failedReceiverIndex[receiver];
        }
    }

    modifier rateLimited() {
        if (block.timestamp < lastActionTime[msg.sender] + ACTION_COOLDOWN) revert TooManyActions();
        lastActionTime[msg.sender] = block.timestamp;
        _;
    }

    modifier transactionLimited() {
        if (transactionCount[msg.sender] >= MAX_TRANSACTIONS_PER_DAY) revert TooManyTransactions();
        // Question: How does unchecked work?
        unchecked { transactionCount[msg.sender]++; }
        _;
    }

    /**
     * @dev Constructor sets the UserRegistry contract address
     */
    constructor(address _system) {
        if (_system == address(0)) revert ZeroAddress();
        userRegistry = new UserRegistry(_system);
        _grantRole(DEFAULT_ADMIN_ROLE, _system);
    }

    /**
     * @dev Allows users to contribute to the daily pool
     * @param amount The amount to contribute (must be between 0.001 and 1 ETH)
     */
    function giveKindness(uint256 amount) external payable transactionLimited {
        if (amount < MIN_KINDNESS_AMOUNT) revert AmountTooLow();
        if (amount > MAX_KINDNESS_AMOUNT) revert AmountTooHigh();
        if (msg.value != amount) revert ValueMismatch();

        unchecked {
            dailyPool += amount;
            dailyContributions[msg.sender] += amount;
        }

        emit KindnessGiven(msg.sender, amount);
        userRegistry.updateUserStats(msg.sender, true, amount);
    }

    /**
     * @dev Allows users to enter the receiver pool
     */
    function enterReceiverPool() external rateLimited transactionLimited {
        if (userRegistry.isInReceiverPool(msg.sender)) revert AlreadyInReceiverPool();
        if (dailyContributions[msg.sender] != 0) revert ContributedToday();

        receivers.push(msg.sender);
        userRegistry.updateReceiverPoolStatus(msg.sender, true);
        emit EnteredReceiverPool(msg.sender);
    }

    /**
     * @dev Distributes the pool to all receivers
     * @dev Can only be called by distributor during distribution window
     * @dev Uses transfer() for EOA addresses
     */
    function distributePool() external onlyRole(DISTRIBUTOR_ROLE) {
        if (!isWithinDistributionWindow()) revert NotInDistributionWindow();
        if (hasDistributedToday()) revert AlreadyDistributedToday();
        if (dailyPool == 0) revert EmptyPool();
        if (receivers.length == 0) revert NoReceivers();
        if (receivers.length > MAX_RECEIVERS) revert TooManyReceivers();

        // Store values we need before making any state changes
        uint256 amountPerReceiver = dailyPool / receivers.length;
        uint256 totalAmount = dailyPool;
        uint256 receiverCount = receivers.length;
        uint256 failedAmount;

        // Store receivers array in memory to avoid storage reads
        address[] memory currentReceivers = receivers;

        // EFFECTS: Update all state variables before any external calls
        dailyPool = 0;
        // Update state before external calls to prevent reentrancy
        lastDistributionTime = block.timestamp;
        delete receivers;

        // Distribute to each receiver
        for (uint256 i = 0; i < currentReceivers.length; i++) {
            address receiver = currentReceivers[i];
            // Reset daily contributions
            dailyContributions[receiver] = 0;

            // Update user registry state before external call
            userRegistry.updateReceiverPoolStatus(receiver, false);
            userRegistry.updateUserStats(receiver, false, amountPerReceiver);

            // Make external call
            try this.transferToReceiver{gas: 21000}(receiver, amountPerReceiver) {
                emit PoolDistributed(amountPerReceiver, 1);
            } catch {
                // Track failed transfer
                failedTransfers[receiver] = FailedTransfer({
                    receiver: receiver,  // Store the receiver address
                    amount: amountPerReceiver,
                    timestamp: block.timestamp,
                    retryCount: 0
                });
                _addFailedReceiver(receiver);
                failedAmount += amountPerReceiver;
                emit TransferFailed(receiver, amountPerReceiver);
            }
            unchecked { i++; }
        }

        // Update unclaimed funds
        if (failedAmount > 0) {
            unchecked { unclaimedFunds += failedAmount; }
            emit UnclaimedFundsUpdated(unclaimedFunds);
        }

        emit PoolDistributed(totalAmount - failedAmount, receiverCount);
    }

    /**
     * @dev Returns the total amount of unclaimed funds
     * @return uint256 Amount of unclaimed funds
     */
    function getUnclaimedFunds() external view returns (uint256) {
        return unclaimedFunds;
    }

    /**
     * @dev Returns the current number of receivers
     */
    function getReceiverCount() external view returns (uint256) {
        return receivers.length;
    }

    /**
     * @dev Checks if current time is within the distribution window
     * @return bool True if within distribution window
     */
    function isWithinDistributionWindow() public view returns (bool) {
        // In test environment, use the state variable
        if (block.chainid == 31337) {
            return distributionWindowOpen;
        }
        // In production, use time-based window
        return (block.timestamp % 1 days) < DISTRIBUTION_WINDOW;
    }

    /**
     * @dev Checks if distribution has already happened today
     * @return bool True if distribution already occurred today
     */
    function hasDistributedToday() public view returns (bool) {
        if (lastDistributionTime == 0) return false;
        return (lastDistributionTime / 1 days) == (block.timestamp / 1 days);
    }

    /**
     * @dev Returns the next distribution time in UTC
     * @return uint256 Timestamp of the next distribution window
     */
    function getNextDistributionTime() public view returns (uint256) {
        if (lastDistributionTime == 0) {
            // If no distribution has happened yet, next distribution is at next UTC midnight
            return (block.timestamp / 1 days + 1) * 1 days;
        }

        uint256 lastDistDay = lastDistributionTime / 1 days;
        uint256 currentDay = block.timestamp / 1 days;

        if (lastDistDay < currentDay) {
            // If we haven't distributed today, next distribution is at next UTC midnight
            return (currentDay + 1) * 1 days;
        }
        return (currentDay + 2) * 1 days;
    }

    // Test-only function to control distribution window
    // This function should only be available in test environment
    function setDistributionWindow(bool _isOpen) external {
        // Only allow this in test environment
        // Chain ID 31337 is the standard Hardhat test network ID
        require(block.chainid == 31337, "Only available in test environment");
        // Only allow admin to control the window
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not authorized");

        distributionWindowOpen = _isOpen;
        emit DistributionWindowUpdated(_isOpen);
    }

    /**
     * @notice Internal function to transfer funds to a receiver
     * @param receiver The address to receive the funds
     * @param amount The amount to transfer
     */
    function transferToReceiver(address receiver, uint256 amount) external {
        if (msg.sender != address(this)) revert NotSystem();

        if (!payable(receiver).send(amount)) {
            failedTransfers[receiver] = FailedTransfer({
                receiver: receiver,
                amount: amount,
                timestamp: block.timestamp,
                retryCount: 0
            });
            _addFailedReceiver(receiver);
            revert TransferFailedErr();
        }
    }

    /**
     * @notice Retry a failed transfer
     * @param receiver The address of the failed transfer
     */
    function retryFailedTransfer(address receiver) external {
        if (!hasRole(DISTRIBUTOR_ROLE, msg.sender)) revert NotDistributor();
        FailedTransfer storage failed = failedTransfers[receiver];
        if (failed.amount == 0) revert NoFailedTransfer();
        if (failed.retryCount >= MAX_RETRIES) revert MaxRetriesExceeded();
        uint256 cooldown = RETRY_COOLDOWN * (1 << failed.retryCount);
        if (block.timestamp < failed.timestamp + cooldown) revert TooEarlyToRetry();

        uint256 amount = failed.amount;
        delete failedTransfers[receiver];
        _removeFailedReceiver(receiver);

        try this.transferToReceiver{gas: 21000}(receiver, amount) {
            emit TransferRetried(receiver, amount, true);
            emit KindnessReceived(receiver, amount);
            unchecked { unclaimedFunds -= amount; }
        } catch {
            failedTransfers[receiver] = FailedTransfer({
                receiver: receiver,  // Store the receiver address
                amount: amount,
                timestamp: block.timestamp,
                retryCount: failed.retryCount + 1
            });
            _addFailedReceiver(receiver);
            emit TransferRetried(receiver, amount, false);
        }
    }

    /**
     * @notice Get the amount of a failed transfer
     * @param receiver The address to check
     * @return The amount of the failed transfer
     */
    function getFailedTransferAmount(address receiver) external view returns (uint256) {
        return failedTransfers[receiver].amount;
    }

    /**
     * @notice Request emergency withdrawal for a failed transfer
     * @param receiver The address of the failed transfer
     */
    function requestEmergencyWithdrawal(address receiver) external {
        FailedTransfer storage failed = failedTransfers[receiver];
        if (failed.amount == 0) revert NoFailedTransfer();

        emit EmergencyWithdrawalRequested(receiver, failed.amount);
    }

    /**
     * @notice Complete emergency withdrawal for a failed transfer
     * @param receiver The address of the failed transfer
     */
    function completeEmergencyWithdrawal(address receiver) external {
        FailedTransfer storage failed = failedTransfers[receiver];
        if (failed.amount == 0) revert NoFailedTransfer();

        uint256 amount = failed.amount;
        delete failedTransfers[receiver];
        _removeFailedReceiver(receiver);

        try this.transferToReceiver{gas: 21000}(receiver, amount) {
            emit EmergencyWithdrawalCompleted(receiver, amount);
            unchecked { unclaimedFunds -= amount; }
        } catch {
            failedTransfers[receiver] = FailedTransfer({
                receiver: receiver,
                amount: amount,
                timestamp: block.timestamp,
                retryCount: failed.retryCount + 1
            });
            _addFailedReceiver(receiver);
            emit TransferFailed(receiver, amount);
        }
    }

    function getFailedTransfers() external view returns (address[] memory) {
        return failedReceivers;
    }
}