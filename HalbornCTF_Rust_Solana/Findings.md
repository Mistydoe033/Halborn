# Halborn CTF – Solana Smart Contract Security Audit Summary

This document summarizes the vulnerabilities identified in the HalbornCTF Solana game contract.

## Vulnerability: Integer Underflow in `user_level_up` Function

### Summary
The `user_level_up` function in `processor.rs` has a critical integer underflow vulnerability. The function subtracts credits from the user's balance **before** validating that the user has sufficient credits, which can cause a panic due to integer underflow.

### Location
- **File:** `ctf_game/ctf/src/processor.rs`
- **Function:** `user_level_up` (lines 150-197)
- **Vulnerable Lines:** 186-190

### Issue Details

The vulnerable code:
```rust
user.credits -= level_credits;  // Line 186: Subtraction happens first

if !(user.credits > 0) {         // Line 188: Check happens after subtraction
    return Err(ProgramError::InsufficientFunds)
}
```

**The Problem:**
1. The function calculates `level_credits` (cumulative credits needed to reach a certain level) based on `credits_to_burn`
2. It then subtracts `level_credits` from `user.credits` **without first checking** if `user.credits >= level_credits`
3. The validation check `if !(user.credits > 0)` happens **after** the subtraction
4. If `user.credits < level_credits`, the subtraction causes an integer underflow, which will panic in Rust (Solana programs have overflow checks enabled by default)

### Exploit Scenario

**Example Attack:**
1. User is at level 0 with only 5 credits
2. `credits_per_level = 10`
3. User calls `user_level_up` with `credits_to_burn = 50`

**Calculation Flow:**
- Starting: `iterator = 0`, `level_credits = 0`, `next_level_credits = 0`
- Iteration 1: `level_credits = 0`, `iterator = 1`, `next_level_credits = 10`
- Iteration 2: `level_credits = 10`, `iterator = 2`, `next_level_credits = 30`
- Iteration 3: `level_credits = 30`, `iterator = 3`, `next_level_credits = 60`
- Loop exits (60 < 50 is false)
- **Result:** `level_credits = 30`
- **Subtraction:** `user.credits (5) -= level_credits (30)` → **UNDERFLOW!**

### Impact
- **Severity:** Critical
- **Consequences:**
  - Integer underflow causes program panic, making the transaction fail
  - However, the logic error allows users to attempt leveling up with insufficient credits
  - The function should validate sufficient credits **before** performing any state changes
  - In a production environment, this could be exploited to cause denial of service or reveal information about user balances through error messages

### Recommended Fix

The validation should happen **before** the subtraction:

```rust
// Validate sufficient credits BEFORE subtracting
if user.credits < level_credits {
    return Err(ProgramError::InsufficientFunds)
}

user.credits -= level_credits;
user.level = iterator;
```

Alternatively, use checked arithmetic:

```rust
user.credits = user.credits
    .checked_sub(level_credits)
    .ok_or(ProgramError::InsufficientFunds)?;
```

### Additional Observations

1. **Logic Issue:** The function calculates how many levels the user can advance based on `credits_to_burn`, but the calculation logic may not match the intended behavior. The cumulative credits calculation seems correct, but the validation timing is wrong.

2. **Missing Pre-validation:** The function should validate that:
   - `user.credits >= level_credits` before subtracting
   - The calculated `level_credits` is reasonable and doesn't exceed available credits

3. **Error Handling:** The current error handling happens too late - after state modification has been attempted, which violates the principle of validating inputs before processing.

## Test Cases

The following test cases demonstrate the vulnerability:

1. **Test: Integer Underflow with Insufficient Credits**
   - User has 5 credits, attempts to level up requiring 30 credits
   - Expected: Integer underflow panic

2. **Test: Validation After Subtraction**
   - User has exactly enough credits for one level
   - Attempts to level up multiple levels
   - Expected: Should fail before subtraction, but currently fails after

## Status

- **Vulnerability Identified:** ✅
- **Proof of Concept:** ✅ (See test file)
- **Severity:** Critical
- **Fix Required:** Yes

