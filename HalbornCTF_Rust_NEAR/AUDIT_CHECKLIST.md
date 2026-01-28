# NEAR CTF Comprehensive Function-by-Function Audit

## MalbornClubContract (halborn-near-ctf/src/lib.rs)

### 1. `new()` - #[init]
- **Intended:** Initialize contract with owner and total supply
- **Access:** Initializer only
- **Invariant:** State doesn't exist, owner gets all tokens
- **Status:** ✅ SAFE

### 2. `mint_tokens()` - pub fn
- **Intended:** Mint tokens to account, increase total_supply
- **Access:** only_owner, not_paused
- **Invariant:** total_supply increases, account balance increases
- **BUG:** If account not registered, total_supply increases but balance doesn't
- **Status:** 🔴 CRITICAL (N-02) - Token loss

### 3. `burn_tokens()` - pub fn
- **Intended:** Burn tokens from account
- **Access:** only_owner, not_paused
- **Invariant:** total_supply decreases, account balance decreases
- **Status:** ✅ SAFE (uses burn_tokens_internal which validates)

### 4. `register_for_event()` - pub fn
- **Intended:** Burn tokens and register for event
- **Access:** not_paused, not_banned
- **Invariant:** User burns tokens, event registration succeeds
- **Status:** ✅ SAFE (validates associated contract exists)

### 5. `upgrade_token_name_symbol()` - pub fn
- **Intended:** Update token metadata name/symbol
- **Access:** only_owner
- **Invariant:** Metadata updated, contract continues working
- **Status:** ✅ SAFE (properly uses take/replace pattern)

### 6. `add_to_blocklist()` - pub fn
- **Intended:** Add account to blocklist
- **Access:** only_owner, not_paused
- **Invariant:** Account marked as Banned
- **Status:** ✅ SAFE

### 7. `remove_from_blocklist()` - pub fn
- **Intended:** Remove account from blocklist
- **Access:** only_owner, not_paused
- **Invariant:** Account marked as Allowed
- **Status:** ✅ SAFE

### 8. `pause()` - pub fn
- **Intended:** Pause contract
- **Access:** only_owner
- **Invariant:** Status set to Paused
- **Status:** ✅ SAFE

### 9. `resume()` - pub fn
- **Intended:** Resume contract
- **Access:** only_owner
- **Invariant:** Status set to Working
- **BUG:** Sets status to Paused instead of Working
- **Status:** 🔴 CRITICAL (N-01) - Permanent DoS

### 10. `set_owner()` - pub fn
- **Intended:** Change contract owner
- **Access:** only_owner
- **Invariant:** owner_id updated
- **Status:** ✅ SAFE

### 11. `set_registration_fee_denominator()` - pub fn
- **Intended:** Update registration fee
- **Access:** only_owner
- **Invariant:** registration_fee_denominator updated
- **Status:** ✅ SAFE

### 12. `set_associated_contract()` - pub fn
- **Intended:** Set associated contract address
- **Access:** only_owner
- **Invariant:** associated_contract_account_id updated
- **Status:** ✅ SAFE

### 13. `get_symbol()` - pub fn
- **Intended:** Get token symbol (read-only)
- **Access:** not_paused
- **Invariant:** Returns symbol, metadata remains available
- **BUG:** Uses take() which consumes metadata
- **Status:** 🔴 CRITICAL (N-03) - Metadata consumption

### 14. `get_name()` - pub fn
- **Intended:** Get token name (read-only)
- **Access:** not_paused
- **Invariant:** Returns name, metadata remains available
- **BUG:** Uses take() which consumes metadata
- **Status:** 🔴 CRITICAL (N-03) - Metadata consumption

### 15. `get_decimals()` - pub fn
- **Intended:** Get token decimals (read-only)
- **Access:** not_paused
- **Invariant:** Returns decimals, metadata remains available
- **BUG:** Uses take() which consumes metadata
- **Status:** 🔴 CRITICAL (N-03) - Metadata consumption

### 16. `contract_status()` - pub fn
- **Intended:** Get contract status (view)
- **Access:** Public
- **Invariant:** Returns current status
- **Status:** ✅ SAFE

### 17. `get_blocklist_status()` - pub fn
- **Intended:** Get blocklist status for account
- **Access:** not_paused
- **Invariant:** Returns Allowed or Banned
- **Status:** ✅ SAFE

### 18. `ft_transfer()` - #[payable]
- **Intended:** Transfer tokens
- **Access:** not_paused, not_banned
- **Invariant:** Sender balance decreases, receiver balance increases
- **Status:** ✅ SAFE (uses standard FungibleToken)

### 19. `ft_transfer_call()` - #[payable]
- **Intended:** Transfer tokens with callback
- **Access:** not_paused, not_banned
- **Invariant:** Transfer succeeds, callback executed
- **Status:** ✅ SAFE

### 20. `ft_total_supply()` - pub fn
- **Intended:** Get total supply
- **Access:** not_paused
- **Invariant:** Returns total_supply
- **Status:** ✅ SAFE

### 21. `ft_balance_of()` - pub fn
- **Intended:** Get account balance
- **Access:** not_paused
- **Invariant:** Returns account balance
- **Status:** ✅ SAFE

### 22. `ft_resolve_transfer()` - #[private]
- **Intended:** Resolve transfer callback
- **Access:** Private (only contract can call)
- **Invariant:** Handles transfer resolution
- **Status:** ✅ SAFE

### 23. `ft_metadata()` - pub fn
- **Intended:** Get token metadata (standard interface)
- **Access:** Public view
- **Invariant:** Returns metadata
- **BUG:** Will fail after metadata consumed by get_symbol/get_name/get_decimals
- **Status:** 🔴 CRITICAL (N-03) - Breaks standard interface

### 24-28. StorageManagement functions
- **Status:** ✅ SAFE (delegates to FungibleToken)

## StakingContract (halborn-near-ctf-staking/src/lib.rs)

### 1. `new()` - #[init]
- **Intended:** Initialize staking contract
- **Access:** Initializer only
- **Invariant:** Owner set, balances empty
- **Status:** ✅ SAFE

### 2. `stake()` - #[payable]
- **Intended:** Stake NEAR tokens
- **Access:** Public
- **Invariant:** User balance increases, total_staked increases
- **Status:** ✅ SAFE (uses saturating_add which is safe)

### 3. `unstake()` - pub fn
- **Intended:** Unstake NEAR tokens
- **Access:** Public
- **Invariant:** User balance decreases, total_staked decreases, refund sent
- **BUG:** Uses saturating_sub without validation, total_staked can become incorrect
- **Status:** 🔴 CRITICAL (N-05) - Accounting inconsistency

### 4. `airdrop()` - pub fn
- **Intended:** Airdrop tokens to all stakers
- **Access:** owner only (checked via assert)
- **Invariant:** All stakers receive amount
- **Status:** ✅ SAFE

### 5-8. View functions
- **Status:** ✅ SAFE

## AssociatedContract (halborn-near-ctf-associated-contract/src/lib.rs)

### 1. `new()` - #[init]
- **Intended:** Initialize associated contract
- **Access:** Initializer only
- **Invariant:** Owner set, empty state
- **Status:** ✅ SAFE

### 2. `get_next_event_idx()` - pub fn
- **Intended:** Get next event index
- **Access:** Public view
- **Invariant:** Returns next_event_idx
- **Status:** ✅ SAFE

### 3. `get_event()` - pub fn
- **Intended:** Get event by ID
- **Access:** Public view
- **Invariant:** Returns event
- **Status:** ✅ SAFE

### 4. `add_new_event()` - pub fn
- **Intended:** Create new event
- **Access:** Public (anyone can add)
- **Invariant:** Event created, next_event_idx incremented
- **Status:** ✅ SAFE (by design - anyone can add events)

### 5. `remove_event()` - pub fn
- **Intended:** Remove event
- **Access:** only_owner
- **Invariant:** Event removed from storage
- **Status:** ✅ SAFE

### 6. `make_event_offline()` - pub fn
- **Intended:** Mark event as offline
- **Access:** only_owner
- **Invariant:** Event.is_live set to false
- **BUG:** Modifies local copy, doesn't persist to storage
- **Status:** 🔴 CRITICAL (N-04) - No effect

### 7. `add_privileged_club()` - pub fn
- **Intended:** Add privileged club
- **Access:** only_owner
- **Invariant:** Club added to privileged_clubs
- **Status:** ✅ SAFE

### 8. `remove_privileged_club()` - pub fn
- **Intended:** Remove privileged club
- **Access:** only_owner
- **Invariant:** Club removed from privileged_clubs
- **Status:** ✅ SAFE

### 9. `register_for_an_event()` - pub fn
- **Intended:** Register user for event
- **Access:** only_from_privileged_club
- **Invariant:** User added to event registrations
- **Status:** ✅ SAFE (checks event exists and is live)

### 10. `check_user_registered()` - pub fn
- **Intended:** Check if user registered
- **Access:** Public view
- **Invariant:** Returns registration status
- **Status:** ✅ SAFE

### 11. `set_owner()` - pub fn
- **Intended:** Change owner
- **Access:** only_owner
- **Invariant:** owner_id updated
- **Status:** ✅ SAFE

### 12. `pause()` - pub fn
- **Intended:** Pause contract
- **Access:** only_owner
- **Invariant:** Status set to Paused
- **Status:** ✅ SAFE

### 13. `resume()` - pub fn
- **Intended:** Resume contract
- **Access:** only_owner
- **Invariant:** Status set to Working
- **Status:** ✅ SAFE (correctly sets to Working)

## Summary

**Total Functions Audited:** 41
**Critical Issues Found:** 5 unique vulnerabilities
**All Critical Issues Have PoC Tests:** ✅ YES

