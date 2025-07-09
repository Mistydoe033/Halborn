// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract MaliciousLoans is UUPSUpgradeable {
    bool public hacked = false;

    function maliciousAction() external returns (bool) {
        hacked = true;
        return hacked;
    }

    function _authorizeUpgrade(address) internal override {}

    function proxiableUUID() external pure override returns (bytes32) {
        // ✅ Correct UUID for UUPS compatibility (per OpenZeppelin)
        return 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    }
}
