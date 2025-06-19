The following is the business logic of the kindness system.
The document is very detailed and contains all the business logic of the system.
All technical considerations and why we made the decisions we made are included and chosen based on the best practices and the most secure way to build the system.
From the business logic, we can create our tests and our smart contracts.

Once the smart contract is deployed, the pool system will mark the current hour as the start of the 24 hours. There will be a strategy implemented to distribute the money to the receivers at the end of the 24 hours and reset the timer and pool for the next day.

Users Registry system

During the 24 hours, users can choose to send kindness (money) to the pool or receive kindness (money).

If they choose to send kindness (money) to the pool.
- They will be able to send an amount of Ether they decide between 0.001 and 1 ETH, from their farcaster wallet to the money pool address. The amount will be added to the pool. The amount will be deducted from their balance.
- Once the money is sent to the pool, the user stats will be updated, adding the amount they sent to the pool to their total contribution amount.
- Once the money is sent to the pool, they will be able to decide to withdraw their money from the pool.
- Users who have contributed to the pool cannot enter the receiver pool in the same day.

If they choose to receive kindness (money).
- They will be able to get in the receiver array, which is a list of users that will share the money pool equally at the end of the 24 hours.
- Once they are in the receiver array, they will be able to see their total stats in the page. And decide to withdraw their request to receive money from the pool.
- At the end of the 24 hours, if they are still in the receiver array, the user will receive money from the pool.
- If a user's transfer fails during distribution, they will be removed from the receiver pool and their share will be redistributed among the remaining receivers.