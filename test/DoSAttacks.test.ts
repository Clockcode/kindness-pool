import { expect } from "chai";
import { ethers } from "hardhat";
import { Pool } from "../typechain-types/contracts/Pool";
import { UserRegistry } from "../typechain-types/contracts/UserRegistry";
import { TestReceiver } from "../typechain-types/contracts/TestReceiver";

describe("DoS Attack Tests", function () {
    let pool: Pool;
    let owner: any;
    let attacker: any;
    let normalUser: any;
    let users: any[];
    let userRegistry: UserRegistry;
    let testReceiver: TestReceiver;

    beforeEach(async function () {
        [owner, attacker, normalUser, ...users] = await ethers.getSigners();

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

        // Deploy TestReceiver for testing failed transfers
        const TestReceiver = await ethers.getContractFactory("TestReceiver");
        testReceiver = await TestReceiver.deploy(await pool.getAddress());
        await testReceiver.waitForDeployment();

        // Grant distributor role to owner
        const DISTRIBUTOR_ROLE = await pool.DISTRIBUTOR_ROLE();
        await pool.connect(owner).grantRole(DISTRIBUTOR_ROLE, owner.address);
    });

    describe("Gas Limit DoS Tests", function () {
        it("Should handle large receiver pool without running out of gas", async function () {
            // Add contributions to the pool
            const amount = ethers.parseEther("1");
            await pool.connect(normalUser).giveKindness(amount, { value: amount });

            // Try to add maximum number of receivers
            const maxReceivers = await pool.MAX_RECEIVERS();
            
            // Add receivers up to the limit
            for (let i = 0; i < Number(maxReceivers) && i < users.length; i++) {
                await pool.connect(users[i]).enterReceiverPool();
            }

            // Set distribution window open for testing
            await pool.connect(owner).setDistributionWindow(true);
            
            // Verify that we can still distribute without running out of gas
            await expect(pool.connect(owner).distributePool()).to.not.be.reverted;
        });

        it("Should prevent adding more than MAX_RECEIVERS", async function () {
            const maxReceivers = await pool.MAX_RECEIVERS();
            
            // Add receivers up to the limit
            for (let i = 0; i < Number(maxReceivers) && i < users.length; i++) {
                await pool.connect(users[i]).enterReceiverPool();
            }

            // Try to add one more receiver - should be rejected
            if (users.length > Number(maxReceivers)) {
                await expect(pool.connect(users[Number(maxReceivers)]).enterReceiverPool())
                    .to.be.revertedWithCustomError(pool, "MaxReceiversReached");
            }
        });

        it("Should handle failed transfers efficiently", async function () {
            // Add contribution to pool
            const amount = ethers.parseEther("1");
            await pool.connect(normalUser).giveKindness(amount, { value: amount });

            // Set up test receiver to fail transfers
            await testReceiver.setFail(true);
            
            // TestReceiver already in receiver pool via constructor

            // Add some normal receivers too
            for (let i = 0; i < 5 && i < users.length; i++) {
                await pool.connect(users[i]).enterReceiverPool();
            }

            // Set distribution window open for testing
            await pool.connect(owner).setDistributionWindow(true);
            
            // Distribution should handle failed transfers gracefully
            await expect(pool.connect(owner).distributePool()).to.not.be.reverted;
        });
    });

    describe("Transaction Limit DoS Tests", function () {
        it("Should enforce daily transaction limits", async function () {
            const maxTransactions = await pool.MAX_TRANSACTIONS_PER_DAY();
            
            // Perform maximum allowed transactions
            for (let i = 0; i < Number(maxTransactions); i++) {
                const amount = ethers.parseEther("0.001");
                await pool.connect(attacker).giveKindness(amount, { value: amount });
            }

            // Next transaction should fail
            const amount = ethers.parseEther("0.001");
            await expect(pool.connect(attacker).giveKindness(amount, { value: amount }))
                .to.be.revertedWithCustomError(pool, "TooManyTransactions");
        });

        it("Should demonstrate transaction count reset bug", async function () {
            const maxTransactions = await pool.MAX_TRANSACTIONS_PER_DAY();
            
            // Perform maximum allowed transactions
            for (let i = 0; i < Number(maxTransactions); i++) {
                const amount = ethers.parseEther("0.001");
                await pool.connect(attacker).giveKindness(amount, { value: amount });
            }

            // Verify we hit the limit
            const amount = ethers.parseEther("0.001");
            await expect(pool.connect(attacker).giveKindness(amount, { value: amount }))
                .to.be.revertedWithCustomError(pool, "TooManyTransactions");

            // Advance time by more than a day to trigger daily reset
            await ethers.provider.send("evm_increaseTime", [86401]); // 24 hours + 1 second
            await ethers.provider.send("evm_mine", []);

            // BUG: Transaction count is NOT reset, so user remains blocked
            // This demonstrates that the contract has a bug where transactionCount
            // is not included in the daily reset mechanism
            const amount2 = ethers.parseEther("0.001");
            await expect(pool.connect(attacker).giveKindness(amount2, { value: amount2 }))
                .to.be.revertedWithCustomError(pool, "TooManyTransactions");
        });

        it("Should prevent rapid-fire receiver pool entries", async function () {
            // Enter receiver pool
            await pool.connect(attacker).enterReceiverPool();
            
            // Try to enter again immediately - should fail due to cooldown
            await expect(pool.connect(attacker).enterReceiverPool())
                .to.be.revertedWithCustomError(pool, "TooManyActions");
        });
    });

    describe("Rate Limit DoS Tests", function () {
        it("Should enforce receiver pool action cooldown", async function () {
            // First, advance time to avoid transaction limit issues
            await ethers.provider.send("evm_increaseTime", [86401]); // 24 hours + 1 second
            await ethers.provider.send("evm_mine", []);
            
            // Enter receiver pool
            await pool.connect(attacker).enterReceiverPool();
            
            // Try to leave immediately - should fail due to cooldown
            await expect(pool.connect(attacker).leaveReceiverPool())
                .to.be.revertedWithCustomError(pool, "TooManyActions");
        });

        it("Should allow actions after cooldown period", async function () {
            // Perform an action
            const amount = ethers.parseEther("0.001");
            await pool.connect(attacker).giveKindness(amount, { value: amount });
            
            // Advance time by cooldown period
            const cooldown = await pool.ACTION_COOLDOWN();
            await ethers.provider.send("evm_increaseTime", [Number(cooldown)]);
            await ethers.provider.send("evm_mine", []);

            // Should be able to perform another action
            const amount2 = ethers.parseEther("0.001");
            await expect(pool.connect(attacker).giveKindness(amount2, { value: amount2 }))
                .to.not.be.reverted;
        });

        it("Should enforce daily contribution limits", async function () {
            // Make 5 contributions of 1 ETH each to reach the 5 ETH daily limit
            for (let i = 0; i < 5; i++) {
                const amount = ethers.parseEther("1");
                await pool.connect(attacker).giveKindness(amount, { value: amount });
                
                // Advance time to pass cooldown
                const cooldown = await pool.ACTION_COOLDOWN();
                await ethers.provider.send("evm_increaseTime", [Number(cooldown)]);
                await ethers.provider.send("evm_mine", []);
            }
            
            // Now we have reached the 5 ETH daily limit. Try to add more - this should fail
            const amount = ethers.parseEther("0.001"); // Small amount that should trigger daily limit error
            await expect(pool.connect(attacker).giveKindness(amount, { value: amount }))
                .to.be.revertedWithCustomError(pool, "DailyContributionLimitExceeded");
        });

        it("Should enforce daily receiver pool entry limits", async function () {
            const maxEntries = await pool.MAX_DAILY_RECEIVER_ENTRIES();
            
            // Make maximum allowed entries
            for (let i = 0; i < Number(maxEntries); i++) {
                await pool.connect(attacker).enterReceiverPool();
                
                // Advance time to pass cooldown
                const cooldown = await pool.RECEIVER_POOL_COOLDOWN();
                await ethers.provider.send("evm_increaseTime", [Number(cooldown)]);
                await ethers.provider.send("evm_mine", []);
                
                // Leave receiver pool to enter again
                await pool.connect(attacker).leaveReceiverPool();
                
                // Advance time to pass cooldown again
                await ethers.provider.send("evm_increaseTime", [Number(cooldown)]);
                await ethers.provider.send("evm_mine", []);
            }

            // Next entry should fail
            await expect(pool.connect(attacker).enterReceiverPool())
                .to.be.revertedWithCustomError(pool, "DailyReceiverEntryLimitExceeded");
        });
    });

    describe("Resource Exhaustion Tests", function () {
        it("Should handle many failed transfers without breaking", async function () {
            // Add contribution to pool
            const amount = ethers.parseEther("1");
            await pool.connect(normalUser).giveKindness(amount, { value: amount });

            // Create multiple failing receivers (smaller number for better tracking)
            const failingReceivers: TestReceiver[] = [];
            for (let i = 0; i < 3; i++) {
                const TestReceiver = await ethers.getContractFactory("TestReceiver");
                const receiver = await TestReceiver.deploy(await pool.getAddress());
                await receiver.waitForDeployment();
                await receiver.setFail(true);
                
                failingReceivers.push(receiver);
            }

            // Add one normal receiver to ensure distribution can work
            await pool.connect(users[0]).enterReceiverPool();

            // Set distribution window open for testing
            await pool.connect(owner).setDistributionWindow(true);
            
            // Distribution should handle all failed transfers
            await expect(pool.connect(owner).distributePool()).to.not.be.reverted;

            // Verify some failed transfers are tracked (at least one)
            let failedCount = 0;
            for (const receiver of failingReceivers) {
                const failedTransfer = await pool.failedTransfers(await receiver.getAddress());
                if (failedTransfer.amount > 0) {
                    failedCount++;
                }
            }
            expect(failedCount).to.be.gt(0);
        });

        it("Should prevent contract from being drained by failed transfer exploitation", async function () {
            // Add contribution to pool
            const contribution = ethers.parseEther("1");
            await pool.connect(normalUser).giveKindness(contribution, { value: contribution });

            // Set up failing receiver
            await testReceiver.setFail(true);

            // Add normal receiver too
            await pool.connect(users[0]).enterReceiverPool();

            const initialBalance = await ethers.provider.getBalance(await pool.getAddress());
            
            // Set distribution window open for testing
            await pool.connect(owner).setDistributionWindow(true);
            
            // Distribute pool
            await pool.connect(owner).distributePool();
            
            // Contract should still have funds (unclaimed from failed transfer)
            const finalBalance = await ethers.provider.getBalance(await pool.getAddress());
            expect(finalBalance).to.be.gt(0);
        });
    });
});