# Kindness Pool Deployment Guide

This guide provides comprehensive instructions for deploying the Kindness Pool smart contracts to various networks.

## Prerequisites

### Software Requirements

- Node.js (v14.0.0 or later)
- npm (v6.0.0 or later)
- Git
- A Web3 wallet (MetaMask, WalletConnect, etc.)

### Network Requirements

- Access to Ethereum node (Infura, Alchemy, or local node)
- ETH for gas fees on target network
- Etherscan API key for contract verification (optional but recommended)

## Environment Setup

### 1. Clone and Install

```bash
git clone https://github.com/your-repo/kindness-pool.git
cd kindness-pool
npm install
```

### 2. Environment Configuration

Create a `.env` file in the root directory:

```env
# Private key of the deployer account (without 0x prefix)
PRIVATE_KEY=your_private_key_here

# Infura project ID or Alchemy API key
INFURA_API_KEY=your_infura_project_id
# OR
ALCHEMY_API_KEY=your_alchemy_api_key

# Etherscan API key for contract verification
ETHERSCAN_API_KEY=your_etherscan_api_key

# Optional: Custom RPC URLs
MAINNET_RPC_URL=https://mainnet.infura.io/v3/your_project_id
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your_project_id
```

### 3. Update Hardhat Configuration

Ensure your `hardhat.config.ts` includes the networks you want to deploy to:

```typescript
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: "0.8.20",
  networks: {
    hardhat: {
      // Local development network
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || `https://sepolia.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: 20000000000, // 20 gwei
    },
    mainnet: {
      url: process.env.MAINNET_RPC_URL || `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: 30000000000, // 30 gwei
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;
```

## Pre-Deployment Checklist

### 1. Security Review

- [ ] Audit all smart contracts
- [ ] Review access control configurations
- [ ] Verify all constants and limits are appropriate
- [ ] Test emergency procedures
- [ ] Review admin key management strategy

### 2. Testing

- [ ] Run all unit tests: `npm test`
- [ ] Run gas optimization tests
- [ ] Test on local network with realistic scenarios
- [ ] Deploy and test on testnet first

### 3. Gas Estimation

```bash
# Get gas estimates for deployment
npx hardhat test --gas-reporter

# Estimate deployment costs
npx hardhat run scripts/estimate-gas.ts --network sepolia
```

## Deployment Process

### Local Development Deployment

#### 1. Start Local Node

```bash
npx hardhat node
```

This starts a local Ethereum node with 20 test accounts pre-funded with ETH.

#### 2. Deploy to Local Network

```bash
npx hardhat run scripts/deploy.ts --network localhost
```

#### 3. Interact with Local Contracts

```bash
npx hardhat console --network localhost
```

### Testnet Deployment (Sepolia)

#### 1. Fund Deployer Account

Ensure your deployer account has sufficient ETH for gas fees. You can get testnet ETH from:
- [Sepolia Faucet](https://sepoliafaucet.com/)
- [Alchemy Sepolia Faucet](https://sepoliafaucet.com/)

#### 2. Deploy Contracts

```bash
npx hardhat run scripts/deploy.ts --network sepolia
```

#### 3. Verify Contracts

After deployment, verify contracts on Etherscan:

```bash
# Verify Pool contract
npx hardhat verify --network sepolia <POOL_ADDRESS> <ADMIN_ADDRESS>

# Verify UserRegistry contract (if deployed separately)
npx hardhat verify --network sepolia <USER_REGISTRY_ADDRESS> <SYSTEM_ADDRESS>
```

#### 4. Test Deployed Contracts

```bash
# Run integration tests against deployed contracts
DEPLOYED_POOL_ADDRESS=<address> npm run test:integration
```

### Mainnet Deployment

⚠️ **CRITICAL WARNING**: Mainnet deployment involves real money. Ensure thorough testing and security reviews.

#### 1. Final Security Checklist

- [ ] Complete professional audit
- [ ] Multi-signature wallet setup for admin functions
- [ ] Emergency pause mechanisms tested
- [ ] Gas price strategy defined
- [ ] Rollback plan prepared

#### 2. Prepare Mainnet Environment

```bash
# Check deployer balance
npx hardhat run scripts/check-balance.ts --network mainnet

# Estimate deployment cost
npx hardhat run scripts/estimate-deployment-cost.ts --network mainnet
```

#### 3. Deploy with Conservative Gas Settings

```bash
# Deploy with manual gas settings
MAINNET_GAS_PRICE=25000000000 npx hardhat run scripts/deploy.ts --network mainnet
```

#### 4. Post-Deployment Steps

1. **Verify Contracts**:
   ```bash
   npx hardhat verify --network mainnet <POOL_ADDRESS> <ADMIN_ADDRESS>
   ```

2. **Transfer Admin Rights** (if using multisig):
   ```bash
   npx hardhat run scripts/transfer-admin.ts --network mainnet
   ```

3. **Set Initial Parameters**:
   ```bash
   npx hardhat run scripts/configure-pool.ts --network mainnet
   ```

## Deployment Script Details

### Main Deployment Script (`scripts/deploy.ts`)

```typescript
import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  // Deploy Pool contract
  const Pool = await ethers.getContractFactory("Pool");
  const pool = await Pool.deploy(deployer.address);
  await pool.waitForDeployment();

  const poolAddress = await pool.getAddress();
  console.log("Pool deployed to:", poolAddress);

  // Get UserRegistry address
  const userRegistryAddress = await pool.userRegistry();
  console.log("UserRegistry deployed to:", userRegistryAddress);

  // Configure initial settings
  const DISTRIBUTOR_ROLE = await pool.DISTRIBUTOR_ROLE();
  await pool.grantRole(DISTRIBUTOR_ROLE, deployer.address);
  console.log("Granted DISTRIBUTOR_ROLE to deployer");

  return {
    pool: poolAddress,
    userRegistry: userRegistryAddress,
  };
}

main()
  .then((addresses) => {
    console.log("Deployment successful!");
    console.log("Contract addresses:", addresses);
    process.exit(0);
  })
  .catch((error) => {
    console.error("Deployment failed:", error);
    process.exit(1);
  });
```

### Verification Script (`scripts/verify.ts`)

```typescript
import { run } from "hardhat";

async function verify(contractAddress: string, constructorArguments: any[]) {
  try {
    await run("verify:verify", {
      address: contractAddress,
      constructorArguments: constructorArguments,
    });
    console.log(`Contract ${contractAddress} verified successfully`);
  } catch (error) {
    console.error(`Verification failed for ${contractAddress}:`, error);
  }
}

async function main() {
  const poolAddress = "0x..."; // Replace with actual address
  const adminAddress = "0x..."; // Replace with actual admin address

  await verify(poolAddress, [adminAddress]);
}

main().catch(console.error);
```

## Post-Deployment Configuration

### 1. Role Configuration

```typescript
// Grant roles to appropriate addresses
await pool.grantRole(DISTRIBUTOR_ROLE, distributorAddress);
await pool.grantRole(DEFAULT_ADMIN_ROLE, multisigAddress);

// Revoke deployer's admin role (if transferring to multisig)
await pool.renounceRole(DEFAULT_ADMIN_ROLE, deployerAddress);
```

### 2. Parameter Tuning

Review and adjust these parameters based on network conditions:

- Gas price settings
- Distribution window timing
- Receiver limits
- Contribution limits

### 3. Monitoring Setup

Set up monitoring for:
- Failed transactions
- Distribution events
- Pool balance changes
- Admin actions

## Troubleshooting

### Common Deployment Issues

#### 1. Gas Price Too Low

```bash
Error: transaction underpriced
```

**Solution**: Increase gas price in network configuration or use EIP-1559 gas pricing.

#### 2. Insufficient Balance

```bash
Error: sender doesn't have enough funds
```

**Solution**: Fund the deployer account with more ETH.

#### 3. Contract Size Too Large

```bash
Error: contract code size limit exceeded
```

**Solution**: Enable optimizer in Hardhat config:

```typescript
solidity: {
  version: "0.8.20",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
},
```

#### 4. Verification Failures

**Common causes**:
- Wrong constructor arguments
- Flattened contract source mismatch
- Compiler settings mismatch

**Solution**: Ensure exact match of compilation settings and constructor arguments.

### Network-Specific Considerations

#### Ethereum Mainnet
- High gas costs - optimize for minimal gas usage
- Use EIP-1559 gas pricing
- Consider deployment during low-traffic periods

#### Layer 2 Solutions (Polygon, Arbitrum, Optimism)
- Lower gas costs but different block times
- May require network-specific configurations
- Consider finality differences

#### Test Networks
- Faucet limitations - may need multiple funding requests
- Network instability - retry failed transactions
- Different block times and gas limits

## Security Best Practices

### 1. Key Management

- Use hardware wallets for mainnet deployments
- Never commit private keys to version control
- Use environment variables for sensitive data
- Consider using deployment services like Defender

### 2. Access Control

- Use multi-signature wallets for admin functions
- Implement timelock for critical parameter changes
- Regularly rotate API keys
- Monitor for unauthorized transactions

### 3. Contract Security

- Enable contract pausing mechanisms
- Implement circuit breakers for large value transfers
- Monitor contract balance and unusual activity
- Prepare incident response procedures

## Deployment Checklist

### Pre-Deployment
- [ ] Environment configured
- [ ] Tests passing
- [ ] Gas estimates calculated
- [ ] Deployer account funded
- [ ] Network configuration verified

### Deployment
- [ ] Contracts deployed successfully
- [ ] Deployment transactions confirmed
- [ ] Contract addresses recorded
- [ ] Initial configuration completed

### Post-Deployment
- [ ] Contracts verified on Etherscan
- [ ] Admin roles configured
- [ ] Monitoring set up
- [ ] Documentation updated
- [ ] Team notified

### Production Readiness
- [ ] Security audit completed
- [ ] Emergency procedures tested
- [ ] Multisig configuration verified
- [ ] Backup and recovery plans in place

## Support and Resources

- **Hardhat Documentation**: https://hardhat.org/docs
- **OpenZeppelin**: https://docs.openzeppelin.com/
- **Etherscan**: https://etherscan.io/
- **Gas Tracker**: https://ethgasstation.info/

For deployment support or issues, please create an issue in the project repository.