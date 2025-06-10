import { ethers } from "hardhat";
import { verify } from "./utils/verify";
import { UserRegistry__factory } from "../typechain-types";

async function main() {
  try {
    // Get the deployer's signer (account)
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // Check deployer's balance
    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("Deployer balance:", ethers.formatEther(balance), "ETH");
    if (balance < ethers.parseEther("0.1")) {
      throw new Error("Insufficient balance for deployment");
    }

    // Deploy UserRegistry with deployer as temporary admin
    console.log("\nDeploying UserRegistry...");
    const UserRegistry: UserRegistry__factory = await ethers.getContractFactory("UserRegistry");
    const userRegistry = await UserRegistry.deploy(deployer.address);
    await userRegistry.waitForDeployment();
    const userRegistryAddress = await userRegistry.getAddress();
    console.log("UserRegistry deployed to:", userRegistryAddress);

    // Verify UserRegistry deployment
    console.log("\nVerifying UserRegistry deployment...");
    const userRegistryCode = await ethers.provider.getCode(userRegistryAddress);
    if (userRegistryCode === "0x") {
      throw new Error("UserRegistry deployment failed - no code at address");
    }

    // Deploy Pool contract
    console.log("\nDeploying Pool...");
    const Pool = await ethers.getContractFactory("Pool");
    const pool = await Pool.deploy(deployer.address);
    await pool.waitForDeployment();
    const poolAddress = await pool.getAddress();
    console.log("Pool deployed to:", poolAddress);

    // Verify Pool deployment
    console.log("\nVerifying Pool deployment...");
    const poolCode = await ethers.provider.getCode(poolAddress);
    if (poolCode === "0x") {
      throw new Error("Pool deployment failed - no code at address");
    }

    // Transfer UserRegistry ownership to Pool
    console.log("\nTransferring UserRegistry ownership to Pool...");
    try {
      const tx = await userRegistry.transferOwnership(poolAddress);
      await tx.wait();
      console.log("UserRegistry ownership transferred to Pool");

      // Verify ownership transfer
      const newOwner = await userRegistry.owner();
      if (newOwner !== poolAddress) {
        throw new Error("Ownership transfer verification failed");
      }
    } catch (error) {
      console.error("Failed to transfer ownership:", error);
      console.log("Emergency: Keeping deployer as owner");
      // Continue with deployment as deployer remains owner
    }

    // Deploy TimeBasedDistributor
    console.log("\nDeploying TimeBasedDistributor...");
    const TimeBasedDistributor = await ethers.getContractFactory("TimeBasedDistributor");
    const timeBasedDistributor = await TimeBasedDistributor.deploy(poolAddress);
    await timeBasedDistributor.waitForDeployment();
    const distributorAddress = await timeBasedDistributor.getAddress();
    console.log("TimeBasedDistributor deployed to:", distributorAddress);

    // Verify TimeBasedDistributor deployment
    console.log("\nVerifying TimeBasedDistributor deployment...");
    const distributorCode = await ethers.provider.getCode(distributorAddress);
    if (distributorCode === "0x") {
      throw new Error("TimeBasedDistributor deployment failed - no code at address");
    }

    // Grant DISTRIBUTOR_ROLE to TimeBasedDistributor
    console.log("\nGranting DISTRIBUTOR_ROLE to TimeBasedDistributor...");
    try {
      const DISTRIBUTOR_ROLE = await pool.DISTRIBUTOR_ROLE();
      const tx2 = await pool.grantRole(DISTRIBUTOR_ROLE, distributorAddress);
      await tx2.wait();
      console.log("DISTRIBUTOR_ROLE granted successfully");

      // Verify role grant
      const hasRole = await pool.hasRole(DISTRIBUTOR_ROLE, distributorAddress);
      if (!hasRole) {
        throw new Error("Role grant verification failed");
      }
    } catch (error) {
      console.error("Failed to grant DISTRIBUTOR_ROLE:", error);
      throw new Error("Critical: Failed to grant DISTRIBUTOR_ROLE");
    }

    // Verify contracts on Etherscan (if not on a local network)
    if (process.env.ETHERSCAN_API_KEY) {
      console.log("\nVerifying contracts on Etherscan...");
      try {
        await verify(userRegistryAddress, [deployer.address]);
        await verify(poolAddress, [deployer.address]);
        await verify(distributorAddress, [poolAddress]);
      } catch (error) {
        console.error("Failed to verify contracts on Etherscan:", error);
        // Continue as verification is not critical
      }
    }

    // Log deployment summary
    console.log("\nDeployment Summary:");
    console.log("------------------");
    console.log("UserRegistry:", userRegistryAddress);
    console.log("Pool:", poolAddress);
    console.log("TimeBasedDistributor:", distributorAddress);
    console.log("\nDeployment completed successfully!");

  } catch (error) {
    console.error("\nDeployment failed:", error);
    process.exitCode = 1;
  }
}

// Error handling
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});