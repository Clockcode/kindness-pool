# Kindness Pool System

This project implements a decentralized kindness pool system using Hardhat and Solidity smart contracts. Users can contribute to or receive from a daily pool of Ether, promoting a culture of giving and receiving kindness.

## Business Logic

For detailed business logic, please refer to [BUSINESS_LOGIC.md](./docs/BUSINESS_LOGIC.md).

Key features:
- 24-hour cycles for contributions and distributions
- User can contribute between 0.001 and 1 ETH
- Users can enter a receiver pool to potentially receive funds
- Automatic distribution at the end of each cycle
- Daily contribution and receiver limits
- Rate limiting and DoS protection
- Failed transfer handling and retry mechanisms
- Comprehensive security features

## Prerequisites

- Node.js (v14.0.0 or later)
- npm (v6.0.0 or later)
- Git

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/your-repo/kindness-pool.git
   cd kindness-pool
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

## Usage

### Compile Contracts

```bash
npm run compile
```

### Run Tests

```bash
npm test
```

### Run Specific Test Files

```bash
npm test -- test/Pool.test.ts
npm test -- test/DoSAttacks.test.ts
npm test -- test/DailyTracking.test.ts
```

### Format Code

```bash
npm run format
npm run format:check
```

### Clean Build Artifacts

```bash
npm run clean
```

## Smart Contract Architecture

### Core Contracts

1. **Pool.sol** - Main contract managing contributions, receivers, and distributions
2. **UserRegistry.sol** - Manages user statistics and receiver pool status
3. **TimeBasedDistributor.sol** - Handles time-based distribution logic
4. **Errors.sol** - Custom error definitions for gas-efficient error handling

### Key Features

#### Security Features
- **Reentrancy Protection**: Uses checks-effects-interactions pattern
- **Rate Limiting**: Action cooldowns and transaction limits
- **DoS Protection**: Gas limit protections and receiver limits
- **Failed Transfer Handling**: Robust retry mechanisms with exponential backoff
- **Access Control**: Role-based permissions for admin functions

#### Daily Limits
- **Contribution Limits**: 5 ETH maximum per user per day
- **Receiver Pool Limits**: 1 entry/exit per user per day
- **Transaction Limits**: 10 transactions per user per day (Note: Currently has a reset bug)
- **Action Cooldowns**: 1 hour between general actions, 30 minutes between receiver pool actions

#### Error Handling
- Uses custom errors for gas efficiency
- Comprehensive error messages for debugging
- Failed transfer tracking and retry mechanisms

## API Documentation

### Pool Contract Functions

#### Public Functions

##### `giveKindness(uint256 amount)`
- **Description**: Contribute ETH to the daily pool
- **Parameters**: 
  - `amount`: Amount to contribute (0.001 to 1 ETH)
- **Requirements**: 
  - Amount must be between MIN_KINDNESS_AMOUNT and MAX_KINDNESS_AMOUNT
  - User must not exceed daily contribution limit (5 ETH)
  - Respects transaction limits and cooldowns

##### `enterReceiverPool()`
- **Description**: Enter the receiver pool to potentially receive funds
- **Requirements**:
  - User must not have contributed today
  - User must not already be in receiver pool
  - Respects daily entry limits and cooldowns

##### `leaveReceiverPool()`
- **Description**: Exit the receiver pool
- **Requirements**:
  - User must be in receiver pool
  - Respects daily exit limits and cooldowns

##### `distributePool()`
- **Description**: Distribute the daily pool to receivers (admin only)
- **Requirements**:
  - Must be within distribution window
  - Must not have distributed today
  - Pool must have minimum balance

#### View Functions

##### `isWithinDistributionWindow()`
- **Returns**: `bool` - Whether current time is within distribution window

##### `hasDistributedToday()`
- **Returns**: `bool` - Whether distribution has occurred today

##### `getReceiverCount()`
- **Returns**: `uint256` - Current number of receivers

##### `getUnclaimedFunds()`
- **Returns**: `uint256` - Amount of unclaimed funds from failed transfers

#### Constants

- `MIN_KINDNESS_AMOUNT`: 0.001 ETH
- `MAX_KINDNESS_AMOUNT`: 1 ETH
- `MAX_DAILY_CONTRIBUTION`: 5 ETH
- `MAX_DAILY_RECEIVER_ENTRIES`: 1
- `MAX_DAILY_RECEIVER_EXITS`: 1
- `MAX_TRANSACTIONS_PER_DAY`: 10
- `ACTION_COOLDOWN`: 1 hour
- `RECEIVER_POOL_COOLDOWN`: 30 minutes
- `MAX_RECEIVERS`: 100

### Events

#### Pool Events
- `KindnessGiven(address indexed giver, uint256 amount)`
- `KindnessReceived(address indexed receiver, uint256 amount)`
- `PoolDistributed(uint256 totalAmount, uint256 receiverCount)`
- `EnteredReceiverPool(address indexed receiver)`
- `LeftReceiverPool(address indexed receiver)`
- `TransferFailed(address indexed receiver, uint256 amount)`
- `TransferRetried(address indexed receiver, uint256 amount, bool success)`

#### UserRegistry Events
- `UserStatsUpdated(address indexed user, bool isGiving, uint256 amount, uint256 totalGiven, uint256 totalReceived, int256 netAmount)`
- `UserNameUpdated(address indexed user, string name)`
- `ReceiverPoolStatusUpdated(address indexed user, bool isInReceiverPool)`

## Deployment Guide

### Local Development

1. Start a local Hardhat node:
   ```bash
   npx hardhat node
   ```

2. Deploy contracts to local network:
   ```bash
   npx hardhat run scripts/deploy.ts --network localhost
   ```

### Testnet Deployment

1. Configure your environment variables in `.env`:
   ```
   PRIVATE_KEY=your_private_key
   INFURA_API_KEY=your_infura_key
   ETHERSCAN_API_KEY=your_etherscan_key
   ```

2. Deploy to testnet (e.g., Sepolia):
   ```bash
   npx hardhat run scripts/deploy.ts --network sepolia
   ```

3. Verify contracts:
   ```bash
   npx hardhat verify --network sepolia DEPLOYED_ADDRESS
   ```

### Mainnet Deployment

⚠️ **Warning**: Ensure thorough testing before mainnet deployment

1. Use the same process as testnet but with mainnet network configuration
2. Consider using a multisig wallet for admin functions
3. Implement timelocks for critical parameter changes

## Security Considerations

### Known Issues

1. **Transaction Count Reset Bug**: The `transactionCount` mapping is not reset in the daily reset mechanism, causing permanent lockout after 10 transactions
2. **Gas Limit Considerations**: Large receiver pools may approach gas limits during distribution
3. **Failed Transfer Handling**: Failed transfers are tracked but require manual intervention for resolution

### Best Practices

1. **Admin Role Management**: Use multisig wallets for admin roles
2. **Emergency Procedures**: Implement emergency pause mechanisms
3. **Monitoring**: Monitor failed transfers and retry attempts
4. **Gas Price Management**: Consider gas price fluctuations for distribution operations

## Testing

The project includes comprehensive test suites:

- **Pool.test.ts**: Core functionality tests
- **DoSAttacks.test.ts**: Denial of service attack resistance tests
- **DailyTracking.test.ts**: Daily reset and limit tests
- **UserRegistry.test.ts**: User statistics and registry tests
- **ReceiverPoolExit.test.ts**: Receiver pool exit functionality tests

### Running Tests

```bash
# Run all tests
npm test

# Run with gas reporting
npx hardhat test --gas-report

# Run specific test file
npm test -- test/DoSAttacks.test.ts

# Run tests with coverage
npx hardhat coverage
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Implement your changes with tests
4. Ensure all tests pass
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For questions and support, please open an issue on the GitHub repository.