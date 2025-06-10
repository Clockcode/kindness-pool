import { expect } from "chai";
import { ethers } from "hardhat";
import { TimeBasedDistributor, Pool, UserRegistry } from "../typechain-types";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

describe("TimeBasedDistributor", function () {
  let timeBasedDistributor: TimeBasedDistributor;
  let pool: Pool;
  let owner: any;
  let addr1: any;
  let addr2: any;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    // Deploy Pool first
    const Pool = await ethers.getContractFactory("Pool");
    pool = await Pool.deploy(owner.address);
    await pool.waitForDeployment();

    // Get the UserRegistry instance and grant system role to Pool
    const userRegistryAddress = await pool.userRegistry();
    const UserRegistry = await ethers.getContractFactory("UserRegistry");
    const userRegistry = await UserRegistry.attach(userRegistryAddress) as UserRegistry;
    await userRegistry.connect(owner).updateSystem(await pool.getAddress());

    // Deploy TimeBasedDistributor
    const TimeBasedDistributor = await ethers.getContractFactory("TimeBasedDistributor");
    timeBasedDistributor = await TimeBasedDistributor.deploy(await pool.getAddress());
    await timeBasedDistributor.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should deploy with valid pool and owner addresses", async function () {
      const TimeBasedDistributor = await ethers.getContractFactory("TimeBasedDistributor");
      timeBasedDistributor = await TimeBasedDistributor.deploy(
        await pool.getAddress()
      );
      await timeBasedDistributor.waitForDeployment();

      expect(await timeBasedDistributor.pool()).to.equal(await pool.getAddress());
      expect(await timeBasedDistributor.hasRole(await timeBasedDistributor.DEFAULT_ADMIN_ROLE(), owner.address)).to.equal(true);
    });

    it("Should fail to deploy with zero pool address", async function () {
      const TimeBasedDistributor = await ethers.getContractFactory("TimeBasedDistributor");
      const zeroAddress = "0x0000000000000000000000000000000000000000";

      await expect(TimeBasedDistributor.deploy(zeroAddress))
        .to.be.revertedWithCustomError(timeBasedDistributor, "ZeroAddress");
    });

    it("Should fail to deploy with zero owner address", async function () {
      const TimeBasedDistributor = await ethers.getContractFactory("TimeBasedDistributor");
      const zeroAddress = "0x0000000000000000000000000000000000000000";

      await expect(TimeBasedDistributor.deploy(zeroAddress))
        .to.be.revertedWithCustomError(timeBasedDistributor, "ZeroAddress");
    });
  });

  describe("Access Control", function () {
    beforeEach(async function () {
      const TimeBasedDistributor = await ethers.getContractFactory("TimeBasedDistributor");
      timeBasedDistributor = await TimeBasedDistributor.deploy(await pool.getAddress());
      await timeBasedDistributor.waitForDeployment();
    });

    it("Should allow owner to update pool address", async function () {
      const newPool = await ethers.deployContract("Pool", [owner.address]);
      await expect(timeBasedDistributor.connect(owner).setPool(await newPool.getAddress()))
        .to.emit(timeBasedDistributor, "PoolAddressUpdated")
        .withArgs(await pool.getAddress(), await newPool.getAddress());
    });

    it("Should prevent non-owner from updating pool address", async function () {
      const newPool = await ethers.deployContract("Pool", [owner.address]);
      await expect(timeBasedDistributor.connect(addr1).setPool(await newPool.getAddress()))
        .to.be.revertedWithCustomError(timeBasedDistributor, "AccessControlUnauthorizedAccount");
    });
    // For ownable contract, this is not needed as the owner is set in the constructor
    it("Should prevent setting zero address as pool", async function () {
      const zeroAddress = "0x0000000000000000000000000000000000000000";
      await expect(timeBasedDistributor.connect(owner).setPool(zeroAddress))
        .to.be.revertedWithCustomError(timeBasedDistributor, "ZeroAddress");
    });
  });

  describe("Distribution", function () {
    beforeEach(async function () {
      const TimeBasedDistributor = await ethers.getContractFactory("TimeBasedDistributor");
      timeBasedDistributor = await TimeBasedDistributor.deploy(await pool.getAddress());
      await timeBasedDistributor.waitForDeployment();
    });
    // TODO: It shouldn't allow anyone to attempt distribution
    it("Should only allow authorized distributors to attempt distribution", async function () {
      // Try with unauthorized user
      await expect(timeBasedDistributor.connect(addr1).attemptDistribution())
        .to.be.revertedWithCustomError(timeBasedDistributor, "NotDistributor");

      // Grant distributor role to addr1
      await timeBasedDistributor.grantRole(await timeBasedDistributor.DISTRIBUTOR_ROLE(), addr1.address);

      // Now addr1 should be able to call attemptDistribution
      // Note: It will still revert due to distribution window or other conditions
      // but we're testing that the function can be called
      await expect(timeBasedDistributor.connect(addr1).attemptDistribution())
        .to.be.revertedWithCustomError(timeBasedDistributor, "NotInDistributionWindow");
    });

    it("Should emit DistributionAttempted event", async function () {
      // Add funds
      await pool.connect(addr1).giveKindness(ethers.parseEther("0.5"), { value: ethers.parseEther("0.5") });

      // Add receiver
      await pool.connect(addr2).enterReceiverPool();

      // Grant distributor role to TimeBasedDistributor
      await pool.connect(owner).grantRole(await pool.DISTRIBUTOR_ROLE(), await timeBasedDistributor.getAddress());

      // Mock the pool's isWithinDistributionWindow to return true
      await pool.connect(owner).setDistributionWindow(true);

      // Grant distributor role to addr1
      await timeBasedDistributor.grantRole(await timeBasedDistributor.DISTRIBUTOR_ROLE(), addr1.address);

      await expect(timeBasedDistributor.connect(addr1).attemptDistribution())
        .to.emit(timeBasedDistributor, "DistributionAttempted")
        .withArgs(anyValue, true);
    });
  });
});