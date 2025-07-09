# 🔐 Halborn CTF – Smart Contract Security Audit Summary

This document summarizes the vulnerabilities exploited through unit testing of the HalbornCTF contracts.

---

## 📄 HalbornToken.sol

### 🛠️ Exploit 1: Unrestricted Minting (`mintToken`)

- **Test:** `test_unlimitedMint()`
- **Issue:** The `mintToken(address, uint256)` function can be called by any address previously set via `setLoans()`, without validation.
- **Exploit:** A malicious contract registers itself and mints tokens arbitrarily.
- **Impact:** Infinite token supply, economic breakdown.
- **Severity:** 🔴 Critical

### 🛠️ Exploit 2: Unrestricted Burning (`burnToken`)

- **Test:** `test_unlimitedBurn()`
- **Issue:** `burnToken` can be used to destroy tokens from any address.
- **Exploit:** A fake loan contract burns a user's tokens without permission.
- **Impact:** Token holder funds loss.
- **Severity:** 🔴 Critical

### 🛠️ Exploit 3: UUPS Upgrade Bypass

- **Test:** `test_vulnerableUUPSupgrade()`
- **Issue:** `_authorizeUpgrade(address)` is empty.
- **Exploit:** Any address can call `upgradeTo(...)` and take over the contract.
- **Impact:** Full contract compromise.
- **Severity:** 🔴 Critical

---

## 📄 HalbornLoans.sol

### 🛠️ Exploit 1: UUPS Upgrade Bypass

- **Test:** `test_vulnerableUUPSupgrade()`
- **Same as above.**
- **Severity:** 🔴 Critical

### 🛠️ Exploit 2: Arbitrary Minting via Loan Logic

- **Test:** `test_vulnerableLoanContractReksTokenMint()`
- **Issue:** Loan logic allows minting through weak integration with the token.
- **Exploit:** Attacker takes a loan without proper collateral or restriction.
- **Impact:** Token inflation.
- **Severity:** 🔴 High

### 🛠️ Exploit 3: Arbitrary Burning via Loan Logic

- **Test:** `test_vulnerableLoanContractReksTokenBurn()`
- **Issue:** Similar to minting; token burning is abusable.
- **Impact:** User fund destruction.
- **Severity:** 🔴 High

### 🛠️ Exploit 4: Reentrancy in Loan Logic

- **Test:** `test_Reentrancy()`
- **Issue:** No reentrancy guard in external calls (e.g., NFT transfer).
- **Impact:** Reentrant loan manipulation.
- **Severity:** 🟠 Medium

---

## 📄 HalbornNFT.sol

### 🛠️ Exploit 1: UUPS Upgrade Bypass

- **Test:** `test_vulnerableUUPSupgrade()`
- **Issue:** Empty `_authorizeUpgrade`, no access control.
- **Impact:** Full control over NFT logic.
- **Severity:** 🔴 Critical

### 🛠️ Exploit 2: Unlimited Whitelist Minting

- **Test:** `test_setMintUnlimited()`
- **Issue:** Whitelisted users can mint multiple times using different token IDs.
- **Impact:** NFT over-inflation.
- **Severity:** 🟠 Medium

### 🛠️ Exploit 3: Draining ETH

- **Test:** `test_stealETH()`
- **Issue:** `withdrawETH()` lacks proper withdrawal protections.
- **Impact:** Any owner can drain ETH, even if it wasn’t meant to be claimable.
- **Severity:** 🟡 Low/Medium

### 🛠️ Exploit 4: Overflow on Token Counter

- **Test:** `test_overflowCounter()`
- **Issue:** Counter increment in `mintBuyWithETH()` has no overflow check.
- **Impact:** Potential for unexpected ID reuse in edge-case block gas settings.
- **Severity:** 🟡 Low

---

## ✅ Overall Observations

- UUPS vulnerabilities affect every contract.
- Token mint/burn control must not be externally assigned without proper validation.
- Reentrancy and withdrawal logic should follow best practices.
- Whitelist minting must include per-address + per-ID limitations.

---

**Status:** All issues demonstrated successfully via unit tests using Foundry.
