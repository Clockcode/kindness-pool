# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Hardhat-based Solidity project implementing a decentralized kindness pool system. Users can contribute ETH to or receive from a daily pool, with 24-hour cycles for contributions and distributions. The system includes comprehensive security features, rate limiting, and DoS protection.

## 🏗️ Core Architecture

The system consists of 4 main smart contracts:

### Contract Hierarchy
- **Pool.sol** - Main contract managing contributions, receivers, and distributions
- **UserRegistry.sol** - Manages user statistics and receiver pool status  
- **TimeBasedDistributor.sol** - Handles time-based distribution logic
- **Errors.sol** - Custom error definitions for gas-efficient error handling
- **TestReceiver.sol** - Testing utility for failed transfer scenarios

### Key Design Patterns
- Uses OpenZeppelin's AccessControl for role-based permissions
- Implements checks-effects-interactions pattern for reentrancy protection
- Immutable UserRegistry reference in Pool contract for gas optimization
- Custom errors instead of require strings for gas efficiency
- Failed transfer tracking with retry mechanisms

## ✨ Implemented Features

### Core Functionality
- ✅ **Daily Contribution System** - Users can contribute 0.001-1 ETH per transaction
- ✅ **Receiver Pool Management** - Users can enter/exit receiver pool (max 100 receivers)
- ✅ **Automatic Daily Reset** - 24-hour cycles with automatic state reset
- ✅ **Equal Distribution** - Pool funds distributed equally among all receivers

### Security & Rate Limiting
- ✅ **Action Cooldowns** - 1 hour general, 30 minutes receiver pool actions
- ✅ **Daily Limits** - 5 ETH max contribution, 10 transactions per user per day
- ✅ **DoS Protection** - Max 100 receivers, gas limit considerations
- ✅ **Reentrancy Protection** - Checks-effects-interactions pattern
- ✅ **Access Control** - Role-based permissions for admin functions

### Advanced Features
- ✅ **Batch Distribution** - Prevents gas limit issues with large receiver pools
- ✅ **Failed Transfer Handling** - Tracking and retry mechanism for failed transfers
- ✅ **Automatic Retry System** - Exponential backoff for failed transfer retries
- ✅ **Withdrawal Functionality** - Users can withdraw their contributions
- ✅ **User Statistics Tracking** - Comprehensive user interaction history
- ✅ **Emergency Functions** - Admin controls for system management

### Business Logic Constraints
- ✅ **Mutual Exclusivity** - Users cannot contribute AND be in receiver pool same day
- ✅ **Contribution Validation** - Minimum 0.001 ETH, maximum 1 ETH per transaction
- ✅ **Receiver Pool Limits** - Maximum 100 receivers to prevent gas issues
- ✅ **Time-based Controls** - 24-hour cycles with proper state management

## 🧪 Test Coverage

### Test Files & Coverage Areas
| Test File | Coverage Area |
|-----------|---------------|
| `Pool.test.ts` | Core functionality, contributions, receiver pool |
| `DoSAttacks.test.ts` | DoS attack resistance, gas limit tests |
| `DailyTracking.test.ts` | Daily reset, limits, state management |
| `UserRegistry.test.ts` | User statistics, role management |
| `Withdrawal.test.ts` | Withdrawal mechanisms, edge cases |
| `ReceiverPoolExit.test.ts` | Receiver pool functionality |
| `BatchDistribution.test.ts` | Batch processing, gas optimization |
| `AutoRetry.test.ts` | Failed transfer retry mechanisms |
| `TimeBasedDistributor.test.ts` | Time-based distribution logic |

### Test Categories
- **Unit Tests**: Individual function testing
- **Integration Tests**: Multi-contract interaction testing
- **Security Tests**: DoS attacks, reentrancy, access control
- **Edge Cases**: Gas limits, failed transfers, state boundaries
- **User Journey Tests**: Complete user interaction flows

## ⚠️ Known Issues

### Critical Issues
1. **Transaction Count Reset Bug**: `transactionCount` mapping not reset in daily reset, causing permanent lockout after 10 transactions
2. **Gas Limit Risk**: Large receiver pools may approach gas limits during distribution (partially mitigated by batch processing)

### Resolved Issues
- ✅ Failed transfer handling (resolved with retry system)
- ✅ Gas limit issues (resolved with batch distribution)
- ✅ DoS attack vulnerabilities (resolved with comprehensive protection)

## 🛠️ Development Configuration

### Essential Commands

#### Development
```bash
npm install                    # Install dependencies
npm run compile               # Compile smart contracts
npm test                      # Run all tests
npm test -- test/Pool.test.ts # Run specific test file
npm run clean                 # Clean build artifacts
```

#### Code Quality
```bash
npm run format                # Format Solidity files with Prettier
npm run format:check          # Check formatting without changes
```

#### Deployment & Verification
```bash
npx hardhat node              # Start local development node
npx hardhat run scripts/deploy.ts --network localhost    # Deploy locally
npx hardhat run scripts/deploy.ts --network base-sepolia # Deploy to Base Sepolia
npx hardhat verify --network base-sepolia CONTRACT_ADDRESS   # Verify on Basescan
```

### Hardhat Setup
- Solidity version: 0.8.20 with optimizer enabled (200 runs)
- Uses TypeChain for type-safe contract interactions
- Configured for Base Sepolia testnet and Base mainnet deployment
- Etherscan integration for contract verification (supports multi-chain)

### Environment Variables Required
```bash
# Network RPC URLs
SEPOLIA_RPC_URL=              # Ethereum Sepolia testnet
MAINNET_RPC_URL=              # Ethereum mainnet
BASE_SEPOLIA_RPC_URL=         # Base Sepolia testnet (default provided)
BASE_RPC_URL=                 # Base mainnet (default provided)

# Deployment
PRIVATE_KEY=                  # Deployer account private key (needs testnet ETH)

# Contract Verification
ETHERSCAN_API_KEY=            # Multi-chain verification (Etherscan + Basescan)
```

## 🎯 Business Logic Constraints

### Daily Cycle System
- 24-hour cycles with automatic reset mechanism
- Users can contribute (0.001-1 ETH per transaction) OR enter receiver pool, not both
- Distribution occurs at end of cycle to all receivers equally
- Failed transfers are tracked and can be retried

### Critical Limits (Hardcoded Constants)
```solidity
MIN_KINDNESS_AMOUNT: 0.001 ETH           // Minimum contribution
MAX_KINDNESS_AMOUNT: 1 ETH               // Maximum per transaction
MAX_DAILY_CONTRIBUTION: 5 ETH            // Maximum per user per day
MAX_RECEIVERS: 100                       // Total receiver pool limit
MAX_TRANSACTIONS_PER_DAY: 10             // Per user daily transaction limit
ACTION_COOLDOWN: 1 hour                  // General action cooldown
RECEIVER_POOL_COOLDOWN: 30 minutes       // Receiver pool action cooldown
```

## 🎯 AI Development Guidelines

### Architecture & Design Principles

#### Smart Contract Design
- **Single Responsibility**: Each contract should have one clear purpose
- **Immutable References**: Use immutable variables for contract addresses to save gas
- **Custom Errors**: Always use custom errors instead of require strings for gas efficiency
- **Events First**: Emit events for all state changes to enable frontend integration
- **Access Control**: Use OpenZeppelin's AccessControl for role-based permissions
- **Upgradability**: Consider proxy patterns only when absolutely necessary, prefer immutable designs

#### Security First Approach
- **Checks-Effects-Interactions**: Always follow this pattern to prevent reentrancy
- **Input Validation**: Validate all inputs at function entry points
- **Rate Limiting**: Implement cooldowns and daily limits for user actions
- **DoS Protection**: Consider gas limits and implement batching for large operations
- **Emergency Controls**: Include pause/emergency functions for critical scenarios
- **Failed Transfer Handling**: Always handle failed ETH transfers gracefully

#### Gas Optimization Strategies
- **Batch Operations**: Group multiple operations to reduce transaction costs
- **Storage Optimization**: Pack structs and use appropriate data types
- **View Functions**: Use view/pure functions for read operations
- **Event Indexing**: Index important event parameters for efficient querying
- **Loop Limits**: Implement maximum iteration limits to prevent gas limit issues

### Testing Excellence Standards

#### Test Architecture
- **Comprehensive Coverage**: Test all functions, edge cases, and error conditions
- **Isolation**: Each test should be independent and use fresh contract deployments
- **Realistic Scenarios**: Test with realistic user interaction patterns
- **Gas Tracking**: Monitor gas usage for optimization opportunities
- **Security Testing**: Include specific tests for DoS attacks and security vulnerabilities

#### Test Organization
- **Descriptive Names**: Use clear, descriptive test names that explain the scenario
- **Setup Patterns**: Use consistent beforeEach patterns for contract deployment
- **Helper Functions**: Create reusable helper functions for common test operations
- **Error Testing**: Test both success and failure paths for all functions
- **State Verification**: Always verify contract state after operations

#### Test Coverage Areas
- **Unit Tests**: Individual function behavior
- **Integration Tests**: Multi-contract interactions
- **User Journey Tests**: Complete end-to-end user flows
- **Security Tests**: Attack vectors and edge cases
- **Performance Tests**: Gas usage and efficiency

### Development Workflow Best Practices

#### Before Writing Code
1. **Understand Requirements**: Clearly define the feature requirements and constraints
2. **Review Existing Code**: Study existing patterns and conventions in the codebase
3. **Plan Architecture**: Design the solution considering gas costs and security
4. **Identify Tests**: Plan test cases before implementation
5. **Consider Integration**: Think about how the feature integrates with existing systems

#### During Development
1. **Incremental Development**: Build features incrementally with frequent testing
2. **Security Reviews**: Consider security implications for every code change
3. **Gas Optimization**: Profile gas usage and optimize where necessary
4. **Documentation**: Add inline comments for complex logic
5. **Event Emission**: Emit appropriate events for state changes

#### Code Quality Standards
- **Consistent Naming**: Use clear, consistent naming conventions
- **Function Size**: Keep functions focused and reasonably sized
- **Error Handling**: Provide clear error messages and proper error handling
- **Code Reuse**: Identify and extract common patterns into reusable functions
- **Type Safety**: Leverage TypeChain for type-safe contract interactions

### Commit and Release Guidelines

#### Commit Standards
- **Atomic Commits**: Each commit should represent a single logical change
- **Clear Messages**: Write clear, descriptive commit messages explaining the change
- **Feature Flags**: Use feature flags for incomplete features
- **Breaking Changes**: Clearly document any breaking changes
- **Security Fixes**: Mark security-related commits clearly

#### Pre-Commit Checklist
1. **Compile Check**: Ensure all contracts compile without errors
2. **Test Suite**: Run full test suite and ensure all tests pass
3. **Gas Analysis**: Review gas usage for any regressions
4. **Security Review**: Consider security implications of changes
5. **Documentation**: Update documentation for any API changes
6. **Formatting**: Ensure code is properly formatted

#### Release Preparation
1. **Integration Testing**: Test on testnet with realistic scenarios
2. **Security Audit**: Consider external security review for major changes
3. **Documentation Update**: Ensure all documentation is current
4. **Deployment Scripts**: Verify deployment scripts work correctly
5. **Rollback Plan**: Have a clear rollback strategy for deployments

### Problem-Solving Approach

#### When Adding New Features
1. **Analyze Impact**: Consider impact on existing functionality
2. **Security First**: Evaluate security implications before implementation
3. **Gas Efficiency**: Design with gas costs in mind
4. **Test Coverage**: Plan comprehensive test coverage
5. **Documentation**: Document new functionality thoroughly

#### When Fixing Bugs
1. **Root Cause Analysis**: Understand the underlying cause
2. **Regression Testing**: Ensure the fix doesn't break existing functionality
3. **Test the Fix**: Create specific tests for the bug scenario
4. **Consider Edge Cases**: Think about related edge cases
5. **Document the Fix**: Explain the fix in commit messages and comments

#### When Optimizing
1. **Measure First**: Use gas profiling to identify bottlenecks
2. **Benchmark**: Compare before and after performance
3. **Maintain Functionality**: Ensure optimizations don't change behavior
4. **Test Thoroughly**: Verify optimizations don't introduce bugs
5. **Document Changes**: Explain optimization techniques used

---

**Important**: Always prioritize security over convenience, gas efficiency over complexity, and comprehensive testing over rapid development. Every code change should be evaluated for its impact on the system's security, usability, and maintainability.