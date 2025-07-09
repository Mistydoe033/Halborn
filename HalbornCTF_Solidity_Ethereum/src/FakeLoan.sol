// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IHalbornToken {
    function mint(address to, uint256 amount) external;
}

contract FakeLoan {
    IHalbornToken public token;

    constructor(address _token) {
        token = IHalbornToken(_token);
    }

    function mintTo(address to, uint256 amount) external {
        token.mint(to, amount);
    }
}