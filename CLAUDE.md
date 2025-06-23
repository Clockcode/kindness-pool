# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Hardhat-based Solidity project implementing a decentralized kindness pool system. Users can contribute ETH to or receive from a daily pool, with 24-hour cycles for contributions and distributions. The system includes comprehensive security features, rate limiting, and DoS protection.

## Core Architecture

The system consists of 4 main smart contracts:

### Contract Hierarchy
- **Pool.sol** - Main contract managing contributions, receivers, and distributions
- **UserRegistry.sol** - Manages user statistics and receiver pool status  
- **TimeBasedDistributor.sol** - Handles time-based distribution logic
- **Errors.sol** - Custom error definitions for gas-efficient error handling

### Key Design Patterns
- Uses OpenZeppelin's AccessControl for role-based permissions
- Implements checks-effects-interactions pattern for reentrancy protection
- Immutable UserRegistry reference in Pool contract for gas optimization
- Custom errors instead of require strings for gas efficiency
- Failed transfer tracking with retry mechanisms

### Security Features
- Rate limiting with action cooldowns (1 hour general, 30 minutes receiver pool)
- Daily limits: 5 ETH max contribution, 1 receiver pool entry/exit per day
- Transaction limits: 10 per user per day (Note: has reset bug - transactionCount not reset)
- DoS protection with max 100 receivers and gas limit considerations
- Failed transfer handling with exponential backoff retry

## Essential Commands

### Development
```bash
npm install                    # Install dependencies
npm run compile               # Compile smart contracts
npm test                      # Run all tests
npm test -- test/Pool.test.ts # Run specific test file
npm run clean                 # Clean build artifacts
```

### Code Formatting
```bash
npm run format                # Format Solidity files with Prettier
npm run format:check          # Check formatting without changes
```

### Testing Patterns
- Use `beforeEach` for contract deployment and setup
- Tests use ethers.getSigners() for multiple test accounts
- TypeChain generates type-safe contract interfaces in `typechain-types/`
- Comprehensive test suites cover security, daily limits, and edge cases

### Deployment
```bash
npx hardhat node              # Start local development node
npx hardhat run scripts/deploy.ts --network localhost    # Deploy locally
npx hardhat run scripts/deploy.ts --network sepolia      # Deploy to testnet
npx hardhat verify --network sepolia CONTRACT_ADDRESS   # Verify on Etherscan
```

## Development Configuration

### Hardhat Setup
- Solidity version: 0.8.20 with optimizer enabled (200 runs)
- Uses TypeChain for type-safe contract interactions
- Configured for Sepolia testnet and mainnet deployment
- Etherscan integration for contract verification

### Environment Variables Required
```
PRIVATE_KEY=         # Deployment account private key
SEPOLIA_RPC_URL=     # Sepolia testnet RPC URL  
MAINNET_RPC_URL=     # Mainnet RPC URL
ETHERSCAN_API_KEY=   # For contract verification
```

## Business Logic Constraints

### Daily Cycle System
- 24-hour cycles with automatic reset mechanism
- Users can contribute (0.001-1 ETH per transaction) OR enter receiver pool, not both
- Distribution occurs at end of cycle to all receivers equally
- Failed transfers are tracked and can be retried

### Critical Limits (Hardcoded Constants)
- MIN_KINDNESS_AMOUNT: 0.001 ETH
- MAX_KINDNESS_AMOUNT: 1 ETH  
- MAX_DAILY_CONTRIBUTION: 5 ETH per user
- MAX_RECEIVERS: 100 total
- MAX_TRANSACTIONS_PER_DAY: 10 per user
- ACTION_COOLDOWN: 1 hour
- RECEIVER_POOL_COOLDOWN: 30 minutes

## Known Issues

1. **Transaction Count Reset Bug**: `transactionCount` mapping not reset in daily reset, causing permanent lockout after 10 transactions
2. **Gas Limit Risk**: Large receiver pools may approach gas limits during distribution
3. **Manual Failed Transfer Resolution**: Failed transfers require manual intervention

## Test Files Organization

- `Pool.test.ts` - Core functionality
- `DoSAttacks.test.ts` - DoS attack resistance  
- `DailyTracking.test.ts` - Daily reset and limits
- `UserRegistry.test.ts` - User statistics
- `ReceiverPoolExit.test.ts` - Receiver pool functionality
- `Withdrawal.test.ts` - Withdrawal mechanisms

When modifying contracts, always run the full test suite and ensure gas limit considerations for distribution operations.