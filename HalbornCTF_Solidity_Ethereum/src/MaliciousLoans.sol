// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MaliciousLoans {
    bool public hacked = false;

    function maliciousAction() external returns (bool) {
        hacked = true;
        return hacked;
    }
}