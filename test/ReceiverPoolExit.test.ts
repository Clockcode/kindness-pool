import { expect } from "chai";
import { ethers } from "hardhat";
import { Pool, UserRegistry } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("Receiver Pool Exit Functionality", function () {
  let pool: Pool;
  let userRegistry: UserRegistry;
  let owner: HardhatEthersSigner;
  let user1: HardhatEthersSigner;
  let user2: HardhatEthersSigner;
  let distributor: HardhatEthersSigner;

  beforeEach(async function () {
    [owner, user1, user2, distributor] = await ethers.getSigners();

    const PoolFactory = await ethers.getContractFactory("Pool");
    pool = await PoolFactory.deploy(owner.address);

    userRegistry = await ethers.getContractAt("UserRegistry", await pool.userRegistry());

    // Transfer ownership of UserRegistry to Pool contract so it can call UserRegistry functions
    await userRegistry.transferOwnership(await pool.getAddress());

    // Grant distributor role
    await pool.grantRole(await pool.DISTRIBUTOR_ROLE(), distributor.address);
  });

  describe("Leave Receiver Pool", function () {
    it("should allow users to leave receiver pool", async function () {
      // Enter receiver pool
      await pool.connect(user1).enterReceiverPool();
      expect(await userRegistry.isInReceiverPool(user1.address)).to.be.true;

      // Fast forward 30 minutes to bypass cooldown
      await ethers.provider.send("evm_increaseTime", [1800]);
      await ethers.provider.send("evm_mine", []);

      // Leave receiver pool
      await pool.connect(user1).leaveReceiverPool();
      expect(await userRegistry.isInReceiverPool(user1.address)).to.be.false;
    });

    it("should prevent users not in receiver pool from leaving", async function () {
      await expect(
        pool.connect(user1).leaveReceiverPool()
      ).to.be.revertedWithCustomError(pool, "NotInReceiverPool");
    });

    it("should enforce daily exit limit", async function () {
      // Enter receiver pool
      await pool.connect(user1).enterReceiverPool();

      // Fast forward 30 minutes to bypass cooldown
      await ethers.provider.send("evm_increaseTime", [1800]);
      await ethers.provider.send("evm_mine", []);

      // Leave receiver pool
      await pool.connect(user1).leaveReceiverPool();

      // Fast forward 30 minutes to bypass cooldown
      await ethers.provider.send("evm_increaseTime", [1800]);
      await ethers.provider.send("evm_mine", []);

      // Enter again
      await pool.connect(user1).enterReceiverPool();

      // Fast forward 30 minutes to bypass cooldown
      await ethers.provider.send("evm_increaseTime", [1800]);
      await ethers.provider.send("evm_mine", []);

      // Try to leave again (should fail due to daily limit)
      await expect(
        pool.connect(user1).leaveReceiverPool()
      ).to.be.revertedWithCustomError(pool, "DailyReceiverExitLimitExceeded");
    });

    it("should enforce cooldown between receiver pool actions", async function () {
      // Enter receiver pool
      await pool.connect(user1).enterReceiverPool();

      // Try to leave immediately (should fail due to cooldown)
      await expect(
        pool.connect(user1).leaveReceiverPool()
      ).to.be.revertedWithCustomError(pool, "TooManyActions");
    });
  });

  describe("Emergency Exit", function () {
    it("should allow admin to emergency exit users", async function () {
      // Enter receiver pool
      await pool.connect(user1).enterReceiverPool();
      expect(await userRegistry.isInReceiverPool(user1.address)).to.be.true;

      // Admin emergency exit
      await pool.connect(owner).emergencyExitReceiverPool(user1.address);
      expect(await userRegistry.isInReceiverPool(user1.address)).to.be.false;
    });

    it("should prevent non-admin from emergency exit", async function () {
      // Enter receiver pool
      await pool.connect(user1).enterReceiverPool();

      // Non-admin tries emergency exit (should fail)
      await expect(
        pool.connect(user1).emergencyExitReceiverPool(user1.address)
      ).to.be.reverted;
    });

    it("should prevent emergency exit for users not in receiver pool", async function () {
      await expect(
        pool.connect(owner).emergencyExitReceiverPool(user1.address)
      ).to.be.revertedWithCustomError(pool, "NotInReceiverPool");
    });
  });

  describe("Daily Stats with Exit Tracking", function () {
    it("should track daily exits in stats", async function () {
      // Enter receiver pool
      await pool.connect(user1).enterReceiverPool();

      // Fast forward 30 minutes to bypass cooldown
      await ethers.provider.send("evm_increaseTime", [1800]);
      await ethers.provider.send("evm_mine", []);

      // Leave receiver pool
      await pool.connect(user1).leaveReceiverPool();

      // Check stats
      const stats = await pool.getUserDailyStats(user1.address);
      expect(stats.receiverEntries).to.equal(1);
      expect(stats.receiverExits).to.equal(1);
      expect(stats.canLeaveReceiverPool).to.be.false; // Already used daily exit
    });

    it("should reset daily exits on new day", async function () {
      // Enter and leave receiver pool today
      await pool.connect(user1).enterReceiverPool();

      await ethers.provider.send("evm_increaseTime", [1800]);
      await ethers.provider.send("evm_mine", []);

      await pool.connect(user1).leaveReceiverPool();

      // Fast forward to next day
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);

      // Enter receiver pool again
      await pool.connect(user1).enterReceiverPool();

      // Check stats (should be reset)
      const stats = await pool.getUserDailyStats(user1.address);
      expect(stats.receiverEntries).to.equal(1);
      expect(stats.receiverExits).to.equal(0); // Reset on new day
      expect(stats.canLeaveReceiverPool).to.be.true; // Can leave again
    });
  });
});