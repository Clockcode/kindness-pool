# Critical Security Issues (Most Urgent)
- [x] Add reentrancy protection to distributePool function
  - Implemented checks-effects-interactions pattern
- [x] Check if it's possible for users to do denial of service attacks and how to prevent them
  - Implemented rate limiting and transaction limiting
- [x] The distributePool function should be restricted to authorized addresses (like an admin or a time-based contract).
- [x] Add zero address checks in constructors

# Core Functionality (High Priority)
- [x] Implement amount limits (0.001 to 1 ETH) in giveKindness function
- [x] Add check to prevent users who have contributed from entering receiver pool
- [x] Move isInRecieverPool to UserRegistry
- [x] Implement mechanism to handle failed transfers in distributePool
  - Added robust tracking of failed receivers
  - Added retry mechanism with exponential backoff
  - Added emergency withdrawal handling for stuck funds
- [x] Add checks for contract balance before distribution
  - Implemented balance verification in distributePool
  - Added minimum pool balance constant
- [x] Add tracking for daily contributions to enforce giver/receiver rules
  - Implemented daily reset mechanism using day counter
  - Added daily contribution limits (5 ETH max per day)
  - Added daily receiver pool entry limits (1 entry per day)
  - Added lazy reset mechanism for gas efficiency
  - Added helper functions for daily stats and limits
- [ ] Set the rule that user can only enter and leave receiver pool once in a day
  - Add daily entry/exit tracking
  - Implement cooldown period
  - Add emergency exit mechanism

# Best Practices & Documentation (Medium Priority)
- [ ] Set Prettier solidity plugin to format the code
  - Add .prettierrc configuration
  - Add format scripts to package.json
- [x] Use custom errors instead of require statements
- [x] Add NatSpec documentation for all functions
- [x] Add input validation for constructor parameters
- [x] Add events for important state changes
- [x] Add events for failed transfers and redistributions

# Testing & Additional Features (Lower Priority)
- [ ] Add tests for denial of service attacks
  - Add gas limit tests
  - Add transaction limit tests
  - Add rate limit tests
- [x] Add tests for failed transfer handling
- [ ] Add documentation for the new functionality
  - Add README.md with setup instructions
  - Add API documentation
  - Add deployment guide
- [ ] Implement withdrawal functionality for users who want to withdraw their contribution
  - Add withdrawal function
  - Add withdrawal limits
  - Add withdrawal cooldown
