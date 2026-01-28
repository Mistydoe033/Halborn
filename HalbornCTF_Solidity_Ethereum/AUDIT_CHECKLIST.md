# Comprehensive Function-by-Function Audit Checklist

## HalbornToken.sol

### 1. `initialize()` - external initializer
- **Intended behavior:** Initialize token name, symbol, and base contracts
- **Access control:** Protected by `initializer` modifier
- **Vulnerabilities:** None - correctly protected
- **Status:** ✅ SAFE

### 2. `setLoans(address)` - external onlyOwner
- **Intended behavior:** Set the authorized loans contract address
- **Access control:** `onlyOwner` modifier
- **Vulnerabilities:** After upgrade, attacker becomes owner and can manipulate
- **Status:** ⚠️ VULNERABLE AFTER UPGRADE (H-02)

### 3. `mintToken(address, uint256)` - external onlyLoans
- **Intended behavior:** Mint tokens to account, only callable by loans contract
- **Access control:** `onlyLoans` modifier
- **Vulnerabilities:** No amount validation, unlimited minting possible
- **Status:** ⚠️ VULNERABLE (H-03)

### 4. `burnToken(address, uint256)` - external onlyLoans
- **Intended behavior:** Burn tokens from account, only callable by loans contract
- **Access control:** `onlyLoans` modifier
- **Vulnerabilities:** Can burn from any address, no authorization check
- **Status:** ⚠️ VULNERABLE (H-04)

### 5. `_authorizeUpgrade(address)` - internal override
- **Intended behavior:** Authorize upgrade to new implementation
- **Access control:** EMPTY - no checks!
- **Vulnerabilities:** Anyone can upgrade
- **Status:** 🔴 CRITICAL (H-01)

## HalbornLoans.sol

### 1. `initialize(address, address)` - public initializer
- **Intended behavior:** Initialize loans contract with token and NFT addresses
- **Access control:** Protected by `initializer` modifier
- **Vulnerabilities:** None - correctly protected
- **Status:** ✅ SAFE

### 2. `depositNFTCollateral(uint256)` - external
- **Intended behavior:** Deposit NFT as collateral, increase totalCollateral
- **Access control:** Checks NFT ownership
- **Vulnerabilities:** None found
- **Status:** ✅ SAFE

### 3. `withdrawCollateral(uint256)` - external
- **Intended behavior:** Withdraw NFT collateral, decrease totalCollateral
- **Access control:** Checks collateral availability and ownership
- **Vulnerabilities:** External call (NFT transfer) before state update - REENTRANCY
- **Status:** 🔴 CRITICAL (H-08)

### 4. `getLoan(uint256)` - external
- **Intended behavior:** Get loan tokens backed by collateral
- **Access control:** Should check available collateral >= amount
- **Vulnerabilities:** Line 60: Uses `<` instead of `>=` - INVERTED LOGIC
- **Status:** 🔴 CRITICAL (H-16)

### 5. `returnLoan(uint256)` - external
- **Intended behavior:** Return loan tokens, decrease usedCollateral
- **Access control:** Checks usedCollateral >= amount
- **Vulnerabilities:** Line 70: Uses `+=` instead of `-=` - WRONG OPERATOR
- **Status:** 🔴 CRITICAL (H-17)

### 6. `_authorizeUpgrade(address)` - internal override
- **Intended behavior:** Authorize upgrade to new implementation
- **Access control:** EMPTY - no checks!
- **Vulnerabilities:** Anyone can upgrade
- **Status:** 🔴 CRITICAL (H-05)

### 7. `onERC721Received(...)` - external pure
- **Intended behavior:** Handle NFT transfers to contract
- **Access control:** Returns selector correctly
- **Vulnerabilities:** Comment says "BUG" but implementation is correct
- **Status:** ✅ SAFE (comment is misleading)

## HalbornNFT.sol

### 1. `initialize(bytes32, uint256)` - external initializer
- **Intended behavior:** Initialize NFT contract with merkle root and price
- **Access control:** Protected by `initializer` modifier
- **Vulnerabilities:** None - correctly protected
- **Status:** ✅ SAFE

### 2. `setPrice(uint256)` - public onlyOwner
- **Intended behavior:** Set NFT mint price
- **Access control:** `onlyOwner` modifier
- **Vulnerabilities:** After upgrade, attacker becomes owner
- **Status:** ⚠️ VULNERABLE AFTER UPGRADE (H-12)

### 3. `setMerkleRoot(bytes32)` - public
- **Intended behavior:** Set merkle root for airdrop whitelist
- **Access control:** NONE - anyone can call!
- **Vulnerabilities:** Complete whitelist bypass
- **Status:** 🔴 CRITICAL (H-09)

### 4. `mintAirdrops(uint256, bytes32[])` - external
- **Intended behavior:** Mint NFT via airdrop with merkle proof
- **Access control:** Checks token doesn't exist, verifies merkle proof
- **Vulnerabilities:** None - logic is correct (mentor's claim was wrong)
- **Status:** ✅ SAFE (but vulnerable if root is manipulated via H-09)

### 5. `mintBuyWithETH()` - external payable
- **Intended behavior:** Mint NFT by paying ETH
- **Access control:** Checks msg.value == price
- **Vulnerabilities:** When called via multicall, msg.value is reused
- **Status:** 🔴 CRITICAL (H-15)

### 6. `withdrawETH(uint256)` - external onlyOwner
- **Intended behavior:** Withdraw ETH from contract
- **Access control:** `onlyOwner` modifier
- **Vulnerabilities:** After upgrade, attacker becomes owner
- **Status:** ⚠️ VULNERABLE AFTER UPGRADE (H-13)

### 7. `_authorizeUpgrade(address)` - internal override
- **Intended behavior:** Authorize upgrade to new implementation
- **Access control:** EMPTY - no checks!
- **Vulnerabilities:** Anyone can upgrade
- **Status:** 🔴 CRITICAL (H-11)

## Multicall.sol

### 1. `multicall(bytes[])` - external payable
- **Intended behavior:** Execute multiple calls in sequence
- **Access control:** None needed (delegatecall to self)
- **Vulnerabilities:** msg.value persists across delegatecalls, enabling reuse
- **Status:** 🔴 CRITICAL (H-15)

## Summary

**Total Functions Audited:** 18
**Critical Issues Found:** 8 unique vulnerabilities
**High Issues Found:** 0
**Medium Issues Found:** 0
**Low Issues Found:** 1 (idCounter overflow - H-14)

**All Critical Issues Have PoC Tests:** ✅ YES

