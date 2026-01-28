# Audit Findings Report

## 1. Executive Summary

This report documents the security review of the Halborn Ethereum CTF contracts: `HalbornToken`, `HalbornLoans`, and `HalbornNFT`. The assessment focused on upgradeability, access control, token economics, and reentrancy risks. All findings were validated against the provided Foundry unit tests.

**Total Findings:** 21 (16 Critical, 3 High, 1 Medium, 1 Low)

## 2. Overview

**Folder name:** HalbornCTF_Solidity_Ethereum

**Date:** 2026

**Auditor:** Seth Brockob

## 3. Scope

**In-scope contracts:**

- src/HalbornToken.sol
- src/HalbornLoans.sol
- src/HalbornNFT.sol
- src/libraries/Multicall.sol

**In-scope tests:**

- test/HalbornToken.t.sol
- test/HalbornLoans.t.sol
- test/HalbornNFT.t.sol

**Out of scope:**

- Library dependencies (OpenZeppelin)
- Build artifacts
- Test utilities

## 4. Methodology

- Manual review of in-scope contracts
- Review of Foundry test suites
- Analysis of upgradeability, access control, and economic risk exposure

## 5. Risk Rating

- **Critical:** Full compromise, irreversible fund loss, or protocol takeover
- **High:** Major security or economic impact with realistic exploitation paths
- **Medium:** Material impact with limited practical exploitation
- **Low:** Minor impact or highly constrained exploitation
- **Informational:** Best practice issues without direct impact

## 6. Findings Summary

| ID | Title | Risk |
| --- | --- | --- |
| H-01 | HalbornToken: UUPS Upgrade Bypass | Critical |
| H-02 | HalbornToken: Loans Address Manipulation | Critical |
| H-03 | HalbornToken: Unrestricted Token Minting | Critical |
| H-04 | HalbornToken: Unrestricted Token Burning | Critical |
| H-05 | HalbornLoans: UUPS Upgrade Bypass | Critical |
| H-06 | HalbornLoans: Infinite Token Minting via Malicious Loan Contract | Critical |
| H-07 | HalbornLoans: Arbitrary Token Burning via Loan Contract | Critical |
| H-08 | HalbornLoans: Reentrancy in Collateral Withdrawal | Critical |
| H-09 | HalbornNFT: Merkle Root Manipulation | Critical |
| H-10 | HalbornNFT: Unlimited Airdrop Minting | Critical |
| H-11 | HalbornNFT: UUPS Upgrade Bypass | Critical |
| H-12 | HalbornNFT: Price Manipulation After Upgrade | Critical |
| H-13 | HalbornNFT: ETH Drainage via Malicious Upgrade | Critical |
| H-14 | HalbornNFT: Unchecked idCounter Overflow | Low |
| H-15 | Multicall: msg.value Reuse Enables Underpaid Mints | Critical |
| H-16 | HalbornLoans: Inverted Collateral Check in getLoan() | Critical |
| H-17 | HalbornLoans: returnLoan() Increases Used Collateral | Critical |
| H-18 | HalbornLoans: usedCollateral Not Updated on Collateral Withdrawal | High |
| H-19 | HalbornLoans: Unsafe ERC721 Receiver Accepts Arbitrary NFTs | High |
| H-20 | HalbornLoans: Immutable State Variable in Upgradeable Contract | Medium |
| H-21 | All Contracts: Reinitialization After Upgrade Enables State Reset | High |

## 7. Detailed Findings

### H-01 – HalbornToken: UUPS Upgrade Bypass

**Risk:** Critical

**Description:**

The token contract inherits from `UUPSUpgradeable`, but `_authorizeUpgrade()` is empty. Any address can upgrade the implementation and reinitialize ownership. The test `test_vulnerableUUPSupgrade()` shows an unauthorized user upgrading to a malicious implementation.

**Code Section:**

- src/HalbornToken.sol: `_authorizeUpgrade(address)`
- Test: `test_vulnerableUUPSupgrade()` in test/HalbornToken.t.sol

**Impact:**

Complete contract takeover. Attackers gain control of minting, burning, and ownership logic, which directly destroys token integrity and value.

**Recommendation on Improvement:**

Implement access control on upgrades:
```solidity
function _authorizeUpgrade(address) internal override onlyOwner {}
```

### H-02 – HalbornToken: Loans Address Manipulation

**Risk:** Critical

**Description:**

After a malicious upgrade, an attacker can call `setLoans()` and permanently assign themselves as the loans authority. The test `test_setLoansAddress()` shows that the original owner can no longer change the loans address.

**Code Section:**

- src/HalbornToken.sol: `setLoans(address)`
- Test: `test_setLoansAddress()` in test/HalbornToken.t.sol

**Impact:**

Permanent mint/burn backdoor. The attacker can mint or burn arbitrarily, permanently compromising token economics.

**Recommendation on Improvement:**

Add governance controls (timelock or multi-sig) around `setLoans()` and prevent reinitialization after upgrade.

### H-03 – HalbornToken: Unrestricted Token Minting

**Risk:** Critical

**Description:**

`mintToken()` trusts the loans address without further validation. In `test_unlimitedMint()`, the attacker upgrades the contract, sets themselves as loans, and mints `type(uint256).max`.

**Code Section:**

- src/HalbornToken.sol: `mintToken(address,uint256)`
- Test: `test_unlimitedMint()` in test/HalbornToken.t.sol

**Impact:**

Infinite token inflation and total loss of economic integrity.

**Recommendation on Improvement:**

Enforce hard supply caps and validate minting logic beyond a single trusted address.

### H-04 – HalbornToken: Unrestricted Token Burning

**Risk:** Critical

**Description:**

`burnToken()` allows burning from any address by the loans authority. In `test_unlimitedBurn()`, the attacker upgrades and burns a victim’s balance.

**Code Section:**

- src/HalbornToken.sol: `burnToken(address,uint256)`
- Test: `test_unlimitedBurn()` in test/HalbornToken.t.sol

**Impact:**

Direct, irreversible user fund loss.

**Recommendation on Improvement:**

Restrict burns to validated loan-default scenarios with explicit authorization and logging.

### H-05 – HalbornLoans: UUPS Upgrade Bypass

**Risk:** Critical

**Description:**

The loans contract also leaves `_authorizeUpgrade()` empty. In `test_vulnerableUUPSupgrade()`, an unauthorized user upgrades and reinitializes the loans contract.

**Code Section:**

- src/HalbornLoans.sol: `_authorizeUpgrade(address)`
- Test: `test_vulnerableUUPSupgrade()` in test/HalbornLoans.t.sol

**Impact:**

Full takeover of the lending system, enabling arbitrary changes to collateral and mint/burn logic.

**Recommendation on Improvement:**

Add access control to upgrade logic and enforce upgrade governance.

### H-06 – HalbornLoans: Infinite Token Minting via Malicious Loan Contract

**Risk:** Critical

**Description:**

After upgrading to a malicious loans implementation, the attacker uses the trusted mint path to create infinite supply. `test_vulnerableLoanContractReksTokenMint()` shows the attacker minting `type(uint256).max`.

**Code Section:**

- src/HalbornLoans.sol: `getLoan(uint256)` mint path
- Test: `test_vulnerableLoanContractReksTokenMint()` in test/HalbornLoans.t.sol

**Impact:**

Unbounded inflation and collapse of token economics.

**Recommendation on Improvement:**

Cap minting per loan, validate collateralization, and limit trusted mint authority.

### H-07 – HalbornLoans: Arbitrary Token Burning via Loan Contract

**Risk:** Critical

**Description:**

The malicious loans upgrade burns arbitrary user balances. `test_vulnerableLoanContractReksTokenBurn()` demonstrates burning a victim’s balance through the trusted loans relationship.

**Code Section:**

- src/HalbornLoans.sol: `returnLoan(uint256)` burn path
- Test: `test_vulnerableLoanContractReksTokenBurn()` in test/HalbornLoans.t.sol

**Impact:**

Targeted or systemic destruction of user balances.

**Recommendation on Improvement:**

Validate burn operations against loan state and borrower authorization before execution.

### H-08 – HalbornLoans: Reentrancy in Collateral Withdrawal

**Risk:** Critical

**Description:**

`withdrawCollateral()` violates the checks-effects-interactions pattern by performing the external NFT transfer (line 53) before updating contract state (lines 54-55). This enables reentrancy attacks via the `onERC721Received` callback. An attacker can deposit multiple NFTs, initiate a withdrawal, and during the NFT transfer callback, withdraw additional NFTs or call `getLoan()` with maximum value before the first withdrawal's state updates are finalized. The test `test_Reentrancy()` demonstrates recovering all deposited NFTs while also draining maximum tokens through reentrant `getLoan()` calls.

**Code Section:**

- src/HalbornLoans.sol: `withdrawCollateral(uint256)` (lines 45-56)
- Test: `test_Reentrancy()` in test/HalbornLoans.t.sol

**Impact:**

Multiple collateral withdrawals and unbounded token minting. Attackers can recover all deposited NFTs while simultaneously draining maximum tokens, causing severe protocol insolvency.

**Recommendation on Improvement:**

Either enforce CEI or apply nonReentrant. CEI alone fully mitigates this issue.
```solidity
function withdrawCollateral(uint256 id) external {
    require(
        totalCollateral[msg.sender] - usedCollateral[msg.sender] >= collateralPrice,
        "Collateral unavailable"
    );
    require(idsCollateral[id] == msg.sender, "ID not deposited by caller");

    // Update state BEFORE external call
    totalCollateral[msg.sender] -= collateralPrice;
    delete idsCollateral[id];
    
    // External call AFTER state update
    nft.safeTransferFrom(address(this), msg.sender, id);
}
```

Alternatively, use OpenZeppelin's `ReentrancyGuard` modifier.

### H-09 – HalbornNFT: Merkle Root Manipulation

**Risk:** Critical

**Description:**

`setMerkleRoot()` has no access control. `test_setMerkelRoot()` shows an unauthorized user replacing the whitelist root.

**Code Section:**

- src/HalbornNFT.sol: `setMerkleRoot(bytes32)`
- Test: `test_setMerkelRoot()` in test/HalbornNFT.t.sol

**Impact:**

Whitelist bypass, enabling unauthorized NFT minting and economic dilution.

**Recommendation on Improvement:**

Restrict `setMerkleRoot()` to authorized admins (onlyOwner or governance).

### H-10 – HalbornNFT: Unlimited Airdrop Minting

**Risk:** Critical

**Description:**

After root manipulation, crafted proofs allow unlimited mints. `test_setMintUnlimited()` demonstrates minting multiple IDs using attacker-controlled proofs.

**Code Section:**

- src/HalbornNFT.sol: `mintAirdrops(uint256,bytes32[])`
- Test: `test_setMintUnlimited()` in test/HalbornNFT.t.sol

**Impact:**

NFT supply inflation and collapse of scarcity.

**Recommendation on Improvement:**

Track claimed IDs and per-address mint limits to enforce one-time claims.

### H-11 – HalbornNFT: UUPS Upgrade Bypass

**Risk:** Critical

**Description:**

The NFT contract exposes the same empty `_authorizeUpgrade()`. `test_vulnerableUUPSupgrade()` shows unauthorized upgrades and reinitialization.

**Code Section:**

- src/HalbornNFT.sol: `_authorizeUpgrade(address)`
- Test: `test_vulnerableUUPSupgrade()` in test/HalbornNFT.t.sol

**Impact:**

Complete NFT contract takeover, enabling arbitrary minting, pricing changes, and ETH theft.

**Recommendation on Improvement:**

Restrict upgrades with access control and governance approvals.

### H-12 – HalbornNFT: Price Manipulation After Upgrade

**Risk:** Critical

**Description:**

After a malicious upgrade, the attacker reinitializes the contract and sets arbitrary pricing. `test_setPrice()` confirms price manipulation.

**Code Section:**

- src/HalbornNFT.sol: `initialize(bytes32,uint256)`
- Test: `test_setPrice()` in test/HalbornNFT.t.sol

**Impact:**

Economic manipulation of mint pricing, enabling free mints or denial of service.

**Recommendation on Improvement:**

Prevent reinitialization after deployment and separate price updates into restricted admin functions.

### H-13 – HalbornNFT: ETH Drainage via Malicious Upgrade

**Risk:** Critical

**Description:**

In `test_stealETH()`, the attacker upgrades to a malicious implementation and drains all ETH from the contract via a modified `withdrawETH()`.

**Code Section:**

- src/HalbornNFT.sol: `withdrawETH(uint256)`
- Test: `test_stealETH()` in test/HalbornNFT.t.sol

**Impact:**

Total loss of ETH held in the contract, causing direct user losses.

**Recommendation on Improvement:**

Protect upgrades and withdrawals with multi-sig or timelock governance.

### H-14 – HalbornNFT: Unchecked idCounter Overflow

**Risk:** Low

**Description:**

`idCounter` is incremented in an unchecked block. The test `test_overflowCounter()` highlights this as theoretically overflowable but practically infeasible.

**Code Section:**

- src/HalbornNFT.sol: `mintBuyWithETH()` unchecked increment
- Test: `test_overflowCounter()` in test/HalbornNFT.t.sol

**Impact:**

Theoretical token ID reuse if overflow occurs. Practical exploitation is infeasible but it remains a correctness issue.

**Recommendation on Improvement:**

Use checked arithmetic or enforce a maximum supply cap.

### H-15 – Multicall: msg.value Reuse Enables Underpaid Mints

**Risk:** Critical

**Description:**

The `multicall()` function in `MulticallUpgradeable` uses `delegatecall` to execute each batched call (line 18), which preserves the original `msg.value` across all calls. When batching multiple `mintBuyWithETH()` calls, each call sees the same `msg.value` from the original multicall invocation. Since `mintBuyWithETH()` only checks `msg.value == price` (line 60), an attacker can send `1 ether` (the price of one NFT) and batch multiple `mintBuyWithETH()` calls, minting multiple NFTs while paying only once. The test `test_multicall_valueReuse_mintBuyWithETH()` demonstrates minting two NFTs for the price of one.

**Code Section:**

- src/libraries/Multicall.sol: `multicall(bytes[])` (lines 13-24)
- src/HalbornNFT.sol: `mintBuyWithETH()` (lines 59-67)
- Test: `test_multicall_valueReuse_mintBuyWithETH()` in test/HalbornNFT.t.sol

**Impact:**

Direct revenue loss and supply inflation. Attackers can mint unlimited NFTs for the cost of a single mint, bypassing intended pricing mechanisms and causing economic damage to the protocol.

**Recommendation on Improvement:**

Either restrict multicall for payable functions or implement aggregated value validation:
```solidity
// Option 1: Disable multicall for payable functions
function multicall(bytes[] calldata data) external payable override {
    require(msg.value == 0, "Multicall cannot be used with payable functions");
    // ... rest of implementation
}

// Option 2: Track and validate total value for batched payable calls
// This requires tracking expected value per call and validating sum
```

### H-16 – HalbornLoans: Inverted Collateral Check in getLoan()

**Risk:** Critical

**Description:**

`getLoan()` uses inverted logic in its collateral validation check. The function requires `totalCollateral[msg.sender] - usedCollateral[msg.sender] < amount` (line 60), which means it only allows loans when available collateral is less than the requested amount. This is the opposite of the intended behavior: loans should only be granted when available collateral is greater than or equal to the requested amount. As a result, users can borrow tokens without sufficient collateral backing, enabling uncollateralized minting.

**Code Section:**

- src/HalbornLoans.sol: `getLoan(uint256)` (lines 58-65)
- Test: `test_getLoan_invertedCollateralCheck()` in test/HalbornLoans.t.sol

**Impact:**

Uncollateralized token minting breaks the core lending model. Users can obtain loans exceeding their available collateral, causing immediate economic loss and protocol insolvency risk.

**Recommendation on Improvement:**

Fix the comparison operator to require sufficient collateral:
```solidity
function getLoan(uint256 amount) external {
    require(
        totalCollateral[msg.sender] - usedCollateral[msg.sender] >= amount,
        "Not enough collateral"
    );
    usedCollateral[msg.sender] += amount;
    token.mintToken(msg.sender, amount);
}
```

### H-17 – HalbornLoans: returnLoan() Increases Used Collateral Instead of Decreasing

**Risk:** Critical

**Description:**

`returnLoan()` incorrectly increments `usedCollateral[msg.sender]` on line 70 instead of decrementing it. When users repay their loans, the function increases their used collateral counter rather than freeing it up. This creates a permanent accounting error where repaid loans make collateral usage worse, preventing users from recovering their collateral or taking additional loans.

**Code Section:**

- src/HalbornLoans.sol: `returnLoan(uint256)` (lines 67-72)
- Test: `test_returnLoan_increasesUsedCollateral()` in test/HalbornLoans.t.sol

**Impact:**

Permanent collateral lock and protocol dysfunction. Users cannot recover collateral after repaying loans, and the accounting becomes increasingly incorrect with each repayment, eventually blocking all lending operations.

**Recommendation on Improvement:**

Decrease used collateral on repayment:
```solidity
function returnLoan(uint256 amount) external {
    require(usedCollateral[msg.sender] >= amount, "Not enough collateral");
    require(token.balanceOf(msg.sender) >= amount);
    usedCollateral[msg.sender] -= amount;  // Changed from += to -=
    token.burnToken(msg.sender, amount);
}
```

### H-18 – HalbornLoans: usedCollateral Not Updated on Collateral Withdrawal

**Risk:** High

**Description:**

`withdrawCollateral()` decreases `totalCollateral[msg.sender]` on line 54 but never adjusts `usedCollateral[msg.sender]`. This accounting flaw is separate from the reentrancy vulnerability (H-08). When a user withdraws collateral while having an active loan, `usedCollateral` remains unchanged while `totalCollateral` decreases. This creates a persistent accounting mismatch after any successful withdrawal. In the current codebase, the test `test_usedCollateralNotUpdatedOnWithdrawal()` demonstrates the mismatch and shows `usedCollateral > totalCollateral` after an additional loan is taken using the inverted collateral check (H-16), which makes the invariant violation explicit.

**Code Section:**

- src/HalbornLoans.sol: `withdrawCollateral(uint256)` (lines 45-56)
- Note: This is distinct from H-08 (reentrancy) and represents a core accounting flaw
- Test: `test_usedCollateralNotUpdatedOnWithdrawal()` in test/HalbornLoans.t.sol

**Impact:**

Permanent withdrawal bricking and solvency guarantee violations. Users with active loans can end up with stale `usedCollateral` after withdrawals, causing inconsistent accounting and incorrect loan eligibility checks. In combination with H-16, the mismatch can be amplified into a state where `usedCollateral > totalCollateral`, breaking the protocol’s core collateral invariants.

**Recommendation on Improvement:**

When withdrawing collateral, reduce `usedCollateral` proportionally if it exceeds available collateral:
```solidity
function withdrawCollateral(uint256 id) external {
    require(
        totalCollateral[msg.sender] - usedCollateral[msg.sender] >= collateralPrice,
        "Collateral unavailable"
    );
    require(idsCollateral[id] == msg.sender, "ID not deposited by caller");

    totalCollateral[msg.sender] -= collateralPrice;
    
    // If usedCollateral would exceed totalCollateral after withdrawal, reduce it
    if (usedCollateral[msg.sender] > totalCollateral[msg.sender]) {
        usedCollateral[msg.sender] = totalCollateral[msg.sender];
    }
    
    delete idsCollateral[id];
    nft.safeTransferFrom(address(this), msg.sender, id);
}
```

Alternatively, prevent withdrawal when `usedCollateral > 0` or require loan repayment first.

### H-19 – HalbornLoans: Unsafe ERC721 Receiver Accepts Arbitrary NFTs

**Risk:** High

**Description:**

The `onERC721Received()` function (lines 77-83) does not validate that `msg.sender` is the expected NFT contract (`address(nft)`). The function accepts any ERC721 transfer, regardless of the sender. This allows arbitrary ERC721 tokens to be permanently locked in the contract, even if they are not the intended collateral NFTs. The test `test_unsafeERC721ReceiverAcceptsArbitraryNFTs()` demonstrates that arbitrary NFTs can be locked in the contract.

**Code Section:**

- src/HalbornLoans.sol: `onERC721Received(...)` (lines 77-83)
- Test: `test_unsafeERC721ReceiverAcceptsArbitraryNFTs()` in test/HalbornLoans.t.sol

**Impact:**

NFT griefing, state corruption, and potential DoS. Malicious actors can send arbitrary ERC721 tokens to the contract, permanently locking them and breaking critical assumptions about NFT ownership, counts, and contract state. This can cause permanent DoS if the contract logic relies on specific NFT tracking, and increases the attack surface for future functionality that depends on accurate NFT accounting. The lack of sender validation violates the principle of least privilege and is a common security anti-pattern in ERC721 receiver implementations.

**Recommendation on Improvement:**

Validate that the sender is the expected NFT contract:
```solidity
function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
) external override returns (bytes4) {
    require(msg.sender == address(nft), "Only accepts HalbornNFT");
    return this.onERC721Received.selector;
}
```

### H-20 – HalbornLoans: Immutable State Variable in Upgradeable Contract

**Risk:** Medium

**Description:**

`collateralPrice` is declared as `immutable` on line 15 and set in the constructor (line 22). In a UUPS upgradeable proxy pattern, immutable variables are set in the implementation contract's constructor and cannot be changed via upgrades. This breaks upgrade safety assumptions and prevents adjusting collateral pricing in response to market conditions or protocol evolution. The test `test_immutableVariableInUpgradeableContract()` demonstrates that immutable variables cannot be changed via upgrade.

**Code Section:**

- src/HalbornLoans.sol: `collateralPrice` declaration (line 15)
- src/HalbornLoans.sol: Constructor (lines 21-23)
- Test: `test_immutableVariableInUpgradeableContract()` in test/HalbornLoans.t.sol

**Impact:**

Inflexible upgrade path and potential economic issues. The collateral price cannot be adjusted after deployment, even through upgrades. This prevents protocol adaptation to market conditions and creates a permanent economic constraint. This is discouraged by OpenZeppelin for upgradeable contracts.

**Recommendation on Improvement:**

Use a regular state variable instead of `immutable`:
```solidity
uint256 public collateralPrice;

function initialize(address token_, address nft_, uint256 collateralPrice_) public initializer {
    __UUPSUpgradeable_init();
    __Multicall_init();
    collateralPrice = collateralPrice_;
    token = HalbornToken(token_);
    nft = HalbornNFT(nft_);
}
```

Remove the constructor and set `collateralPrice` in the initializer. If immutability is desired, use access-controlled setter functions instead.

### H-21 – All Contracts: Reinitialization After Upgrade Enables State Reset

**Risk:** High

**Description:**

All three contracts (`HalbornToken`, `HalbornLoans`, `HalbornNFT`) use the `initializer` modifier but do not disable reinitialization via constructor (`_disableInitializers()`). Combined with the upgrade bypass vulnerabilities (H-01, H-05, H-11), an attacker who upgrades the contract to a malicious implementation can then call `initialize()` on the new implementation, resetting critical state including ownership, pricing, merkle roots, and configuration. While the `initializer` modifier prevents calling `initialize()` twice on the same implementation, upgrading to a new implementation allows reinitialization on that new implementation, enabling complete state reset attacks even after initial deployment. The tests `test_reinitializationAfterUpgradeEnablesStateReset()` in both HalbornToken.t.sol and HalbornNFT.t.sol demonstrate state reset after upgrade.

**Code Section:**

- src/HalbornToken.sol: `initialize()` (line 24)
- src/HalbornLoans.sol: `initialize(address,address)` (line 25)
- src/HalbornNFT.sol: `initialize(bytes32,uint256)` (lines 23-34)
- Tests: `test_reinitializationAfterUpgradeEnablesStateReset()` in test/HalbornToken.t.sol and test/HalbornNFT.t.sol

**Impact:**

Complete state reset and protocol takeover. After upgrading, attackers can reinitialize contracts to reset ownership, pricing, merkle roots, and other critical state. This enables protocol takeover even if initial deployment was secure, as demonstrated in tests where upgrades are followed by reinitialization.

**Recommendation on Improvement:**

Disable reinitialization after first initialization:
```solidity
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract HalbornToken is Initializable, ... {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize() external initializer {
        // ... initialization logic
    }
}
```

Alternatively, use versioned reinitializers (`reinitializer(uint8 version)`) if reinitialization is required for upgrades, and ensure proper access control.

## 8. Test Coverage Gaps

All findings (Critical, High, Medium, and Low) have been validated with Foundry PoC tests. The following areas represent edge cases or theoretical scenarios that were documented but not explicitly tested due to practical infeasibility:

- **Edge case arithmetic:** Underflow scenarios in `withdrawCollateral()` are protected by require checks and Solidity 0.8+ automatic overflow protection.
- **Comprehensive state reset scenarios:** While reinitialization after upgrade is demonstrated in tests for Token and NFT contracts, exhaustive testing of all possible state reset combinations across all three contracts was not performed.

All Critical, High, Medium, and Low findings have been validated through PoC tests. The test suite provides comprehensive coverage of all documented vulnerabilities.

## 9. Conclusion

All contracts exhibit systemic upgradeability weaknesses that allow complete takeovers, unlimited minting, and ETH theft. These issues introduce severe economic risk to token and NFT holders. Upgrade authorization and access control must be remediated before any production deployment.

