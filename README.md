# Kindness Pool System

This project implements a decentralized kindness pool system using Hardhat and Solidity smart contracts. Users can contribute to or receive from a daily pool of Ether, promoting a culture of giving and receiving kindness.

## Business Logic

For detailed business logic, please refer to [BUSINESS_LOGIC.md](./docs/BUSINESS_LOGIC.md).

Key features:
- 24-hour cycles for contributions and distributions
- User can contribute between 0.001 and 1 ETH
- Users can enter a receiver pool to potentially receive funds
- Automatic distribution at the end of each cycle

## Prerequisites

- Node.js (v14.0.0 or later)
- npm (v6.0.0 or later)

## Installation

1. Clone the repository:
   ```
   git clone https://github.com/your-repo/kindness-pool.git
   cd kindness-pool
   ```

2. Install dependencies:
   ```
   npm install
   ```

## Usage

### Compile Contracts
