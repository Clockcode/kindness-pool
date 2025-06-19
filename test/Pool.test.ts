import { expect } from "chai";
import { ethers } from "hardhat";
import { Pool } from "../typechain-types/contracts/Pool";
import { UserRegistry } from "../typechain-types/contracts/UserRegistry";

describe("Pool", function () {
  let pool: Pool;
  let owner: any;
  let addr1: any;
  let addr2: any;
  let addr3: any;
  let userRegistry: UserRegistry;

  beforeEach(async function () {
    [owner, addr1, addr2, addr3] = await ethers.getSigners();

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
  });

  describe("Deployment", function () {
    it("Should deploy with valid system address", async function () {
      const userRegistry = await pool.userRegistry();
      expect(userRegistry).to.not.equal(ethers.ZeroAddress);
      expect(await pool.hasRole(await pool.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
    });

    it("Should fail to deploy with zero address", async function () {
      const zeroAddress = "0x0000000000000000000000000000000000000000";

      await expect((await ethers.getContractFactory("Pool")).deploy(zeroAddress))
        .to.be.revertedWithCustomError(pool, "ZeroAddress");
    });
  });

  describe("Access Control", function () {
    it("Should allow admin to grant distributor role", async function () {
      const DISTRIBUTOR_ROLE = await pool.DISTRIBUTOR_ROLE();
      await expect(pool.connect(owner).grantRole(DISTRIBUTOR_ROLE, addr1.address))
        .to.emit(pool, "RoleGranted")
        .withArgs(DISTRIBUTOR_ROLE, addr1.address, owner.address);
    });

    it("Should prevent non-admin from granting distributor role", async function () {
      const DISTRIBUTOR_ROLE = await pool.DISTRIBUTOR_ROLE();
      await expect(pool.connect(addr1).grantRole(DISTRIBUTOR_ROLE, addr2.address))
        .to.be.revertedWithCustomError(pool, "AccessControlUnauthorizedAccount")
        .withArgs(addr1.address, await pool.DEFAULT_ADMIN_ROLE());
    });

    it("Should allow distributor to distribute pool", async function () {
      const DISTRIBUTOR_ROLE = await pool.DISTRIBUTOR_ROLE();
      await pool.connect(owner).grantRole(DISTRIBUTOR_ROLE, addr1.address);

      // Add some funds to the pool
      await pool.connect(addr2).giveKindness(ethers.parseEther("0.5"), { value: ethers.parseEther("0.5") });

      // Add some receivers
      await pool.connect(addr3).enterReceiverPool();

      // Mock the distribution window
      await pool.connect(owner).setDistributionWindow(true);

      await expect(pool.connect(addr1).distributePool())
        .to.emit(pool, "PoolDistributed");
    });

    it("Should prevent non-distributor from distributing pool", async function () {
      await expect(pool.connect(addr1).distributePool())
        .to.be.revertedWithCustomError(pool, "AccessControlUnauthorizedAccount");
    });
  });

  describe("giveKindness", function () {
    it("Should accept amount within limits", async function () {
      const amount = ethers.parseEther("0.5"); // 0.5 ETH
      await expect(pool.connect(addr1).giveKindness(amount, { value: amount }))
        .to.emit(pool, "KindnessGiven")
        .withArgs(addr1.address, amount);
    });

    it("Should reject amount below minimum", async function () {
      const amount = ethers.parseEther("0.0005"); // 0.0005 ETH
      await expect(pool.connect(addr1).giveKindness(amount, { value: amount }))
        .to.be.revertedWithCustomError(pool, "AmountTooLow");
    });

    it("Should reject amount above maximum", async function () {
      const amount = ethers.parseEther("1.5"); // 1.5 ETH
      await expect(pool.connect(addr1).giveKindness(amount, { value: amount }))
        .to.be.revertedWithCustomError(pool, "AmountTooHigh");
    });

    it("Should reject if sent value doesn't match amount", async function () {
      const amount = ethers.parseEther("0.5"); // 0.5 ETH
      const sentValue = ethers.parseEther("0.6"); // 0.6 ETH
      await expect(pool.connect(addr1).giveKindness(amount, { value: sentValue }))
        .to.be.revertedWithCustomError(pool, "ValueMismatch");
    });
  });

  describe("enterReceiverPool", function () {
    it("Should prevent users who have contributed from entering receiver pool", async function () {
      // First contribute some ETH
      const amount = ethers.parseEther("0.5");
      await pool.connect(addr1).giveKindness(amount, { value: amount });

      // Try to enter receiver pool
      await expect(pool.connect(addr1).enterReceiverPool())
        .to.be.revertedWithCustomError(pool, "ContributedToday");
    });

    it("Should allow users who haven't contributed to enter receiver pool", async function () {
      await expect(pool.connect(addr1).enterReceiverPool())
        .to.emit(pool, "EnteredReceiverPool")
        .withArgs(addr1.address);
    });

    it("Should prevent users from entering receiver pool twice", async function () {
      // First enter
      await pool.connect(addr1).enterReceiverPool();

      // Increase time by ACTION_COOLDOWN + 1 second
      await ethers.provider.send("evm_increaseTime", [3601]); // 1 hour + 1 second
      await ethers.provider.send("evm_mine");

      // Try to enter again
      await expect(pool.connect(addr1).enterReceiverPool())
        .to.be.revertedWithCustomError(pool, "AlreadyInReceiverPool");
    });
  });
});