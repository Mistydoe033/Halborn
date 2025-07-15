# 🔐 Halborn CTF – Smart Contract Security Audit Summary

This document summarizes the vulnerabilities exploited through unit testing of the HalbornCTF contracts.

---

## 📄 HalbornToken.sol

### 🛠️ Exploit 1: UUPS Upgrade Bypass

- **Test:** `test_vulnerableUUPSupgrade()`

- **Issue:**  
  The `_authorizeUpgrade(address)` function is left empty, meaning it lacks any access control.  
  As a result, **any address can invoke `upgradeTo(...)`**, enabling arbitrary contract upgrades.

- **Exploit:**  
  An attacker calls `upgradeTo(...)` with a malicious implementation.  
  This allows them to install new logic, seize control of the contract, reinitialize storage, and potentially lock out the original owner.

- **Impact:**

  - Full contract compromise.
  - Storage manipulation, ownership takeover, and logic hijacking.
  - Potential loss of funds and administrative control.

- **Severity:** 🔴 Critical

- **Remediation:**
  - Restrict `_authorizeUpgrade(address)` by applying `onlyOwner` or a custom role-based access modifier (e.g., `onlyAdmin`).
  - Ensure upgrade authorization is limited strictly to trusted parties.
  - Consider integrating a multi-signature wallet or timelock for upgrade governance in production deployments.

### 🛠️ Exploit 2: Loans Address Manipulation via Malicious Upgrade

- **Test:** `test_setLoansAddress()`
- **Issue:**  
  Although `setLoans(address)` is protected by `onlyOwner`, the `_authorizeUpgrade(address)` function lacks access control.  
  This allows any address to call `upgradeTo(...)` and install a malicious implementation.

- **Exploit:**  
  The attacker deploys a malicious contract implementation containing their own `initialize()` function.  
  They use `upgradeTo(...)` to replace the original contract, and then reinitialize ownership to themselves.  
  As the new `owner`, they call `setLoans()` and assign a malicious loan contract that they control.  
  This contract can now mint or burn tokens arbitrarily.

- **Impact:**

  - Attacker becomes the contract owner.
  - Gains control of the `halbornLoans` address.
  - Can mint unlimited tokens or burn tokens from any account.
  - Original owner loses all administrative privileges permanently.

- **Severity:** 🔴 Critical

- **Remediation:**
  - Restrict `_authorizeUpgrade(address)` using `onlyOwner` or a custom role modifier to prevent unauthorized upgrades.
  - Use OpenZeppelin’s `initializer` and `reinitializer` modifiers properly to block reinitialization in new implementations.
  - Optionally, introduce a version control or upgrade guard mechanism to ensure only trusted upgrades are allowed.

### 🛠️ Exploit 3: Unrestricted Minting via Malicious Loan Contract

- **Test:** `test_unlimitedMint()`

- **Issue:**  
  The `mintToken(address, uint256)` function is restricted to calls from `halbornLoans`, enforced by the `onlyLoans` modifier.  
  However, due to the lack of access control in `_authorizeUpgrade`, an attacker can upgrade the contract and become `owner`, then call `setLoans(...)` to assign a malicious contract as the loan authority.

- **Exploit:**  
  After taking over the contract via a malicious upgrade and reinitialization, the attacker calls `setLoans(...)` and sets their own contract as `halbornLoans`.  
  From this contract, they can call `mintToken(...)` repeatedly to create an infinite supply of tokens and drain value from the system.

- **Impact:**

  - Infinite token minting.
  - Complete loss of economic integrity.
  - Unrecoverable inflation and potential collapse of token trust.

- **Severity:** 🔴 Critical

- **Remediation:**
  - As with previous exploits, secure `_authorizeUpgrade(address)` with `onlyOwner` to prevent unauthorized upgrades.
  - Harden `setLoans(address)` access and consider restricting it to a one-time initialization or multisig-controlled update.
  - Add validation or a whitelist for trusted loan contracts before allowing minting authority.

### 🛠️ Exploit 4: Unrestricted Burning via Malicious Loan Contract

- **Test:** `test_unlimitedBurn()`

- **Issue:**  
  Similar to `mintToken`, the `burnToken(address, uint256)` function is callable by the address stored in `halbornLoans`.  
  While this is controlled via `onlyLoans`, a malicious actor who takes over the contract through `upgradeTo(...)` can set a fake loan contract and misuse this functionality.

- **Exploit:**  
  The attacker exploits the unprotected `_authorizeUpgrade` to deploy a malicious version of the contract and reassigns themselves as `owner`.  
  They then use `setLoans(...)` to assign a malicious contract that can call `burnToken(...)` to burn tokens from **any user address**, without consent or approval.

- **Impact:**

  - Arbitrary destruction of user funds.
  - Undermines token trust and user safety.
  - Potential for targeted attacks on individual holders or mass token supply reduction.

- **Severity:** 🔴 Critical

- **Remediation:**
  - Secure upgrade paths using proper access control in `_authorizeUpgrade(address)`.
  - Ensure that `burnToken(...)` can only burn tokens from `msg.sender`, or require explicit approval from the account being burned.
  - Reconsider exposing such powerful functions through a single `loans` address without robust trust assumptions and verification.

---

## 📄 HalbornLoans.sol

### 🛠️ Exploit 1: UUPS Upgrade Bypass

- **Test:** `test_vulnerableUUPSupgrade()`

- **Issue:**  
  The `_authorizeUpgrade(address)` function is left completely unprotected, allowing any address to call `upgradeTo(...)` and take control of the contract.

- **Exploit:**  
  An attacker deploys a malicious upgrade implementation, reinitializes the contract, and hijacks core loan logic — enabling arbitrary token operations and unauthorized access to loan and collateral systems.

- **Impact:**

  - Full contract compromise.
  - Arbitrary logic injection.
  - Potential theft or manipulation of collateral and token supply.

- **Severity:** 🔴 Critical

- **Remediation:**
  - Protect `_authorizeUpgrade(address)` using `onlyOwner` or a role-based modifier.
  - Use multisig or timelocks for safer production upgrade governance.
  - Ensure initializers are properly locked using OpenZeppelin's `initializer` and `reinitializer`.

---

### 🛠️ Exploit 2: Infinite Token Minting via Malicious Loan Contract

- **Test:** `test_vulnerableLoanContractReksTokenMint()`

- **Issue:**  
  The `HalbornToken` contract trusts the `HalbornLoans` contract to call `mintToken(...)`.  
  If `HalbornLoans` is compromised via an upgrade, the attacker can mint tokens freely.

- **Exploit:**  
  After exploiting the unprotected `_authorizeUpgrade`, the attacker upgrades the contract and uses their control to call `mintToken(...)`, minting unlimited tokens to themselves.

- **Impact:**

  - Infinite token inflation.
  - Economic collapse of the token ecosystem.
  - Loss of trust in the system’s integrity.

- **Severity:** 🔴 Critical

- **Remediation:**
  - Secure the upgrade path.
  - Token contracts should validate or whitelist trusted minters.
  - Consider revoking mint authority during runtime if not required long-term.

---

### 🛠️ Exploit 3: Arbitrary Token Burning via Loan Contract

- **Test:** `test_vulnerableLoanContractReksTokenBurn()`

- **Issue:**  
  The token contract allows the `HalbornLoans` contract to call `burnToken(...)` on **any user’s address**, with no ownership or approval check.  
  If `HalbornLoans` is compromised, this becomes a powerful griefing tool.

- **Exploit:**  
  An attacker upgrades the loan contract, takes control, and calls `burnToken(alice, amount)` to arbitrarily destroy another user's funds.

- **Impact:**

  - Permanent user fund loss.
  - Trust erosion and risk of targeted attacks.
  - No recourse for affected users.

- **Severity:** 🔴 Critical

- **Remediation:**
  - Lock upgrade access with `onlyOwner`.
  - Update `burnToken()` logic to enforce ownership or explicit approval.
  - Avoid allowing any external contract to have destructive authority unchecked.

---

### 🛠️ Exploit 4: Reentrancy in NFT Collateral Withdrawal

- **Test:** `test_Reentrancy()`

- **Issue:**  
  The `withdrawCollateral()` function makes an external call to transfer the NFT **before** internal state is updated, and lacks a `nonReentrant` modifier.  
  This opens the door to a reentrancy attack via the ERC721 `onERC721Received()` callback.

- **Exploit:**  
  An attacker deposits an NFT, then calls `withdrawCollateral()`.  
  During `safeTransferFrom(...)`, the attacker’s contract re-enters `withdrawCollateral()` via the callback **before the original function updates `totalCollateral`** — allowing multiple withdrawals.

- **Impact:**

  - Multiple unauthorized NFT withdrawals.
  - Full draining of the collateral vault.
  - State corruption and loss of internal consistency.

- **Severity:** 🔴 Critical

- **Remediation:**
  - Add `nonReentrant` to `withdrawCollateral()`.
  - Follow the Checks-Effects-Interactions pattern to update state before external calls.
  - Optionally queue withdrawals to be claimed in a separate, pull-based transaction.

---

### 🧠 Real-World Analogy (Plain English)

Imagine you're at a bank that gives you loans based on how many gold bars (NFTs) you’ve deposited in a vault.

- You deposit **2 gold bars**.
- You ask to withdraw **1 gold bar**.
- The bank says “Sure,” and starts handing it over.
- **But while the handover is happening**, you sneak into the system and say “Hey, I still have 2 bars in the vault, let me get the second one too.”
- Because the system hasn’t **finished updating** your record (you still show as having 2 bars), it says “Okay.”
- Now you’ve withdrawn **both** bars.
- You then immediately say “Look, I have 2 bars — give me the **maximum loan**!”
- The bank, using the outdated record, gives you a full loan based on the now-nonexistent collateral.
- You walk away with both bars **and** the loan.

---

### 🛠️ Exploit 5: Insecure Loan Collateralization

- **Test:** Implicit in `test_Reentrancy()`

- **Issue:**  
  The `getLoan()` function checks how much collateral a user has by subtracting `usedCollateral` from `totalCollateral`.  
  However, due to the reentrancy issue in `withdrawCollateral()`, this check may be based on outdated data.

- **Exploit:**  
  During a reentrancy attack, the attacker calls `getLoan()` **before** the contract updates the internal state that reflects their recent collateral withdrawal.  
  The loan is granted based on a **false assumption** of collateral backing.

- **Impact:**

  - Loans issued without sufficient collateral.
  - Token supply drained under false collateralization assumptions.
  - Chain of debt defaults and insolvency.

- **Severity:** 🟠 Medium

- **Remediation:**
  - Prevent reentrancy to ensure `getLoan()` reflects up-to-date state.
  - Recalculate collateral exposure after every sensitive operation.
  - Optionally redesign logic to decouple collateral accounting from withdrawal and loan flow.

---

### 🧠 Real-World Analogy (Plain English)

Continuing from the previous example:

- After withdrawing both gold bars using the reentrancy trick,
- You quickly shout: “I still have 2 gold bars in the vault — give me the **maximum loan** now!”
- The bank, still believing its records are accurate (even though you now hold the gold bars in your hand), gives you the full loan.
- You walk away with both the gold bars **and** the cash — fully draining the bank.

## 📄 HalbornNFT.sol

### 🛠️ Exploit 1: Merkle Root Manipulation

- **Test:** `test_setMerkelRoot()`

- **Issue:**  
  The `setMerkleRoot()` function is missing access control.  
  This allows **any user** to overwrite the whitelist Merkle root and control who can mint via `mintAirdrops()`.

- **Exploit:**  
  An attacker calls `setMerkleRoot()` with their own Merkle tree that includes only addresses they control.  
  They can then submit valid proofs and freely mint whitelisted NFTs.

- **Impact:**

  - Whitelist bypass.
  - Unauthorized users mint NFTs intended for verified recipients.
  - Undermines fairness and integrity of the airdrop.

- **Severity:** 🔴 Critical

- **Remediation:**
  - Add `onlyOwner` to `setMerkleRoot()` to ensure only the contract admin can modify it.
  - Optionally make the root immutable post-deployment for one-time airdrops.

---

### 🛠️ Exploit 2: Unlimited Airdrop Minting

- **Test:** `test_setMintUnlimited()`

- **Issue:**  
  After the attacker overwrites the Merkle root (Exploit 1), they can repeatedly craft valid proofs for unique token IDs and mint indefinitely.

- **Exploit:**  
  The attacker generates multiple Merkle proofs for different IDs from their manipulated tree and calls `mintAirdrops(...)` for each.  
  Since the only check is `_exists(id)`, they can mint as many NFTs as desired.

- **Impact:**

  - Infinite NFT minting through airdrop.
  - Supply inflation and dilution of value.
  - Potential to destroy scarcity-based utility.

- **Severity:** 🔴 Critical

- **Remediation:**
  - Lock Merkle root with `onlyOwner`.
  - Track claim status per address (or `(address, id)` pair) to prevent repeated claims.
  - Consider time-gating or limiting airdrop windows.

---

### 🛠️ Exploit 3: UUPS Upgrade Bypass

- **Test:** `test_vulnerableUUPSupgrade()`

- **Issue:**  
  The `_authorizeUpgrade(address)` function is left empty, offering no protection on the upgrade path.  
  This allows **any address** to call `upgradeTo(...)` and deploy arbitrary logic.

- **Exploit:**  
  An attacker deploys a malicious contract and upgrades the proxy to point to it.  
  They then reinitialize the contract and gain full control over all privileged operations (e.g., pricing, withdrawal, minting).

- **Impact:**

  - Full protocol compromise.
  - NFT mint logic, ETH balance, and configuration hijacked.
  - Permanent loss of control by the original owner.

- **Severity:** 🔴 Critical

- **Remediation:**
  - Implement access control in `_authorizeUpgrade(address)` using `onlyOwner` or role-based modifiers.
  - Apply OpenZeppelin’s upgrade security best practices, including upgrade delay and multisig validation.

---

### 🛠️ Exploit 4: Price Manipulation

- **Test:** `test_setPrice()`

- **Issue:**  
  Although `setPrice()` is `onlyOwner`, an attacker who exploits the upgrade bypass can reinitialize the contract and become `owner`.

- **Exploit:**  
  After gaining ownership, the attacker calls `setPrice(1 wei)` to drastically reduce mint cost, or sets it to an invalid value to break minting logic.

- **Impact:**

  - Pricing model integrity compromised.
  - Enables free or underpriced mints.
  - Denial-of-service or abusive mint conditions.

- **Severity:** 🔴 Critical

- **Remediation:**
  - Prevent reinitialization by locking the contract after deployment (`initializer` pattern).
  - Secure `_authorizeUpgrade(address)` to avoid the root takeover.
  - Optionally enforce minimum price thresholds in `setPrice()` logic.

---

### 🛠️ Exploit 5: ETH Drainage via Malicious Upgrade

- **Test:** `test_stealETH()`

- **Issue:**  
  The `withdrawETH()` function is gated by `onlyOwner`, but upgrade exploitation allows an attacker to gain ownership.  
  Even worse, they can upgrade to a version with unrestricted withdrawal or fallback drain logic.

- **Exploit:**  
  The attacker upgrades the contract to a version where `withdrawETH()` is either permissionless or hidden in a fallback.  
  They then drain the full ETH balance of the contract.

- **Impact:**

  - Total ETH theft.
  - User loss of funds deposited for NFT purchases.
  - Project bankruptcy and ecosystem trust collapse.

- **Severity:** 🔴 Critical

- **Remediation:**
  - Secure the upgrade path via `_authorizeUpgrade(address)` with `onlyOwner`.
  - Consider integrating reentrancy protection and withdraw limits.
  - Use a multisig or DAO-controlled treasury for critical funds.

---

## ✅ Overall Observations

- UUPS vulnerabilities affect every contract.
- Token mint/burn control must not be externally assigned without proper validation.
- Reentrancy and withdrawal logic should follow best practices.
- Whitelist minting must include per-address + per-ID limitations.

---

**Status:** All exploits have been successfully demonstrated through passing unit tests using Foundry, confirming the effectiveness of each attack vector.

**Usage 1:** `forge test --match-path 'test/Halborn*.*.sol' --no-match-path 'test/Halborn.t.sol'`
**Usage 2:** `forge test -vv --match-path 'test/Halborn*.*.sol' --no-match-path 'test/Halborn.t.sol'`
