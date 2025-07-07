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
    uint256 public dailyPool; // Current day's pool amount
    uint256 public lastDistributionTime; // Timestamp of last distribution
    address[] public receivers; // List of current receivers
    // Question: Why is UserRegistry immutable? and why is it gas saving?
    UserRegistry public immutable userRegistry; // Make immutable for gas savings
    mapping(address => uint256) public lastActionTime;
    uint256 public constant ACTION_COOLDOWN = 1 hours;
    mapping(address => uint256) public transactionCount;
    uint256 public constant MAX_TRANSACTIONS_PER_DAY = 10;
    mapping(address => uint256) public dailyContributions; // Track daily contributions per user
    uint256 public unclaimedFunds; // Track unclaimed funds
    bool public distributionWindowOpen; // Track if distribution window is open

    // Batch distribution state
    uint256 public distributionIndex; // Current index in receivers array for batch processing
    bool public distributionInProgress; // Track if distribution is currently in progress
    uint256 public distributionStartTime; // When current distribution started
    address[] public distributionSnapshot; // Snapshot of receivers at distribution start

    // Auto-retry state
    uint256 public lastAutoRetryTime; // Last time auto-retry was attempted

    // Daily reset mechanism
    uint256 public currentDay; // Current day counter (increments every 24 hours)
    mapping(address => uint256) public userLastDay; // Track when user's data was last reset
    mapping(address => uint256) public dailyReceiverEntries; // Track daily receiver pool entries per user
    mapping(address => uint256) public dailyReceiverExits; // Track daily receiver pool exits per user
    mapping(address => uint256) public lastReceiverPoolAction; // Track last receiver pool action time
    mapping(address => uint256) public dailyWithdrawals; // Track daily withdrawals per user
    mapping(address => uint256) public lastWithdrawalTime; // Track last withdrawal time per user

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
    event LeftReceiverPool(address indexed receiver);
    event TransferFailed(address indexed receiver, uint256 amount);
    event TransferRetried(address indexed receiver, uint256 amount, bool success);
    event UnclaimedFundsUpdated(uint256 amount);
    event DistributionWindowUpdated(bool isOpen);
    event EmergencyWithdrawalRequested(address indexed receiver, uint256 amount);
    event EmergencyWithdrawalCompleted(address indexed receiver, uint256 amount);
    event EmergencyExitCompleted(address indexed user);
    event ContributionWithdrawn(address indexed user, uint256 amount);
    event WithdrawalFailed(address indexed user, uint256 amount);
    event BatchDistributed(uint256 batchSize, uint256 processedCount, uint256 totalReceivers);
    event DistributionStopped(uint256 timestamp);
    event AutoRetryCompleted(uint256 retriedCount, uint256 successCount);

    // Constants
    uint256 public constant DISTRIBUTION_INTERVAL = 1 days;
    uint256 public constant DISTRIBUTION_WINDOW = 5 minutes; // 5-minute window for distribution
    uint256 public constant MAX_RECEIVERS = 100; // Adjust based on your needs
    uint256 public constant MIN_KINDNESS_AMOUNT = 0.001 ether; // Minimum amount of 0.001 ETH
    uint256 public constant MAX_KINDNESS_AMOUNT = 1 ether; // Maximum amount of 1 ETH
    uint256 public constant MIN_POOL_BALANCE = 0.01 ether; // Minimum pool balance required to distribute
    uint256 public constant MAX_RETRIES = 3;
    uint256 public constant RETRY_COOLDOWN = 1 hours;
    uint256 public constant DISTRIBUTION_BATCH_SIZE = 25; // Maximum receivers per distribution batch
    uint256 public constant MAX_AUTO_RETRIES_PER_TX = 5; // Maximum retries to process in one transaction

    // Daily limits
    uint256 public constant MAX_DAILY_CONTRIBUTION = 5 ether; // Maximum daily contribution per user
    uint256 public constant MAX_DAILY_RECEIVER_ENTRIES = 1; // Maximum receiver pool entries per day
    uint256 public constant MAX_DAILY_RECEIVER_EXITS = 1; // Maximum receiver pool exits per day
    uint256 public constant RECEIVER_POOL_COOLDOWN = 30 minutes; // Cooldown between receiver pool actions

    // Withdrawal limits
    uint256 public constant MAX_DAILY_WITHDRAWALS = 3; // Maximum withdrawals per day
    uint256 public constant WITHDRAWAL_COOLDOWN = 2 hours; // Cooldown between withdrawals
    uint256 public constant MIN_WITHDRAWAL_AMOUNT = 0.001 ether; // Minimum withdrawal amount

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

    /**
     * @dev Internal helper to update the current day counter
     */
    function _updateDay() internal {
        uint256 dayNumber = block.timestamp / 1 days;
        if (dayNumber > currentDay) {
            currentDay = dayNumber;
        }
    }

    /**
     * @dev Internal helper to check if user's daily data needs to be reset
     */
    function _isNewDay(address user) internal view returns (bool) {
        return userLastDay[user] < currentDay;
    }

    /**
     * @dev Internal helper to reset user's daily data
     */
    function _resetDailyData(address user) internal {
        if (_isNewDay(user)) {
            dailyContributions[user] = 0;
            dailyReceiverEntries[user] = 0;
            dailyReceiverExits[user] = 0;
            dailyWithdrawals[user] = 0;
            transactionCount[user] = 0;
            userLastDay[user] = currentDay;
        }
    }

    /**
     * @dev Internal helper to remove a user from the receivers array
     */
    function _removeFromReceivers(address user) internal {
        for (uint256 i = 0; i < receivers.length; i++) {
            if (receivers[i] == user) {
                // Move the last element to the current position
                receivers[i] = receivers[receivers.length - 1];
                receivers.pop();
                break;
            }
        }
    }

    modifier dailyReset() {
        _updateDay();
        _resetDailyData(msg.sender);
        _;
    }

    modifier rateLimited() {
        if (block.timestamp < lastActionTime[msg.sender] + ACTION_COOLDOWN) revert TooManyActions();
        lastActionTime[msg.sender] = block.timestamp;
        _;
    }

    modifier transactionLimited() {
        if (transactionCount[msg.sender] >= MAX_TRANSACTIONS_PER_DAY) revert TooManyTransactions();
        // Question: How does unchecked work?
        unchecked {
            transactionCount[msg.sender]++;
        }
        _;
    }

    modifier receiverPoolCooldown() {
        if (block.timestamp < lastReceiverPoolAction[msg.sender] + RECEIVER_POOL_COOLDOWN) {
            revert TooManyActions();
        }
        lastReceiverPoolAction[msg.sender] = block.timestamp;
        _;
    }

    /**
     * @dev Modifier to enforce withdrawal cooldown
     */
    modifier withdrawalCooldown() {
        if (block.timestamp < lastWithdrawalTime[msg.sender] + WITHDRAWAL_COOLDOWN) {
            revert WithdrawalCooldownActive();
        }
        lastWithdrawalTime[msg.sender] = block.timestamp;
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
    function giveKindness(uint256 amount) external payable dailyReset transactionLimited {
        if (amount < MIN_KINDNESS_AMOUNT) revert AmountTooLow();
        if (amount > MAX_KINDNESS_AMOUNT) revert AmountTooHigh();
        if (msg.value != amount) revert ValueMismatch();

        // Check daily contribution limit
        if (dailyContributions[msg.sender] + amount > MAX_DAILY_CONTRIBUTION) {
            revert DailyContributionLimitExceeded();
        }

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
    function enterReceiverPool() external dailyReset receiverPoolCooldown transactionLimited {
        if (userRegistry.isInReceiverPool(msg.sender)) revert AlreadyInReceiverPool();

        if (dailyContributions[msg.sender] != 0) revert ContributedToday();

        // Check daily receiver entry limit
        if (dailyReceiverEntries[msg.sender] >= MAX_DAILY_RECEIVER_ENTRIES) {
            revert DailyReceiverEntryLimitExceeded();
        }

        unchecked {
            dailyReceiverEntries[msg.sender]++;
        }
        receivers.push(msg.sender);
        userRegistry.updateReceiverPoolStatus(msg.sender, true);
        emit EnteredReceiverPool(msg.sender);
    }

    /**
     * @dev Allows users to leave the receiver pool
     */
    function leaveReceiverPool() external dailyReset receiverPoolCooldown transactionLimited {
        if (!userRegistry.isInReceiverPool(msg.sender)) revert NotInReceiverPool();

        // Check daily receiver exit limit
        if (dailyReceiverExits[msg.sender] >= MAX_DAILY_RECEIVER_EXITS) {
            revert DailyReceiverExitLimitExceeded();
        }

        unchecked {
            dailyReceiverExits[msg.sender]++;
        }

        // Remove user from receivers array
        _removeFromReceivers(msg.sender);
        userRegistry.updateReceiverPoolStatus(msg.sender, false);
        emit LeftReceiverPool(msg.sender);
    }

    /**
     * @dev Allows users to withdraw their contribution from the current day's pool
     * @param amount Amount to withdraw (must be <= user's daily contribution)
     */
    function withdrawContribution(uint256 amount) external dailyReset withdrawalCooldown transactionLimited {
        if (amount < MIN_WITHDRAWAL_AMOUNT) revert WithdrawalAmountTooLow();

        // Check if user has sufficient contribution to withdraw
        if (amount > dailyContributions[msg.sender]) revert InsufficientContribution();

        // Check daily withdrawal limit
        if (dailyWithdrawals[msg.sender] >= MAX_DAILY_WITHDRAWALS) {
            revert DailyWithdrawalLimitExceeded();
        }

        // Check if pool has sufficient balance
        if (amount > dailyPool) revert InsufficientContractBalance();
        if (address(this).balance < amount) revert InsufficientContractBalance();

        // Update state before external call (checks-effects-interactions)
        unchecked {
            dailyPool -= amount;
            dailyContributions[msg.sender] -= amount;
            dailyWithdrawals[msg.sender]++;
        }

        // Attempt withdrawal
        (bool success, ) = payable(msg.sender).call{ value: amount }("");
        if (!success) {
            // Revert state changes if withdrawal failed
            unchecked {
                dailyPool += amount;
                dailyContributions[msg.sender] += amount;
                dailyWithdrawals[msg.sender]--;
            }
            emit WithdrawalFailed(msg.sender, amount);
            revert TransferFailedErr();
        }

        emit ContributionWithdrawn(msg.sender, amount);
        userRegistry.updateUserStatsWithdrawal(msg.sender, amount); // Reduce totalGiven by withdrawal amount
    }

    /**
     * @dev Emergency exit function for administrators to remove users from receiver pool
     * @dev Only callable by admin role
     * @param user Address of the user to remove
     */
    function emergencyExitReceiverPool(address user) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!userRegistry.isInReceiverPool(user)) revert NotInReceiverPool();

        // Remove user from receivers array
        _removeFromReceivers(user);
        userRegistry.updateReceiverPoolStatus(user, false);
        emit EmergencyExitCompleted(user);
    }

    /**
     * @dev Start batch distribution process
     * @notice Initiates distribution in batches to prevent gas limit issues
     */
    function startDistribution() external onlyRole(DISTRIBUTOR_ROLE) {
        if (!isWithinDistributionWindow()) revert NotInDistributionWindow();
        if (hasDistributedToday()) revert AlreadyDistributedToday();
        if (dailyPool == 0) revert EmptyPool();
        if (receivers.length == 0) revert NoReceivers();
        if (receivers.length > MAX_RECEIVERS) revert TooManyReceivers();
        if (address(this).balance < dailyPool) revert InsufficientContractBalance();
        if (dailyPool < MIN_POOL_BALANCE) revert PoolBalanceBelowMinimum();
        if (distributionInProgress) revert DistributionInProgress();

        // Attempt to retry failed transfers before starting new distribution
        _autoRetryDuringDistribution();

        // Initialize distribution state
        distributionInProgress = true;
        distributionIndex = 0;
        distributionStartTime = block.timestamp;

        // Create snapshot of current receivers
        delete distributionSnapshot;
        for (uint256 i = 0; i < receivers.length; i++) {
            distributionSnapshot.push(receivers[i]);
        }

        // Clear receivers array (new users can't join during distribution)
        delete receivers;

        // Start first batch
        _processBatch();
    }

    /**
     * @dev Continue batch distribution process
     * @notice Processes the next batch of receivers
     */
    function continueDistribution() external onlyRole(DISTRIBUTOR_ROLE) {
        if (!distributionInProgress) revert NoDistributionInProgress();
        if (distributionIndex >= distributionSnapshot.length) revert DistributionAlreadyComplete();

        _processBatch();
    }

    /**
     * @dev Process a batch of receivers
     * @notice Internal function to handle distribution logic
     */
    function _processBatch() internal {
        uint256 startIndex = distributionIndex;
        uint256 endIndex = startIndex + DISTRIBUTION_BATCH_SIZE;
        if (endIndex > distributionSnapshot.length) {
            endIndex = distributionSnapshot.length;
        }

        uint256 amountPerReceiver = dailyPool / distributionSnapshot.length;
        uint256 failedAmount = 0;

        // Process batch of receivers
        for (uint256 i = startIndex; i < endIndex; i++) {
            address receiver = distributionSnapshot[i];

            // Reset all daily data for the receiver
            dailyContributions[receiver] = 0;
            dailyReceiverEntries[receiver] = 0;
            dailyReceiverExits[receiver] = 0;
            userLastDay[receiver] = currentDay;

            // Update user registry state before external call
            userRegistry.updateReceiverPoolStatus(receiver, false);
            userRegistry.updateUserStats(receiver, false, amountPerReceiver);

            // Make external call with gas limit
            try this.transferToReceiver{ gas: 21000 }(receiver, amountPerReceiver) {
                emit KindnessReceived(receiver, amountPerReceiver);
            } catch {
                // Track failed transfer
                failedTransfers[receiver] = FailedTransfer({
                    receiver: receiver,
                    amount: amountPerReceiver,
                    timestamp: block.timestamp,
                    retryCount: 0
                });
                _addFailedReceiver(receiver);
                failedAmount += amountPerReceiver;
                emit TransferFailed(receiver, amountPerReceiver);
            }
        }

        // Update distribution progress
        distributionIndex = endIndex;

        // Update unclaimed funds if there were failures
        if (failedAmount > 0) {
            unchecked {
                unclaimedFunds += failedAmount;
            }
            emit UnclaimedFundsUpdated(unclaimedFunds);
        }

        // Check if distribution is complete
        if (distributionIndex >= distributionSnapshot.length) {
            _finalizeDistribution();
        }

        emit BatchDistributed(endIndex - startIndex, distributionIndex, distributionSnapshot.length);
    }

    /**
     * @dev Finalize the distribution process
     * @notice Complete distribution and reset state
     */
    function _finalizeDistribution() internal {
        // Update state
        lastDistributionTime = block.timestamp;
        dailyPool = 0;
        distributionInProgress = false;
        distributionIndex = 0;

        // Clear snapshot
        delete distributionSnapshot;

        emit PoolDistributed(address(this).balance, distributionSnapshot.length);
    }

    /**
     * @dev Emergency stop for distribution
     * @notice Allow admin to stop distribution in case of issues
     */
    function emergencyStopDistribution() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!distributionInProgress) revert NoDistributionInProgress();

        distributionInProgress = false;
        distributionIndex = 0;
        delete distributionSnapshot;

        emit DistributionStopped(block.timestamp);
    }

    /**
     * @dev Legacy function for backward compatibility
     * @notice Use startDistribution() for new implementations
     */
    function distributePool() external onlyRole(DISTRIBUTOR_ROLE) {
        if (!isWithinDistributionWindow()) revert NotInDistributionWindow();
        if (hasDistributedToday()) revert AlreadyDistributedToday();
        if (dailyPool == 0) revert EmptyPool();
        if (receivers.length == 0) revert NoReceivers();
        if (receivers.length > MAX_RECEIVERS) revert TooManyReceivers();
        if (address(this).balance < dailyPool) revert InsufficientContractBalance();
        if (dailyPool < MIN_POOL_BALANCE) revert PoolBalanceBelowMinimum();
        if (distributionInProgress) revert DistributionInProgress();

        // Initialize distribution state
        distributionInProgress = true;
        distributionIndex = 0;
        distributionStartTime = block.timestamp;

        // Create snapshot of current receivers
        delete distributionSnapshot;
        for (uint256 i = 0; i < receivers.length; i++) {
            distributionSnapshot.push(receivers[i]);
        }

        // Clear receivers array (new users can't join during distribution)
        delete receivers;

        // Start first batch
        _processBatch();
    }

    /**
     * @dev Automatically retry failed transfers
     * @notice Public function that anyone can call to help process failed transfers
     * @dev Processes up to MAX_AUTO_RETRIES_PER_TX failed transfers per call
     */
    function autoRetryFailedTransfers() external {
        uint256 processedCount = 0;
        uint256 successCount = 0;

        // Process failed transfers with circuit breaker
        for (uint256 i = 0; i < failedReceivers.length && processedCount < MAX_AUTO_RETRIES_PER_TX; i++) {
            address receiver = failedReceivers[i];
            FailedTransfer storage failed = failedTransfers[receiver];

            // Skip if no failed transfer or max retries exceeded
            if (failed.amount == 0 || failed.retryCount >= MAX_RETRIES) {
                continue;
            }

            // Check if retry cooldown has passed
            uint256 cooldown = RETRY_COOLDOWN * (1 << failed.retryCount);
            if (block.timestamp < failed.timestamp + cooldown) {
                continue;
            }

            // Attempt retry
            if (_attemptTransferRetry(receiver)) {
                successCount++;
            }
            processedCount++;
        }

        // Update last auto-retry time
        lastAutoRetryTime = block.timestamp;

        emit AutoRetryCompleted(processedCount, successCount);
    }

    /**
     * @dev Internal function to attempt a single transfer retry
     * @param receiver Address to retry transfer to
     * @return success Whether the retry was successful
     */
    function _attemptTransferRetry(address receiver) internal returns (bool success) {
        FailedTransfer storage failed = failedTransfers[receiver];
        uint256 amount = failed.amount;

        // Remove from failed transfers before attempting
        delete failedTransfers[receiver];
        _removeFailedReceiver(receiver);

        try this.transferToReceiver{ gas: 21000 }(receiver, amount) {
            emit TransferRetried(receiver, amount, true);
            emit KindnessReceived(receiver, amount);
            unchecked {
                unclaimedFunds -= amount;
            }
            return true;
        } catch {
            // Re-add to failed transfers with incremented retry count
            failedTransfers[receiver] = FailedTransfer({
                receiver: receiver,
                amount: amount,
                timestamp: block.timestamp,
                retryCount: failed.retryCount + 1
            });
            _addFailedReceiver(receiver);
            emit TransferRetried(receiver, amount, false);
            return false;
        }
    }

    /**
     * @dev Automatically retry failed transfers during distribution
     * @notice Called internally during distribution to piggyback retries
     */
    function _autoRetryDuringDistribution() internal {
        uint256 processedCount = 0;

        // Limit retries during distribution to avoid gas issues
        uint256 maxRetries = MAX_AUTO_RETRIES_PER_TX / 2; // Conservative limit

        for (uint256 i = 0; i < failedReceivers.length && processedCount < maxRetries; i++) {
            address receiver = failedReceivers[i];
            FailedTransfer storage failed = failedTransfers[receiver];

            if (failed.amount == 0 || failed.retryCount >= MAX_RETRIES) {
                continue;
            }

            // Use shorter cooldown during distribution for faster recovery
            uint256 cooldown = (RETRY_COOLDOWN * (1 << failed.retryCount)) / 2;
            if (block.timestamp < failed.timestamp + cooldown) {
                continue;
            }

            _attemptTransferRetry(receiver);
            processedCount++;
        }
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
        uint256 today = block.timestamp / 1 days;

        if (lastDistDay < today) {
            // If we haven't distributed today, next distribution is at next UTC midnight
            return (today + 1) * 1 days;
        }
        return (today + 2) * 1 days;
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

        try this.transferToReceiver{ gas: 21000 }(receiver, amount) {
            emit TransferRetried(receiver, amount, true);
            emit KindnessReceived(receiver, amount);
            unchecked {
                unclaimedFunds -= amount;
            }
        } catch {
            failedTransfers[receiver] = FailedTransfer({
                receiver: receiver, // Store the receiver address
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

        try this.transferToReceiver{ gas: 21000 }(receiver, amount) {
            emit EmergencyWithdrawalCompleted(receiver, amount);
            unchecked {
                unclaimedFunds -= amount;
            }
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

    /**
     * @dev Returns the current day number (days since epoch)
     * @return uint256 Current day number
     */
    function getCurrentDay() external view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /**
     * @dev Returns user's daily statistics
     * @param user Address of the user
     * @return contributionAmount Current daily contribution amount
     * @return receiverEntries Current daily receiver pool entries
     * @return receiverExits Current daily receiver pool exits
     * @return lastResetDay Day when user's data was last reset
     * @return canContribute Whether user can contribute more today
     * @return canEnterReceiverPool Whether user can enter receiver pool today
     * @return canLeaveReceiverPool Whether user can leave receiver pool today
     */
    function getUserDailyStats(
        address user
    )
        external
        view
        returns (
            uint256 contributionAmount,
            uint256 receiverEntries,
            uint256 receiverExits,
            uint256 lastResetDay,
            bool canContribute,
            bool canEnterReceiverPool,
            bool canLeaveReceiverPool
        )
    {
        uint256 today = block.timestamp / 1 days;

        // If user's data is from a previous day, they haven't contributed or entered today
        if (userLastDay[user] < today) {
            contributionAmount = 0;
            receiverEntries = 0;
            receiverExits = 0;
            lastResetDay = userLastDay[user];
            canContribute = true;
            canEnterReceiverPool = true;
            canLeaveReceiverPool = userRegistry.isInReceiverPool(user);
        } else {
            contributionAmount = dailyContributions[user];
            receiverEntries = dailyReceiverEntries[user];
            receiverExits = dailyReceiverExits[user];
            lastResetDay = userLastDay[user];
            canContribute = contributionAmount < MAX_DAILY_CONTRIBUTION;
            canEnterReceiverPool = receiverEntries < MAX_DAILY_RECEIVER_ENTRIES && contributionAmount == 0;
            canLeaveReceiverPool = receiverExits < MAX_DAILY_RECEIVER_EXITS && userRegistry.isInReceiverPool(user);
        }
    }

    /**
     * @dev Returns the remaining daily contribution limit for a user
     * @param user Address of the user
     * @return uint256 Remaining amount user can contribute today
     */
    function getRemainingDailyContribution(address user) external view returns (uint256) {
        uint256 today = block.timestamp / 1 days;

        if (userLastDay[user] < today) {
            return MAX_DAILY_CONTRIBUTION;
        }

        uint256 used = dailyContributions[user];
        return used >= MAX_DAILY_CONTRIBUTION ? 0 : MAX_DAILY_CONTRIBUTION - used;
    }

    /**
     * @dev Returns the withdrawable amount for a user
     * @param user Address of the user
     * @return uint256 Amount user can withdraw from their current day's contributions
     */
    function getWithdrawableAmount(address user) external view returns (uint256) {
        uint256 today = block.timestamp / 1 days;

        if (userLastDay[user] < today) {
            return 0; // No contributions today means nothing to withdraw
        }

        return dailyContributions[user];
    }

    /**
     * @dev Returns withdrawal statistics for a user
     * @param user Address of the user
     * @return withdrawalCount Number of withdrawals made today
     * @return canWithdraw Whether user can withdraw now
     * @return nextWithdrawalTime Timestamp when user can withdraw again
     * @return withdrawableAmount Amount user can withdraw
     */
    function getUserWithdrawalStats(
        address user
    )
        external
        view
        returns (uint256 withdrawalCount, bool canWithdraw, uint256 nextWithdrawalTime, uint256 withdrawableAmount)
    {
        uint256 today = block.timestamp / 1 days;

        if (userLastDay[user] < today) {
            withdrawalCount = 0;
            withdrawableAmount = 0;
        } else {
            withdrawalCount = dailyWithdrawals[user];
            withdrawableAmount = dailyContributions[user];
        }

        bool cooldownPassed = block.timestamp >= lastWithdrawalTime[user] + WITHDRAWAL_COOLDOWN;
        bool withinDailyLimit = withdrawalCount < MAX_DAILY_WITHDRAWALS;
        bool hasContribution = withdrawableAmount > 0;

        canWithdraw = cooldownPassed && withinDailyLimit && hasContribution;
        nextWithdrawalTime = lastWithdrawalTime[user] + WITHDRAWAL_COOLDOWN;
    }

    /**
     * @dev Returns withdrawal limits and constants
     * @return maxDailyWithdrawals Maximum withdrawals per day
     * @return withdrawalCooldownPeriod Cooldown period between withdrawals
     * @return minWithdrawalAmount Minimum withdrawal amount
     */
    function getWithdrawalLimits()
        external
        pure
        returns (uint256 maxDailyWithdrawals, uint256 withdrawalCooldownPeriod, uint256 minWithdrawalAmount)
    {
        return (MAX_DAILY_WITHDRAWALS, WITHDRAWAL_COOLDOWN, MIN_WITHDRAWAL_AMOUNT);
    }
}
