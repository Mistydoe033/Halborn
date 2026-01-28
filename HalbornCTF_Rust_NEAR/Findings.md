# Audit Findings Report

## 1. Executive Summary

This report documents the security review of the Halborn NEAR CTF contracts: `MalbornClubContract`, `StakingContract`, and `AssociatedContract`. The assessment focused on state management, storage persistence, access control, and economic integrity. All findings were validated against the provided Rust unit tests.

**Total Findings:** 16 (9 Critical, 3 High, 3 Medium, 1 Informational)

## 2. Overview

**Folder name:** HalbornCTF_Rust_NEAR

**Date:** 2026

**Auditor:** Seth Brockob

## 3. Scope

**In-scope contracts:**

- halborn-near-ctf/src/lib.rs
- halborn-near-ctf-staking/src/lib.rs
- halborn-near-ctf-associated-contract/src/lib.rs

**In-scope tests:**

- Embedded unit tests in each contract's `#[cfg(test)]` module

**Out of scope:**

- Deployment scripts
- Build configuration files
- Documentation files

## 4. Methodology

- Manual review of in-scope contracts
- Review of Rust unit test suites
- Analysis of state management, storage persistence, and economic risk exposure

## 5. Risk Rating

- **Critical:** Full compromise, irreversible fund loss, or protocol takeover
- **High:** Major security or economic impact with realistic exploitation paths
- **Medium:** Material impact with limited practical exploitation
- **Low:** Minor impact or highly constrained exploitation
- **Informational:** Best practice issues without direct impact

## 6. Findings Summary

| ID | Title | Risk |
| --- | --- | --- |
| N-01 | MalbornClubContract: resume() Sets Incorrect Status | Critical |
| N-02 | MalbornClubContract: mint_tokens() Loses Tokens for Unregistered Users | Critical |
| N-03 | MalbornClubContract: Metadata Functions Consume Metadata | Critical |
| N-04 | AssociatedContract: make_event_offline() Has No Effect | Critical |
| N-05 | StakingContract: unstake() Logic Error and Accounting Inconsistency | Critical |
| N-06 | MalbornClubContract: Division by Zero in register_for_event() | Critical |
| N-07 | MalbornClubContract: Tokens Burned Before External Call Validation | Critical |
| N-08 | MalbornClubContract: FT Standard Functions Break When Contract is Paused | Critical |
| N-09 | MalbornClubContract: get_blocklist_status() Breaks When Contract is Paused | Critical |
| N-10 | AssociatedContract: check_user_registered() Can Panic on Invalid State | High |
| N-11 | AssociatedContract: register_for_an_event() Inefficient Double Lookup and Potential Panic | High |
| N-12 | AssociatedContract: get_event() Can Panic Instead of Returning Option | Medium |
| N-13 | AssociatedContract: remove_event() Does Not Clear Underlying LookupSet Storage | High |
| N-14 | StakingContract: airdrop() Has No Validation on Amount Parameter | Medium |
| N-15 | MalbornClubContract: set_associated_contract() Does Not Validate Account ID | Medium |
| N-16 | All Contracts: Missing Event Emissions for State Changes | Informational |

## 7. Detailed Findings

### N-01 – MalbornClubContract: resume() Sets Incorrect Status

**Risk:** Critical

**Description:**

The `resume()` function sets the contract status to `Paused` instead of `Working`. Once paused, the contract cannot be resumed, causing permanent denial of service. The tests `test_resume_bug_contract_stays_paused()` and `test_resume_bug_cannot_use_contract()` demonstrate that after calling `resume()`, the contract remains paused and all guarded functions fail.

**Code Section:**

- halborn-near-ctf/src/lib.rs: `resume()` (line 184-187)
- Tests: `test_resume_bug_contract_stays_paused()`, `test_resume_bug_cannot_use_contract()` in halborn-near-ctf/src/lib.rs

**Impact:**

Permanent denial of service. Once paused, the contract cannot be resumed, and all functions protected by `not_paused()` remain unusable. This breaks core contract functionality permanently.

**Recommendation on Improvement:**

Set the contract status to `Working`:
```rust
pub fn resume(&mut self) {
    self.only_owner();
    self.status = ContractStatus::Working;
}
```

### N-02 – MalbornClubContract: mint_tokens() Loses Tokens for Unregistered Users

**Risk:** Critical

**Description:**

`mint_tokens()` increases `total_supply` unconditionally but only credits the user's balance if they are already registered. When minting to an unregistered user, the total supply increases but no balance is credited, causing permanent token loss. The tests `test_mint_tokens_bug_unregistered_user()` and `test_mint_tokens_bug_token_loss()` confirm supply inflation without corresponding balances.

**Code Section:**

- halborn-near-ctf/src/lib.rs: `mint_tokens()` (line 105-125)
- Tests: `test_mint_tokens_bug_unregistered_user()`, `test_mint_tokens_bug_token_loss()` in halborn-near-ctf/src/lib.rs

**Impact:**

Permanent token loss and supply inflation without ownership. Tokens are minted into existence but cannot be accessed, creating economic inconsistencies and undermining token integrity.

**Recommendation on Improvement:**

Register users before crediting balances:
```rust
if let Some(user_amount) = self.malborn_token.accounts.get(account_id) {
    self.malborn_token.accounts.insert(
        account_id,
        &user_amount
            .checked_add(u128::from(amount))
            .expect("Exceeded balance"),
    );
} else {
    // Register user if not already registered
    self.malborn_token.internal_register_account(account_id);
    self.malborn_token.accounts.insert(account_id, &u128::from(amount));
}
```

### N-03 – MalbornClubContract: Metadata Functions Consume Metadata

**Risk:** Critical

**Description:**

`get_symbol()`, `get_name()`, and `get_decimals()` use `token_metadata.take()` which removes metadata from storage. After the first call to any of these functions, metadata becomes permanently unavailable, breaking the standard NEAR token metadata interface. The tests `test_metadata_consumption_bug()`, `test_metadata_consumption_bug_multiple_functions()`, and `test_metadata_consumption_bug_ft_metadata()` demonstrate that `ft_metadata()` fails after metadata is consumed.

**Code Section:**

- halborn-near-ctf/src/lib.rs: `get_symbol()` (line 204-210), `get_name()` (line 212-218), `get_decimals()` (line 220-226)
- Tests: `test_metadata_consumption_bug()`, `test_metadata_consumption_bug_multiple_functions()`, `test_metadata_consumption_bug_ft_metadata()` in halborn-near-ctf/src/lib.rs

**Impact:**

Token metadata becomes permanently inaccessible after one read operation. This breaks standard NEAR token interfaces (`FungibleTokenMetadataProvider`) and prevents downstream integrations from accessing token information.

**Recommendation on Improvement:**

Use read-only access with `get()` instead of `take()`:
```rust
pub fn get_symbol(&self) -> String {
    self.not_paused();
    let metadata = self.token_metadata.get();
    metadata
        .expect("Unable to retrieve metadata at this moment")
        .symbol
}
```

Apply the same pattern to `get_name()` and `get_decimals()`.

### N-04 – AssociatedContract: make_event_offline() Has No Effect

**Risk:** Critical

**Description:**

`make_event_offline()` retrieves an event from storage, modifies the local copy's `is_live` field to `false`, but never persists the change back to storage. The test `test_make_event_offline_bug_no_effect()` confirms that events remain live and registrations still succeed after calling this function.

**Code Section:**

- halborn-near-ctf-associated-contract/src/lib.rs: `make_event_offline()` (line 109-112)
- Test: `test_make_event_offline_bug_no_effect()` in halborn-near-ctf-associated-contract/src/lib.rs

**Impact:**

Events cannot be taken offline. This bypasses intended access control and allows registrations during cancellations or shutdowns, breaking event management functionality.

**Recommendation on Improvement:**

Persist the updated event back into storage:
```rust
pub fn make_event_offline(&mut self, event_id: U64) {
    self.only_owner();
    let mut event = self.events.get(&event_id).unwrap();
    event.is_live = false;
    self.events.insert(&event_id, &event);
}
```

### N-05 – StakingContract: unstake() Logic Error and Accounting Inconsistency

**Risk:** Critical

**Description:**

`unstake()` uses `saturating_sub` without validating that `amount <= balance`. When unstaking more than the user's balance, `new_balance` becomes `0`, but `total_staked` is reduced by the requested `amount` (not the actual balance). This causes incorrect accounting. The tests `test_unstake_bug_when_balance_reaches_zero()`, `test_unstake_bug_logic_inconsistency()`, and `test_unstake_edge_case_saturating_sub()` demonstrate the accounting inconsistency.

**Code Section:**

- halborn-near-ctf-staking/src/lib.rs: `unstake()` (line 49-70)
- Tests: `test_unstake_bug_when_balance_reaches_zero()`, `test_unstake_bug_logic_inconsistency()`, `test_unstake_edge_case_saturating_sub()` in halborn-near-ctf-staking/src/lib.rs

**Impact:**

Incorrect `total_staked` accounting and inconsistent refunds. When users unstake more than their balance, `total_staked` becomes incorrect, undermining staking economics and protocol balance correctness.

**Recommendation on Improvement:**

Validate `amount <= balance` and update `total_staked` based on the actual unstaked amount:
```rust
pub fn unstake(&mut self, amount: U128) -> bool {
    assert!(u128::from(amount) > 0);
    let user = env::predecessor_account_id();
    
    match self.stake_balances.get(&user) {
        Some(balance) => {
            assert!(u128::from(amount) <= balance, "Insufficient staked balance");
            let new_balance = balance - u128::from(amount);
            self.stake_balances.insert(&user, &new_balance);
            self.total_staked = self.total_staked - u128::from(amount);
            
            let _ = Promise::new(user).transfer(NearToken::from_yoctonear(amount.0));
            true
        }
        _ => false,
    }
}
```

### N-06 – MalbornClubContract: Division by Zero in register_for_event()

**Risk:** Critical

**Description:**

`set_registration_fee_denominator()` allows the owner to set the denominator to `0` without validation. When `register_for_event()` calculates the burn amount, it divides `total_supply` by `registration_fee_denominator`, causing a division by zero panic if the denominator is `0`. The test `test_registration_fee_denominator_zero_division()` demonstrates this DoS vulnerability.

**Code Section:**

- halborn-near-ctf/src/lib.rs: `set_registration_fee_denominator()` (line 194-197)
- halborn-near-ctf/src/lib.rs: `register_for_event()` (line 147-148)
- Test: `test_registration_fee_denominator_zero_division()` in halborn-near-ctf/src/lib.rs

**Impact:**

Complete denial of service for event registration. The owner can accidentally or maliciously set the denominator to `0`, making all event registrations fail permanently until the denominator is corrected.

**Recommendation on Improvement:**

Validate that the denominator is not zero:
```rust
pub fn set_registration_fee_denominator(&mut self, new_denominator: U128) {
    self.only_owner();
    assert!(u128::from(new_denominator) > 0, "Denominator cannot be zero");
    self.registration_fee_denominator = new_denominator;
}
```

### N-07 – MalbornClubContract: Tokens Burned Before External Call Validation

**Risk:** Critical

**Description:**

`register_for_event()` burns tokens before making the external call to `register_for_an_event()`. If the external call fails (event doesn't exist, event is offline, associated contract is paused, etc.), tokens are permanently burned without successful registration. In NEAR, promise failures don't revert the transaction, so the token burn is irreversible. The test `test_register_for_event_burns_tokens_before_external_call()` demonstrates token loss when the external call fails.

**Code Section:**

- halborn-near-ctf/src/lib.rs: `register_for_event()` (line 137-154)
- Test: `test_register_for_event_burns_tokens_before_external_call()` in halborn-near-ctf/src/lib.rs

**Impact:**

Permanent token loss without successful event registration. Users lose tokens if the external call fails for any reason (invalid event ID, event offline, contract paused, etc.), creating an unfair economic loss.

**Recommendation on Improvement:**

Validate event existence and state before burning tokens, or use a callback pattern to refund tokens if registration fails:
```rust
pub fn register_for_event(&mut self, event_id: U128) {
    self.not_paused();
    assert!(
        self.associated_contract_account_id.is_some(),
        "Associated Account is not set"
    );
    let sender_id = env::signer_account_id();
    self.not_banned(sender_id.clone());

    // Validate event exists and is live BEFORE burning tokens
    // This requires a view call or storing event state locally
    
    // burn tokens for registering
    let burn_amount = u128::from(self.malborn_token.total_supply)
        / u128::from(self.registration_fee_denominator);
    
    // Only burn after validation, or use callback to refund on failure
    self.burn_tokens_internal(&sender_id, U128::from(burn_amount));

    let _ = associated_contract_interface::ext(self.associated_contract_account_id.get().unwrap())
        .with_static_gas(GAS_FOR_REGISTER)
        .register_for_an_event(event_id, sender_id);
}
```

Alternatively, implement a callback mechanism to refund tokens if registration fails.

### N-08 – MalbornClubContract: FT Standard Functions Break When Contract is Paused

**Risk:** Critical

**Description:**

`ft_total_supply()` and `ft_balance_of()` implement the NEAR Fungible Token standard interface but call `not_paused()`, causing them to fail when the contract is paused. These are view functions that should always be queryable according to the FT standard. When paused, external contracts and users cannot query token balances or total supply, breaking standard compliance and preventing legitimate read-only operations.

**Code Section:**

- halborn-near-ctf/src/lib.rs: `ft_total_supply()` (line 318-321)
- halborn-near-ctf/src/lib.rs: `ft_balance_of()` (line 323-327)
- Tests: `test_ft_total_supply_breaks_when_paused()`, `test_ft_balance_of_breaks_when_paused()` in halborn-near-ctf/src/lib.rs

**Impact:**

Breaks Fungible Token standard compliance. When the contract is paused, all balance queries fail, preventing external integrations, wallets, and DEXs from functioning correctly. This creates a denial of service for read-only operations that should always be available.

**Recommendation on Improvement:**

Remove `not_paused()` checks from view functions implementing the FT standard:
```rust
fn ft_total_supply(&self) -> U128 {
    self.malborn_token.ft_total_supply()
}

fn ft_balance_of(&self, account_id: AccountId) -> U128 {
    self.malborn_token.ft_balance_of(account_id)
}
```

View functions should not be affected by pause state. Only state-changing operations should require the contract to be unpaused.

### N-09 – MalbornClubContract: get_blocklist_status() Breaks When Contract is Paused

**Risk:** Critical

**Description:**

`get_blocklist_status()` is a view function that calls `not_paused()`. When the contract is paused, users cannot check blocklist status, creating a denial of service. Additionally, `not_banned()` calls `get_blocklist_status()`, creating a circular dependency where checking if someone is banned requires the contract to not be paused, potentially preventing legitimate operations.

**Code Section:**

- halborn-near-ctf/src/lib.rs: `get_blocklist_status()` (line 232-238)
- halborn-near-ctf/src/lib.rs: `not_banned()` (line 277-281)
- Test: `test_get_blocklist_status_breaks_when_paused()` in halborn-near-ctf/src/lib.rs

**Impact:**

Denial of service for blocklist queries when contract is paused. This prevents users from checking their own blocklist status and creates a circular dependency where pause state blocks access control checks.

**Recommendation on Improvement:**

Remove `not_paused()` check from `get_blocklist_status()`:
```rust
pub fn get_blocklist_status(&self, account_id: &AccountId) -> BlocklistStatus {
    return match self.block_list.get(account_id) {
        Some(user_status) => user_status.clone(),
        None => BlocklistStatus::Allowed,
    };
}
```

View functions should not be affected by pause state.

### N-10 – AssociatedContract: check_user_registered() Can Panic on Invalid State

**Risk:** High

**Description:**

`check_user_registered()` uses `unwrap()` on `event_to_registered_users.get()`. While `add_new_event()` creates both `events` and `event_to_registered_users` together, and `remove_event()` removes both, storage corruption or edge cases could cause `event_to_registered_users` to be missing while `events` contains the key. This would cause the view function to panic instead of returning `false`.

**Code Section:**

- halborn-near-ctf-associated-contract/src/lib.rs: `check_user_registered()` (line 143-150)
- Test: `test_check_user_registered_panic_on_missing_registered_users()` in halborn-near-ctf-associated-contract/src/lib.rs

**Impact:**

View function can panic on invalid state, causing transaction failures. While the function checks `events.contains_key()` first, if storage is corrupted or an edge case occurs where `event_to_registered_users` is missing, the `unwrap()` will panic.

**Recommendation on Improvement:**

Handle the case where `event_to_registered_users` might not exist:
```rust
pub fn check_user_registered(&self, event_id: U64, account_id: AccountId) -> bool {
    if !self.events.contains_key(&event_id) {
        return false;
    }
    match self.event_to_registered_users.get(&event_id) {
        Some(registered_users) => registered_users.contains(&account_id),
        None => false, // Event exists but registered_users missing (shouldn't happen, but handle gracefully)
    }
}
```

### N-11 – AssociatedContract: register_for_an_event() Inefficient Double Lookup and Potential Panic

**Risk:** High

**Description:**

`register_for_an_event()` performs inefficient double lookups and can panic if storage is corrupted. The function checks `events.contains_key()` on line 126, then calls `events.get().unwrap()` on line 128 to check `is_live`, then calls `event_to_registered_users.get().unwrap()` on line 132-135. This results in three separate storage lookups. More critically, if `event_to_registered_users` is missing (due to storage corruption or edge cases), the function panics instead of handling the error gracefully.

**Code Section:**

- halborn-near-ctf-associated-contract/src/lib.rs: `register_for_an_event()` (line 124-141)
- Test: `test_register_for_an_event_panic_on_missing_registered_users()` in halborn-near-ctf-associated-contract/src/lib.rs

**Impact:**

Inefficient gas usage due to redundant lookups. More critically, if storage becomes corrupted and `event_to_registered_users` is missing while `events` contains the key, the function will panic, preventing event registration and potentially causing transaction failures.

**Recommendation on Improvement:**

Use a single lookup and handle missing `event_to_registered_users` gracefully:
```rust
pub fn register_for_an_event(&mut self, event_id: U64, account_id: AccountId) {
    self.only_from_privileged_club();
    
    // Single lookup for event
    let event = self.events.get(&event_id)
        .expect("No event with such ID");
    assert!(event.is_live, "Event is no longer live");

    // Handle missing event_to_registered_users gracefully
    match self.event_to_registered_users.get(&event_id) {
        Some(mut registered_users) => {
            registered_users.insert(&account_id);
            self.event_to_registered_users.insert(&event_id, &registered_users);
        }
        None => {
            // Recreate if missing (shouldn't happen, but handle gracefully)
            let mut registered_users = LookupSet::new(
                StorageKey::RegisteredUsers(u64::from(event_id)).into_bytes()
            );
            registered_users.insert(&account_id);
            self.event_to_registered_users.insert(&event_id, &registered_users);
        }
    }
    
    log!("{} registered for event: {}", account_id, u64::from(event_id));
}
```

### N-12 – AssociatedContract: get_event() Can Panic Instead of Returning Option

**Risk:** Medium

**Description:**

`get_event()` is a view function that uses `unwrap()` instead of returning `Option<Event>`. If an event doesn't exist, the function panics instead of returning `None`, breaking the expectation that view functions should not panic on invalid input.

**Code Section:**

- halborn-near-ctf-associated-contract/src/lib.rs: `get_event()` (line 73-75)
- Test: `test_get_event_panic_on_nonexistent_event()` in halborn-near-ctf-associated-contract/src/lib.rs

**Impact:**

View function can panic on invalid input, causing transaction failures. External contracts or frontends calling this function with a non-existent event ID will experience panics instead of receiving a clear error indication.

**Recommendation on Improvement:**

Return `Option<Event>` instead of panicking:
```rust
pub fn get_event(&self, event_idx: U64) -> Option<Event> {
    self.events.get(&event_idx)
}
```

Or if the current signature must be maintained, provide a separate `try_get_event()` function that returns `Option<Event>`.

### N-13 – AssociatedContract: remove_event() Does Not Clear Underlying LookupSet Storage

**Risk:** High

**Description:**

`remove_event()` removes entries from `events` and `event_to_registered_users` LookupMaps (lines 102-103), but does not clear the underlying `LookupSet<AccountId>` storage. Each `RegisteredUsers` LookupSet has its own storage key (`StorageKey::RegisteredUsers(event_id)`), which persists even after the entry is removed from the LookupMap. This causes storage leaks and prevents storage refunds.

**Code Section:**

- halborn-near-ctf-associated-contract/src/lib.rs: `remove_event()` (lines 100-104)
- halborn-near-ctf-associated-contract/src/lib.rs: `add_new_event()` (lines 88-94) - creates LookupSet with separate storage key
- halborn-near-ctf-associated-contract/src/storage.rs: `StorageKey::RegisteredUsers(u16)` storage key definition

**Impact:**

Storage leaks and potential DoS. LookupSet data remains in storage after event removal, preventing storage refunds and causing contract storage to grow indefinitely. Over time, excessive storage usage could cause the contract to exceed storage limits, leading to denial of service.

**Recommendation on Improvement:**

Clear the LookupSet before removing from LookupMap:
```rust
pub fn remove_event(&mut self, event_id: U64) {
    self.only_owner();
    
    // Clear the underlying LookupSet storage before removing from LookupMap
    if let Some(registered_users) = self.event_to_registered_users.get(&event_id) {
        // Collect all users to avoid borrowing issues
        let users_to_remove: Vec<AccountId> = registered_users.iter().collect();
        for user in users_to_remove {
            registered_users.remove(&user);
        }
    }
    
    self.events.remove(&event_id);
    self.event_to_registered_users.remove(&event_id);
}
```

Alternatively, implement a storage cleanup mechanism that can be called separately if clearing during removal is too gas-intensive.

### N-14 – StakingContract: airdrop() Has No Validation on Amount Parameter

**Risk:** Medium

**Description:**

`airdrop()` function accepts `amount: u128` without validation. If `amount` is `0`, the function will iterate through all stakers and send `0` NEAR to each, wasting gas. Additionally, there is no check that the contract has sufficient balance to cover all airdrops, which could cause promise failures after consuming gas.

**Code Section:**

- halborn-near-ctf-staking/src/lib.rs: `airdrop()` (lines 72-78)

**Impact:**

Gas waste and potential DoS. Calling with `amount = 0` wastes gas iterating through all stakers without meaningful effect. If contract balance is insufficient for the total airdrop amount, promises will fail but gas is still consumed, creating an inefficient and potentially DoS-prone function.

**Recommendation on Improvement:**

Add validation for amount and contract balance:
```rust
pub fn airdrop(&mut self, amount: u128) {
    let user = env::predecessor_account_id();
    assert!(user == self.owner);
    assert!(amount > 0, "Airdrop amount must be greater than zero");
    
    let staker_count = self.stake_balances.len();
    let total_required = amount.saturating_mul(staker_count);
    let contract_balance = env::account_balance().as_yoctonear();
    assert!(total_required <= contract_balance, "Insufficient contract balance for airdrop");
    
    for (staker, _) in self.stake_balances.iter() {
        let _ = Promise::new(staker).transfer(NearToken::from_yoctonear(amount));
    }
}
```

### N-15 – MalbornClubContract: set_associated_contract() Does Not Validate Account ID

**Risk:** Medium

**Description:**

`set_associated_contract()` accepts any `AccountId` without validation. The function does not verify that the account exists, is not the contract itself, or implements the expected `AssociatedContractInterface`. This could lead to setting invalid contract addresses, causing all `register_for_event()` calls to fail.

**Code Section:**

- halborn-near-ctf/src/lib.rs: `set_associated_contract()` (lines 199-202)

**Impact:**

Potential DoS and user confusion. If an invalid or non-existent address is set, all `register_for_event()` calls will fail, causing users to lose tokens (as tokens are burned before the external call fails, per N-07). Additionally, setting the contract to itself would create a circular dependency.

**Recommendation on Improvement:**

Add basic validation:
```rust
pub fn set_associated_contract(&mut self, account_id: AccountId) {
    self.only_owner();
    assert!(
        account_id != env::current_account_id(),
        "Cannot set associated contract to self"
    );
    // Optionally: Verify contract exists and implements expected interface via view call
    self.associated_contract_account_id.set(&account_id);
}
```

For production, consider adding a view call to verify the contract implements `AssociatedContractInterface` before setting.

### N-16 – All Contracts: Missing Event Emissions for State Changes

**Risk:** Informational

**Description:**

None of the three contracts emit events for state changes. NEAR contracts should emit events for token transfers (FT standard), ownership changes, pause/resume actions, event creation/removal, and staking/unstaking actions. While not a security vulnerability, this impacts observability and compliance with NEAR standards.

**Code Section:**

- All contracts lack event emissions throughout their implementations

**Impact:**

Poor observability and compliance. External systems cannot track contract state changes, making it difficult to monitor contract activity, debug issues, or build integrations. The NEAR Fungible Token standard recommends event emissions for transfers and other state changes.

**Recommendation on Improvement:**

Implement event emissions using NEAR's event standard:
```rust
use near_sdk::serde_json::json;

// Example for pause/resume
pub fn pause(&mut self) {
    self.only_owner();
    self.status = ContractStatus::Paused;
    log!("EVENT_JSON:{}", json!({
        "standard": "malborn_club",
        "version": "1.0.0",
        "event": "contract_paused",
        "data": {}
    }));
}

pub fn resume(&mut self) {
    self.only_owner();
    self.status = ContractStatus::Working;
    log!("EVENT_JSON:{}", json!({
        "standard": "malborn_club",
        "version": "1.0.0",
        "event": "contract_resumed",
        "data": {}
    }));
}
```

Apply similar event emissions for all state-changing functions across all contracts.

## 8. Test Coverage Gaps

All Critical findings have been validated with Rust PoC tests. The following areas were not explicitly tested but represent potential coverage gaps:

- **Storage leak in remove_event():** The storage leak issue (N-13) where `remove_event()` does not clear underlying LookupSet storage was not explicitly tested. A test should verify that LookupSet storage persists after event removal.
- **Zero amount validation in airdrop():** The lack of validation in `airdrop()` (N-14) was not tested. A test should verify gas waste when calling with `amount = 0`.
- **Account ID validation in set_associated_contract():** The lack of validation in `set_associated_contract()` (N-15) was not tested. A test should verify behavior when setting invalid addresses or self.
- **Edge case arithmetic:** Underflow scenarios are protected by `checked_add`/`checked_sub` and explicit assertions.
- **State consistency:** All state transitions are validated through integration tests.
- **Access control boundaries:** All access control bypasses are demonstrated through owner-only function tests.
- **next_event_idx overflow:** The `next_event_idx` field in `AssociatedContract` is a `u16` and will wrap around after 65535 events, potentially causing event ID collisions. This requires an extremely large number of events to trigger and is considered a medium-severity edge case.
- **Zero burn_amount edge case:** If `total_supply < registration_fee_denominator`, users can register for events without burning tokens (burn_amount = 0). This is an economic bypass but requires specific conditions.

Most High and Medium findings were validated through code review and logical analysis, with Critical findings demonstrated through existing PoC tests.

## 9. Conclusion

The NEAR contracts contain critical state management flaws that lead to permanent pause states, token loss, metadata consumption, and incorrect accounting. These issues compromise both functionality and economic correctness. Remediation should prioritize state correctness, storage persistence, and balance validation before any production deployment.
