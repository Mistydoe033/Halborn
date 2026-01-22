# Solana CTF

Here, you will find the Solana CTFs. 

It is mandatory to provide a PoC (Proof of Concept) to verify that the findings are vulnerable.

## Running Tests

To run the vulnerability tests:

```bash
cd ctf_game/ctf
cargo test --test integration_test
```

Or run all tests:

```bash
cargo test --workspace
```

## Findings

See [Findings.md](./Findings.md) for detailed vulnerability descriptions and proof of concept tests.

## Vulnerability Summary

**Critical: Integer Underflow in `user_level_up` Function**

The `user_level_up` function subtracts credits from the user's balance before validating that the user has sufficient credits, causing an integer underflow when `user.credits < level_credits`.

**Location:** `ctf_game/ctf/src/processor.rs:186-190`

**Proof of Concept:** See `ctf_game/ctf/tests/integration_test.rs`

