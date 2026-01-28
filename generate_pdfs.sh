#!/bin/bash

# Generate PDFs for all CTF audit reports

echo "Generating PDFs for all audit reports..."

# Ethereum
echo "Generating Ethereum PDF..."
cd HalbornCTF_Solidity_Ethereum
npx --yes md-to-pdf Findings.md
cd ..

# NEAR
echo "Generating NEAR PDF..."
cd HalbornCTF_Rust_NEAR
npx --yes md-to-pdf Findings.md
cd ..

# Substrate
echo "Generating Substrate PDF..."
cd HalbornCTF_Rust_Substrate
npx --yes md-to-pdf Findings.md
cd ..

echo "Done! PDFs generated:"
echo "  - HalbornCTF_Solidity_Ethereum/Findings.pdf"
echo "  - HalbornCTF_Rust_NEAR/Findings.pdf"
echo "  - HalbornCTF_Rust_Substrate/Findings.pdf"

