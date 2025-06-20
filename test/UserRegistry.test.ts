import { expect } from "chai";
import { ethers } from "hardhat";
import { UserRegistry } from "../typechain-types";

describe("UserRegistry", function () {
  let userRegistry: UserRegistry;
  let owner: any;
  let addr1: any;
  let addr2: any;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
  });

  describe("Deployment", function () {
    it("Should deploy with valid system address", async function () {
      const UserRegistry = await ethers.getContractFactory("UserRegistry");
      userRegistry = await UserRegistry.deploy(owner.address);
      await userRegistry.waitForDeployment();

      expect(await userRegistry.system()).to.equal(owner.address);
      expect(await userRegistry.owner()).to.equal(owner.address);
    });

    it("Should fail to deploy with zero address", async function () {
      const UserRegistry = await ethers.getContractFactory("UserRegistry");
      const zeroAddress = "0x0000000000000000000000000000000000000000";

      await expect(UserRegistry.deploy(zeroAddress))
        .to.be.revertedWithCustomError(userRegistry, "OwnableInvalidOwner")
        .withArgs(zeroAddress);
    });
  });

  describe("Access Control", function () {
    beforeEach(async function () {
      const UserRegistry = await ethers.getContractFactory("UserRegistry");
      userRegistry = await UserRegistry.deploy(owner.address);
      await userRegistry.waitForDeployment();
    });

    it("Should allow owner to update system address", async function () {
      await expect(userRegistry.connect(owner).updateSystem(addr1.address))
        .to.emit(userRegistry, "SystemUpdated")
        .withArgs(addr1.address);

      expect(await userRegistry.system()).to.equal(addr1.address);
    });

    it("Should prevent non-owner from updating system address", async function () {
      await expect(userRegistry.connect(addr1).updateSystem(addr2.address))
        .to.be.revertedWithCustomError(userRegistry, "OwnableUnauthorizedAccount")
        .withArgs(addr1.address);
    });

    it("Should prevent owner from setting zero address as system", async function () {
      const zeroAddress = "0x0000000000000000000000000000000000000000";
      await expect(userRegistry.connect(owner).updateSystem(zeroAddress))
        .to.be.revertedWithCustomError(userRegistry, "ZeroAddress");
    });

    it("Should allow system to update receiver pool status", async function () {
      await expect(userRegistry.connect(owner).updateReceiverPoolStatus(addr1.address, true))
        .to.emit(userRegistry, "ReceiverPoolStatusUpdated")
        .withArgs(addr1.address, true);
    });

    it("Should prevent non-system from updating receiver pool status", async function () {
      await expect(userRegistry.connect(addr1).updateReceiverPoolStatus(addr2.address, true))
        .to.be.revertedWithCustomError(userRegistry, "NotSystem");
    });
  });

  describe("User Statistics", function () {
    beforeEach(async function () {
      const UserRegistry = await ethers.getContractFactory("UserRegistry");
      userRegistry = await UserRegistry.deploy(owner.address);
      await userRegistry.waitForDeployment();
    });
    it("Should prevent non-system from updating user stats", async function () {
      await expect(userRegistry.connect(addr1).updateUserStats(addr2.address, true, 100))
        .to.be.revertedWithCustomError(userRegistry, "NotSystem");
    });

    it("Should allow system to update user stats", async function () {
      await expect(userRegistry.connect(owner).updateUserStats(addr2.address, true, 100))
        .to.emit(userRegistry, "UserStatsUpdated")
        .withArgs(addr2.address, true, 100, 100, 0, 100);
    });

    it("Should allow users to set their own name", async function () {
      const name = "Test User";
      await expect(userRegistry.connect(addr1).setName(name))
        .to.emit(userRegistry, "UserNameUpdated")
        .withArgs(addr1.address, name);
    });

    it("Should prevent setting empty name", async function () {
      await expect(userRegistry.connect(addr1).setName(""))
        .to.be.revertedWithCustomError(userRegistry, "EmptyName");
    });

    it("Should prevent setting name longer than 32 characters", async function () {
      const longName = "This name is way too long to be accepted by the contract";
      await expect(userRegistry.connect(addr1).setName(longName))
        .to.be.revertedWithCustomError(userRegistry, "NameTooLong");
    });
  });
});