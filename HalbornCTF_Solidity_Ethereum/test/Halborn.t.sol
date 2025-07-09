// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Merkle} from "./murky/Merkle.sol";

import {HalbornNFT} from "../src/HalbornNFT.sol";
import {HalbornToken} from "../src/HalbornToken.sol";
import {HalbornLoans} from "../src/HalbornLoans.sol";

contract HalbornTest is Test {
    // Named addresses for test identity
    address public immutable ALICE = makeAddr("ALICE");
    address public immutable BOB = makeAddr("BOB");

    // Merkle proofs generated for specific leaf indices
    bytes32[] public ALICE_PROOF_1;
    bytes32[] public ALICE_PROOF_2;
    bytes32[] public BOB_PROOF_1;
    bytes32[] public BOB_PROOF_2;

    // Deployed contract instances
    HalbornNFT public nft;
    HalbornToken public token;
    HalbornLoans public loans;

    function setUp() public {
        // Instantiate Merkle tree utility
        Merkle m = new Merkle();
        // Create leaf nodes from user addresses and token IDs
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encodePacked(ALICE, uint256(15)));
        data[1] = keccak256(abi.encodePacked(ALICE, uint256(19)));
        data[2] = keccak256(abi.encodePacked(BOB, uint256(21)));
        data[3] = keccak256(abi.encodePacked(BOB, uint256(24)));

        // Compute Merkle root from leaf array
        bytes32 root = m.getRoot(data);

        // Generate Merkle proofs for each leaf
        ALICE_PROOF_1 = m.getProof(data, 0);
        ALICE_PROOF_2 = m.getProof(data, 1);
        BOB_PROOF_1 = m.getProof(data, 2);
        BOB_PROOF_2 = m.getProof(data, 3);

        // Ensure proofs verify against the root and correct leaf
        assertTrue(m.verifyProof(root, ALICE_PROOF_1, data[0]));
        assertTrue(m.verifyProof(root, ALICE_PROOF_2, data[1]));
        assertTrue(m.verifyProof(root, BOB_PROOF_1, data[2]));
        assertTrue(m.verifyProof(root, BOB_PROOF_2, data[3]));

        // Deploy and initialize NFT contract with whitelist Merkle root
        nft = new HalbornNFT();
        nft.initialize(root, 1 ether);

        // Deploy and initialize token contract
        token = new HalbornToken();
        token.initialize();

        // Deploy and initialize loans contract with token and NFT addresses
        loans = new HalbornLoans(2 ether);
        loans.initialize(address(token), address(nft));

        // Set loan contract as authorized minter/burner for the token
        token.setLoans(address(loans));
    }
}
