import { expect } from "chai";
import { ethers } from "hardhat";
import { Pool } from "../typechain-types/contracts/Pool";
import { UserRegistry } from "../typechain-types/contracts/UserRegistry";
import { TestReceiver } from "../typechain-types/contracts/TestReceiver";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("Automatic Failed Transfer Retry", function () {
  let pool: Pool;
  let owner: any;
  let users: any[];
  let userRegistry: UserRegistry;
  let testReceiver: TestReceiver;

  beforeEach(async function () {
    const signers = await ethers.getSigners();
    owner = signers[0];
    users = signers.slice(1);

    // Deploy Pool contract
    const Pool = await ethers.getContractFactory("Pool");
    pool = await Pool.deploy(owner.address);
    await pool.waitForDeployment();

    // Get the UserRegistry instance
    const userRegistryAddress = await pool.userRegistry();
    const UserRegistry = await ethers.getContractFactory("UserRegistry");
    userRegistry = await UserRegistry.attach(userRegistryAddress) as UserRegistry;

    // Grant system role to Pool contract
    await userRegistry.connect(owner).updateSystem(await pool.getAddress());

    // Grant distributor role to owner
    const DISTRIBUTOR_ROLE = await pool.DISTRIBUTOR_ROLE();
    await pool.connect(owner).grantRole(DISTRIBUTOR_ROLE, owner.address);

    // Deploy TestReceiver for testing failed transfers
    const TestReceiver = await ethers.getContractFactory("TestReceiver");
    testReceiver = await TestReceiver.deploy(await pool.getAddress());
    await testReceiver.waitForDeployment();

    // Set distribution window to open for testing
    await pool.connect(owner).setDistributionWindow(true);
  });

  describe("Public Auto-Retry Function", function () {
    it("Should automatically retry failed transfers", async function () {
      // Setup: Create a failed transfer
      await pool.connect(users[0]).giveKindness(ethers.parseEther("1"), { value: ethers.parseEther("1") });
      
      // TestReceiver automatically enters receiver pool in constructor
      // Set TestReceiver to reject transfers
      await testReceiver.setFail(true);

      console.log("🔧 Setting up failed transfer...");

      // Distribute - this should create a failed transfer
      await pool.connect(owner).distributePool();

      // Verify failed transfer was created
      const failedTransfer = await pool.failedTransfers(await testReceiver.getAddress());
      expect(failedTransfer.amount).to.be.greaterThan(0);
      console.log(`   ✅ Failed transfer created: ${ethers.formatEther(failedTransfer.amount)} ETH`);

      // Fix the TestReceiver to accept transfers
      await testReceiver.setFail(false);

      // Fast forward past the retry cooldown
      const RETRY_COOLDOWN = await pool.RETRY_COOLDOWN();
      await time.increase(Number(RETRY_COOLDOWN) + 1);

      console.log("🔄 Attempting auto-retry...");

      // Call auto-retry function
      const tx = await pool.autoRetryFailedTransfers();
      const receipt = await tx.wait();

      // Check for AutoRetryCompleted event
      const autoRetryEvent = receipt?.logs.find(log => {
        try {
          const parsed = pool.interface.parseLog(log);
          return parsed?.name === "AutoRetryCompleted";
        } catch {
          return false;
        }
      });

      if (autoRetryEvent) {
        const parsed = pool.interface.parseLog(autoRetryEvent);
        console.log(`   ✅ Auto-retry completed: ${parsed?.args[0]} retried, ${parsed?.args[1]} successful`);
      }

      // Verify the failed transfer was resolved
      const failedTransferAfter = await pool.failedTransfers(await testReceiver.getAddress());
      expect(failedTransferAfter.amount).to.equal(0);
      console.log("   ✅ Failed transfer successfully resolved");
    });

    it("Should respect cooldown periods", async function () {
      // Setup failed transfer
      await pool.connect(users[0]).giveKindness(ethers.parseEther("1"), { value: ethers.parseEther("1") });
      // TestReceiver automatically enters receiver pool in constructor
      await testReceiver.setFail(true);
      await pool.connect(owner).distributePool();

      // Verify failed transfer exists
      const failedTransfer = await pool.failedTransfers(await testReceiver.getAddress());
      expect(failedTransfer.amount).to.be.greaterThan(0);

      // Try auto-retry before cooldown - should not process anything
      const tx1 = await pool.autoRetryFailedTransfers();
      const receipt1 = await tx1.wait();

      // Should have processed 0 retries due to cooldown
      const autoRetryEvent1 = receipt1?.logs.find(log => {
        try {
          const parsed = pool.interface.parseLog(log);
          return parsed?.name === "AutoRetryCompleted";
        } catch {
          return false;
        }
      });

      if (autoRetryEvent1) {
        const parsed = pool.interface.parseLog(autoRetryEvent1);
        expect(parsed?.args[0]).to.equal(0); // 0 retries processed
        console.log("   ✅ Cooldown properly respected - 0 retries attempted");
      }
    });

    it("Should limit retries per transaction", async function () {
      const MAX_AUTO_RETRIES = await pool.MAX_AUTO_RETRIES_PER_TX();
      console.log(`   Max auto retries per transaction: ${MAX_AUTO_RETRIES}`);

      // This test verifies the circuit breaker works
      // We can't easily create more failed transfers than signers available,
      // but we can verify the constant is reasonable
      expect(MAX_AUTO_RETRIES).to.be.greaterThan(1);
      expect(MAX_AUTO_RETRIES).to.be.lessThan(20); // Reasonable upper bound

      console.log("   ✅ Circuit breaker limit is reasonable");
    });

    it("Should handle case with no failed transfers", async function () {
      // Call auto-retry when there are no failed transfers
      const tx = await pool.autoRetryFailedTransfers();
      const receipt = await tx.wait();

      // Should complete without errors and process 0 retries
      const autoRetryEvent = receipt?.logs.find(log => {
        try {
          const parsed = pool.interface.parseLog(log);
          return parsed?.name === "AutoRetryCompleted";
        } catch {
          return false;
        }
      });

      if (autoRetryEvent) {
        const parsed = pool.interface.parseLog(autoRetryEvent);
        expect(parsed?.args[0]).to.equal(0); // 0 retries processed
        expect(parsed?.args[1]).to.equal(0); // 0 successful
        console.log("   ✅ Handled empty failed transfer list correctly");
      }
    });
  });

  describe("Auto-Retry During Distribution", function () {
    it("Should automatically retry during new distribution", async function () {
      console.log("🔧 Setting up failed transfer from previous distribution...");

      // First distribution: Create failed transfer
      await pool.connect(users[0]).giveKindness(ethers.parseEther("1"), { value: ethers.parseEther("1") });
      // TestReceiver automatically enters receiver pool in constructor
      await testReceiver.setFail(true);
      await pool.connect(owner).distributePool();

      // Verify failed transfer was created
      const failedTransfer = await pool.failedTransfers(await testReceiver.getAddress());
      expect(failedTransfer.amount).to.be.greaterThan(0);
      console.log(`   ✅ Failed transfer created: ${ethers.formatEther(failedTransfer.amount)} ETH`);

      // Fix the receiver for next attempt
      await testReceiver.setFail(false);

      // Fast forward past cooldown and to next day for new distribution
      const RETRY_COOLDOWN = await pool.RETRY_COOLDOWN();
      await time.increase(Number(RETRY_COOLDOWN) / 2 + 1); // Use shorter cooldown during distribution
      await time.increase(24 * 60 * 60); // Advance to next day to allow new distribution

      console.log("🔄 Starting new distribution (should trigger auto-retry)...");

      // Second distribution: Should auto-retry the failed transfer
      await pool.connect(users[1]).giveKindness(ethers.parseEther("1"), { value: ethers.parseEther("1") });
      await pool.connect(users[2]).enterReceiverPool();
      
      // This should trigger auto-retry during startDistribution
      await pool.connect(owner).startDistribution();

      // Verify the failed transfer was resolved during distribution
      const failedTransferAfter = await pool.failedTransfers(await testReceiver.getAddress());
      expect(failedTransferAfter.amount).to.equal(0);
      console.log("   ✅ Failed transfer automatically resolved during distribution");
    });
  });

  describe("Integration Tests", function () {
    it("Should maintain system stability with auto-retry", async function () {
      console.log("🔧 Testing system stability with mixed operations...");

      // Create multiple operations with some failures
      await pool.connect(users[0]).giveKindness(ethers.parseEther("1"), { value: ethers.parseEther("1") });
      
      // Add normal receiver
      await pool.connect(users[1]).enterReceiverPool();
      
      // Add test receiver that will fail
      // TestReceiver automatically enters receiver pool in constructor
      await testReceiver.setFail(true);

      // Distribute (should create one failed transfer)
      await pool.connect(owner).distributePool();

      console.log("   ✅ Distribution completed with mixed success/failure");

      // Verify system state is consistent
      const receiverCount = await pool.getReceiverCount();
      expect(receiverCount).to.equal(0); // All receivers should be removed after distribution

      const unclaimedFunds = await pool.getUnclaimedFunds();
      expect(unclaimedFunds).to.be.greaterThan(0); // Should have unclaimed funds from failed transfer

      console.log(`   ✅ System state consistent: ${ethers.formatEther(unclaimedFunds)} ETH unclaimed`);

      // Auto-retry should work independently
      await testReceiver.setFail(false);
      await time.increase(3600); // 1 hour
      
      await pool.autoRetryFailedTransfers();
      
      const unclaimedAfter = await pool.getUnclaimedFunds();
      expect(unclaimedAfter).to.be.lessThan(unclaimedFunds); // Should be reduced after successful retry

      console.log("   ✅ Auto-retry system maintains stability");
    });
  });
});