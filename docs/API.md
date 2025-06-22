# Kindness Pool API Documentation

This document provides detailed API documentation for the Kindness Pool smart contracts.

## Overview

The Kindness Pool system consists of four main contracts:

1. **Pool.sol** - Core contract managing the daily pool
2. **UserRegistry.sol** - User statistics and receiver pool management
3. **TimeBasedDistributor.sol** - Time-based distribution logic
4. **Errors.sol** - Custom error definitions

## Pool Contract

### Constructor

```solidity
constructor(address _system)
```

**Parameters:**
- `_system`: Address of the admin/system account

**Requirements:**
- `_system` must not be zero address

### State Variables

```solidity
uint256 public dailyPool;                    // Current day's pool amount
uint256 public lastDistributionTime;         // Timestamp of last distribution
address[] public receivers;                  // List of current receivers
UserRegistry public immutable userRegistry; // User registry contract
mapping(address => uint256) public lastActionTime;        // User's last action timestamp
mapping(address => uint256) public transactionCount;     // Daily transaction count per user
mapping(address => uint256) public dailyContributions;   // Daily contributions per user
uint256 public unclaimedFunds;              // Track unclaimed funds
bool public distributionWindowOpen;         // Distribution window status (test only)
uint256 public currentDay;                  // Current day counter
mapping(address => uint256) public userLastDay;          // User's last reset day
mapping(address => uint256) public dailyReceiverEntries; // Daily receiver entries per user
mapping(address => uint256) public dailyReceiverExits;   // Daily receiver exits per user
mapping(address => uint256) public lastReceiverPoolAction; // Last receiver pool action timestamp
```

### Modifiers

#### `rateLimited()`
Enforces 1-hour cooldown between actions.
- **Error**: `TooManyActions()`
- **Cooldown**: `ACTION_COOLDOWN` (1 hour)

#### `transactionLimited()`
Enforces daily transaction limit (10 per day).
- **Error**: `TooManyTransactions()`
- **Limit**: `MAX_TRANSACTIONS_PER_DAY` (10)

#### `receiverPoolCooldown()`
Enforces cooldown between receiver pool actions.
- **Error**: `TooManyActions()`
- **Cooldown**: `RECEIVER_POOL_COOLDOWN` (30 minutes)

### Public Functions

#### `giveKindness(uint256 amount)`

Allows users to contribute ETH to the daily pool.

**Parameters:**
- `amount`: Amount to contribute in wei

**Modifiers:**
- `transactionLimited`

**Requirements:**
- `amount >= MIN_KINDNESS_AMOUNT` (0.001 ETH)
- `amount <= MAX_KINDNESS_AMOUNT` (1 ETH)
- `msg.value == amount`
- Daily contribution limit not exceeded (5 ETH)

**Effects:**
- Increases `dailyPool` by `amount`
- Updates user's daily contributions
- Updates user statistics in UserRegistry
- Emits `KindnessGiven` event

**Events:**
```solidity
emit KindnessGiven(msg.sender, amount);
```

#### `enterReceiverPool()`

Allows users to enter the receiver pool to potentially receive funds.

**Modifiers:**
- `receiverPoolCooldown`
- `transactionLimited`

**Requirements:**
- User not already in receiver pool
- User has not contributed today
- Daily receiver entry limit not exceeded (1 per day)
- Receiver pool not at maximum capacity

**Effects:**
- Adds user to `receivers` array
- Updates receiver pool status in UserRegistry
- Increments daily receiver entries for user
- Emits `EnteredReceiverPool` event

**Events:**
```solidity
emit EnteredReceiverPool(msg.sender);
```

#### `leaveReceiverPool()`

Allows users to exit the receiver pool.

**Modifiers:**
- `receiverPoolCooldown`
- `transactionLimited`

**Requirements:**
- User must be in receiver pool
- Daily receiver exit limit not exceeded (1 per day)

**Effects:**
- Removes user from `receivers` array
- Updates receiver pool status in UserRegistry
- Increments daily receiver exits for user
- Emits `LeftReceiverPool` event

**Events:**
```solidity
emit LeftReceiverPool(msg.sender);
```

#### `distributePool()`

Distributes the daily pool among receivers (admin only).

**Access Control:**
- Requires `DISTRIBUTOR_ROLE`

**Requirements:**
- Within distribution window
- Not already distributed today
- Pool has minimum balance (`MIN_POOL_BALANCE`)
- Has receivers to distribute to

**Effects:**
- Calculates share per receiver
- Attempts to transfer funds to each receiver
- Tracks failed transfers for retry
- Resets daily data for receivers
- Updates distribution timestamp
- Emits `PoolDistributed` event

**Events:**
```solidity
emit PoolDistributed(totalAmount, receiverCount);
emit KindnessReceived(receiver, sharePerReceiver); // For each successful transfer
emit TransferFailed(receiver, sharePerReceiver);   // For each failed transfer
```

### View Functions

#### `isWithinDistributionWindow()`

**Returns:** `bool` - Whether current time is within distribution window

In test environment (chainid 31337), uses `distributionWindowOpen` state variable.
In production, checks if current time modulo 1 day is less than `DISTRIBUTION_WINDOW`.

#### `hasDistributedToday()`

**Returns:** `bool` - Whether distribution has already occurred today

Compares the day of `lastDistributionTime` with current day.

#### `getReceiverCount()`

**Returns:** `uint256` - Current number of receivers in the pool

#### `getUnclaimedFunds()`

**Returns:** `uint256` - Amount of unclaimed funds from failed transfers

#### `getNextDistributionTime()`

**Returns:** `uint256` - Timestamp of the next distribution window

Calculates based on current time and last distribution time.

### Admin Functions

#### `retryFailedTransfer(address receiver)`

Retry a previously failed transfer with exponential backoff.

**Access Control:**
- Requires `DISTRIBUTOR_ROLE`

**Parameters:**
- `receiver`: Address of the failed transfer recipient

**Requirements:**
- Must have a recorded failed transfer
- Retry count must be below `MAX_RETRIES` (3)
- Enough time must have passed since last retry (exponential cooldown)

#### `setDistributionWindow(bool _isOpen)`

Control distribution window for testing (test environment only).

**Access Control:**
- Requires `DEFAULT_ADMIN_ROLE`
- Only available in test environment (chainid 31337)

### Constants

```solidity
uint256 public constant DISTRIBUTION_INTERVAL = 1 days;
uint256 public constant DISTRIBUTION_WINDOW = 5 minutes;
uint256 public constant MAX_RECEIVERS = 100;
uint256 public constant MIN_KINDNESS_AMOUNT = 0.001 ether;
uint256 public constant MAX_KINDNESS_AMOUNT = 1 ether;
uint256 public constant MIN_POOL_BALANCE = 0.01 ether;
uint256 public constant MAX_RETRIES = 3;
uint256 public constant RETRY_COOLDOWN = 1 hours;
uint256 public constant MAX_DAILY_CONTRIBUTION = 5 ether;
uint256 public constant MAX_DAILY_RECEIVER_ENTRIES = 1;
uint256 public constant MAX_DAILY_RECEIVER_EXITS = 1;
uint256 public constant RECEIVER_POOL_COOLDOWN = 30 minutes;
uint256 public constant ACTION_COOLDOWN = 1 hours;
uint256 public constant MAX_TRANSACTIONS_PER_DAY = 10;
```

## UserRegistry Contract

### State Variables

```solidity
struct UserStats {
    uint256 totalGiven;      // Total amount given by user
    uint256 totalReceived;   // Total amount received by user
    uint256 timesReceived;   // Number of times user received kindness
    uint256 lastActionTime;  // Timestamp of last action
    string name;             // User's display name
    bool isInReceiverPool;   // Whether user is currently in receiver pool
}

address public system;                              // Address of the system contract
mapping(address => UserStats) public userStats;    // User statistics
```

### Public Functions

#### `updateUserStats(address user, bool isGiving, uint256 amount)`

Updates user statistics when they give or receive kindness.

**Access Control:**
- `onlySystem` modifier

**Parameters:**
- `user`: User's address
- `isGiving`: True if giving, false if receiving
- `amount`: Amount given or received

#### `updateReceiverPoolStatus(address user, bool isInPool)`

Updates user's receiver pool status.

**Access Control:**
- `onlySystem` modifier

**Parameters:**
- `user`: User's address
- `isInPool`: True if entering pool, false if leaving

#### `setUserName(string memory name)`

Allows users to set their display name.

**Requirements:**
- Name must not be empty
- Name length must be <= 50 characters

#### `updateSystem(address newSystem)`

Updates the system contract address (admin only).

**Access Control:**
- `onlyOwner`

### View Functions

#### `isInReceiverPool(address user)`

**Returns:** `bool` - Whether user is currently in receiver pool

#### `getUserStats(address user)`

**Returns:** `UserStats` - Complete user statistics struct

#### `getUserNetAmount(address user)`

**Returns:** `int256` - Net amount (received - given) for user

## Error Definitions

### Custom Errors (Errors.sol)

```solidity
error ZeroAddress();                         // Address is zero
error InsufficientGas();                     // Not enough gas provided
error NotInDistributionWindow();             // Outside distribution window
error AlreadyDistributedToday();             // Distribution already done today
error EmptyPool();                           // Pool is empty
error NoReceivers();                         // No receivers in pool
error TooManyReceivers();                    // Exceeded max receivers
error AmountTooLow();                        // Below minimum amount
error AmountTooHigh();                       // Above maximum amount
error ValueMismatch();                       // msg.value != amount
error AlreadyInReceiverPool();               // User already in receiver pool
error ContributedToday();                    // User contributed today
error NoFailedTransfer();                    // No failed transfer record
error NotDistributor();                      // Missing distributor role
error TooManyActions();                      // Action cooldown active
error TooManyTransactions();                 // Daily transaction limit exceeded
error DistributionFailed();                  // Distribution process failed
error NotSystem();                           // Not authorized system contract
error EmptyName();                           // Name is empty
error NameTooLong();                         // Name exceeds length limit
error TransferFailedErr();                   // Transfer failed
error TooEarlyToRetry();                     // Retry cooldown active
error MaxRetriesExceeded();                  // Maximum retries reached
error EmergencyWithdrawalFailed();           // Emergency withdrawal failed
error NotAdmin();                            // Missing admin role
error InsufficientContractBalance();         // Contract balance too low
error PoolBalanceBelowMinimum();             // Pool below minimum for distribution
error DailyContributionLimitExceeded();      // Daily contribution limit exceeded
error DailyReceiverEntryLimitExceeded();     // Daily receiver entry limit exceeded
error DailyReceiverExitLimitExceeded();      // Daily receiver exit limit exceeded
error NotInReceiverPool();                   // User not in receiver pool
error EmergencyExitNotAllowed();             // Emergency exit not permitted
```

## Gas Optimization Notes

1. **Unchecked Math**: Used for safe operations to save gas
2. **Custom Errors**: More gas-efficient than string revert messages
3. **Immutable Variables**: `userRegistry` marked immutable for gas savings
4. **Efficient Array Operations**: Optimized receiver array management
5. **Lazy Reset**: Daily data reset only when needed

## Security Features

1. **Reentrancy Protection**: Checks-effects-interactions pattern
2. **Access Control**: Role-based permissions using OpenZeppelin
3. **Input Validation**: Comprehensive parameter checking
4. **Rate Limiting**: Multiple cooldown mechanisms
5. **Failed Transfer Handling**: Robust retry mechanisms
6. **Gas Limit Protection**: Receiver count limits prevent DoS

## Integration Examples

### Frontend Integration

```javascript
// Connect to contract
const pool = new ethers.Contract(poolAddress, poolABI, signer);

// Give kindness
const amount = ethers.parseEther("0.5");
await pool.giveKindness(amount, { value: amount });

// Enter receiver pool
await pool.enterReceiverPool();

// Check if user can distribute
const canDistribute = await pool.hasRole(await pool.DISTRIBUTOR_ROLE(), userAddress);
const inWindow = await pool.isWithinDistributionWindow();
const notDistributed = !(await pool.hasDistributedToday());

if (canDistribute && inWindow && notDistributed) {
    await pool.distributePool();
}
```

### Event Listening

```javascript
// Listen for kindness events
pool.on("KindnessGiven", (giver, amount) => {
    console.log(`${giver} gave ${ethers.formatEther(amount)} ETH`);
});

pool.on("PoolDistributed", (totalAmount, receiverCount) => {
    console.log(`Distributed ${ethers.formatEther(totalAmount)} ETH to ${receiverCount} receivers`);
});
```

This documentation covers the complete API surface of the Kindness Pool contracts. For implementation examples and usage patterns, refer to the test files in the repository.