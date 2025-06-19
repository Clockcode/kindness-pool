// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPool {
    function enterReceiverPool() external;
}

/// @title TestReceiver
/// @notice Helper contract that can fail to receive Ether
contract TestReceiver {
    bool public fail = true;

    constructor(address pool) {
        IPool(pool).enterReceiverPool();
    }

    function setFail(bool _fail) external {
        fail = _fail;
    }

    receive() external payable {
        if (fail) {
            revert("fail");
        }
    }
}
