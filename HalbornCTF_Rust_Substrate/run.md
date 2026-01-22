# Running the Tests

## Prerequisites

This project uses Substrate 3.0.0 which requires Rust 1.68.0. A `rust-toolchain` file is included to automatically use the correct version.

## Installation

If you encounter compilation errors with newer Rust versions, install Rust 1.68.0:

```bash
cd HalbornCTF_Rust_Substrate
rustup toolchain install 1.68.0
```

## Running Tests

To run all vulnerability tests for both pallets:

```bash
cargo test --package pallet-pause --package pallet-allocations --lib
```

To run tests for individual pallets:

```bash
# Test Pause Pallet only
cargo test --package pallet-pause --lib

# Test Allocations Pallet only
cargo test --package pallet-allocations --lib
```

The `rust-toolchain` file will automatically ensure Rust 1.68.0 is used when working in this directory. Once Rust 1.68.0 is installed, all tests should compile and run successfully.

