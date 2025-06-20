import { expect } from "chai";
import { ethers } from "hardhat";
import { Pool, UserRegistry } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("Daily Contribution Tracking", function () {
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

  describe("Daily Reset Mechanism", function () {
    it("should reset daily data when user interacts on a new day", async function () {
      // User contributes today
      await pool.connect(user1).giveKindness(ethers.parseEther("0.1"), {
        value: ethers.parseEther("0.1")
      });

      // Check daily stats
      let stats = await pool.getUserDailyStats(user1.address);
      expect(stats.contributionAmount).to.equal(ethers.parseEther("0.1"));
      expect(stats.receiverEntries).to.equal(0);

      // Fast forward to next day
      await ethers.provider.send("evm_increaseTime", [86400]); // 1 day
      await ethers.provider.send("evm_mine", []);

      // User contributes again (should reset and allow)
      await pool.connect(user1).giveKindness(ethers.parseEther("0.2"), {
        value: ethers.parseEther("0.2")
      });

      // Check that daily data was reset
      stats = await pool.getUserDailyStats(user1.address);
      expect(stats.contributionAmount).to.equal(ethers.parseEther("0.2"));
      expect(stats.receiverEntries).to.equal(0);
    });
  });

  describe("Daily Contribution Limits", function () {
    it("should enforce daily contribution limit", async function () {
      const maxDaily = await pool.MAX_DAILY_CONTRIBUTION();
      const maxPerTransaction = await pool.MAX_KINDNESS_AMOUNT();

      // Calculate how many transactions we need to reach the daily limit
      const transactionsNeeded = Math.ceil(Number(maxDaily) / Number(maxPerTransaction));

      // Contribute up to the limit in multiple transactions
      for (let i = 0; i < transactionsNeeded - 1; i++) {
        await pool.connect(user1).giveKindness(maxPerTransaction, {
          value: maxPerTransaction
        });
      }

      // Try to contribute the remaining amount (should succeed)
      const remaining = maxDaily - (BigInt(transactionsNeeded - 1) * maxPerTransaction);
      if (remaining > 0) {
        await pool.connect(user1).giveKindness(remaining, {
          value: remaining
        });
      }

      // Try to contribute more (should fail)
      await expect(
        pool.connect(user1).giveKindness(ethers.parseEther("0.1"), {
          value: ethers.parseEther("0.1")
        })
      ).to.be.revertedWithCustomError(pool, "DailyContributionLimitExceeded");
    });

    it("should allow contribution after daily reset", async function () {
      const maxDaily = await pool.MAX_DAILY_CONTRIBUTION();
      const maxPerTransaction = await pool.MAX_KINDNESS_AMOUNT();

      // Calculate how many transactions we need to reach the daily limit
      const transactionsNeeded = Math.ceil(Number(maxDaily) / Number(maxPerTransaction));

      // Contribute up to the limit in multiple transactions
      for (let i = 0; i < transactionsNeeded; i++) {
        const amount = i === transactionsNeeded - 1 ?
          maxDaily - (BigInt(i) * maxPerTransaction) :
          maxPerTransaction;
        await pool.connect(user1).giveKindness(amount, {
          value: amount
        });
      }

      // Fast forward to next day
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);

      // Should be able to contribute again
      await pool.connect(user1).giveKindness(ethers.parseEther("0.1"), {
        value: ethers.parseEther("0.1")
      });
    });
  });

  describe("Daily Receiver Entry Limits", function () {
    it("should enforce daily receiver entry limit", async function () {
      // Enter receiver pool once
      await pool.connect(user1).enterReceiverPool();

      // Try to enter again (should fail)
      await expect(
        pool.connect(user1).enterReceiverPool()
      ).to.be.revertedWithCustomError(pool, "TooManyActions");
    });

    it("should prevent users who contributed from entering receiver pool", async function () {
      // Contribute first
      await pool.connect(user1).giveKindness(ethers.parseEther("0.1"), {
        value: ethers.parseEther("0.1")
      });

      // Try to enter receiver pool (should fail)
      await expect(
        pool.connect(user1).enterReceiverPool()
      ).to.be.revertedWithCustomError(pool, "ContributedToday");
    });
  });

  describe("Helper Functions", function () {
    it("should return correct daily stats", async function () {
      // Check initial stats
      let stats = await pool.getUserDailyStats(user1.address);
      expect(stats.contributionAmount).to.equal(0);
      expect(stats.receiverEntries).to.equal(0);
      expect(stats.canContribute).to.be.true;
      expect(stats.canEnterReceiverPool).to.be.true;

      // Contribute some amount
      await pool.connect(user1).giveKindness(ethers.parseEther("0.1"), {
        value: ethers.parseEther("0.1")
      });

      // Check updated stats
      stats = await pool.getUserDailyStats(user1.address);
      expect(stats.contributionAmount).to.equal(ethers.parseEther("0.1"));
      expect(stats.canContribute).to.be.true;
      expect(stats.canEnterReceiverPool).to.be.false; // Can't enter because contributed
    });

    it("should return correct remaining contribution amount", async function () {
      const maxDaily = await pool.MAX_DAILY_CONTRIBUTION();

      // Check initial remaining amount
      let remaining = await pool.getRemainingDailyContribution(user1.address);
      expect(remaining).to.equal(maxDaily);

      // Contribute some amount
      const contribution = ethers.parseEther("1");
      await pool.connect(user1).giveKindness(contribution, {
        value: contribution
      });

      // Check remaining amount
      remaining = await pool.getRemainingDailyContribution(user1.address);
      expect(remaining).to.equal(maxDaily - contribution);
    });
  });
});