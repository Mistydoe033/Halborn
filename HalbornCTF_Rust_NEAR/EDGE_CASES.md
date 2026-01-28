# Edge Cases and Logic Flaws Analysis

## Critical Edge Cases Found

### 1. Division by Zero in register_for_event()
**Location:** halborn-near-ctf/src/lib.rs:147-148
**Issue:** If `registration_fee_denominator` is set to 0, division by zero will panic
**Code:**
```rust
let burn_amount = u128::from(self.malborn_token.total_supply)
    / u128::from(self.registration_fee_denominator);
```
**Impact:** Owner can set denominator to 0 via `set_registration_fee_denominator()`, causing all event registrations to fail
**Severity:** Critical - DoS vulnerability

### 2. next_event_idx Overflow
**Location:** halborn-near-ctf-associated-contract/src/lib.rs:96
**Issue:** `next_event_idx` is `u16`, will wrap around at 65535, causing event ID collisions
**Code:**
```rust
self.next_event_idx += 1;
```
**Impact:** After 65535 events, new events will reuse IDs, potentially overwriting old events
**Severity:** Medium - Requires 65535 events to trigger, but could cause data loss

### 3. Double Event Lookup in register_for_an_event()
**Location:** halborn-near-ctf-associated-contract/src/lib.rs:126-128
**Issue:** Event is looked up twice - once for contains_key check, once for is_live check
**Code:**
```rust
assert!(self.events.contains_key(&event_id), "No event with such ID");
assert!(
    self.events.get(&event_id).unwrap().is_live,
    "Event is no longer live"
);
```
**Impact:** Inefficient but not exploitable. However, theoretically event could be removed between checks (unlikely in practice)
**Severity:** Low - Performance issue, not a security bug

### 4. Zero Deposit in stake()
**Location:** halborn-near-ctf-staking/src/lib.rs:28-46
**Issue:** Users can call stake() with 0 deposit, adding 0 to their balance
**Impact:** Wastes gas but no security issue
**Severity:** Informational

### 5. Airdrop Gas Limit
**Location:** halborn-near-ctf-staking/src/lib.rs:72-78
**Issue:** If there are many stakers, airdrop() could exceed gas limits
**Impact:** Airdrop could fail for large staker sets
**Severity:** Medium - Scalability issue

### 6. Zero burn_amount in register_for_event()
**Location:** halborn-near-ctf/src/lib.rs:147-149
**Issue:** If total_supply < registration_fee_denominator, burn_amount = 0
**Impact:** Users can register for events without burning tokens
**Severity:** Medium - Economic bypass

