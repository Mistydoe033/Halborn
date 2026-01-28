# PDF Generation Guide

This guide explains how to convert Markdown audit reports (`Findings.md`) to PDF format for submission.

## Prerequisites

- **Node.js** (v14 or higher) - Required for `md-to-pdf`
- **WSL/Linux terminal** - Commands are run in WSL environment

To check if Node.js is installed:
```bash
node --version
```

If not installed, install Node.js from [nodejs.org](https://nodejs.org/)

## Quick Start

### Method 1: Generate All PDFs at Once (Recommended)

Run the batch script from the project root:

```bash
./generate_pdfs.sh
```

This will generate PDFs for all three CTF projects:
- `HalbornCTF_Solidity_Ethereum/Findings.pdf`
- `HalbornCTF_Rust_NEAR/Findings.pdf`
- `HalbornCTF_Rust_Substrate/Findings.pdf`

### Method 2: Generate Individual PDFs

Navigate to each project directory and run:

```bash
# Ethereum
cd HalbornCTF_Solidity_Ethereum
npx --yes md-to-pdf Findings.md

# NEAR
cd HalbornCTF_Rust_NEAR
npx --yes md-to-pdf Findings.md

# Substrate
cd HalbornCTF_Rust_Substrate
npx --yes md-to-pdf Findings.md
```

The `npx --yes` command automatically downloads and runs `md-to-pdf` without requiring global installation.

## How It Works

- **`md-to-pdf`** is a Node.js package that converts Markdown to PDF
- Uses **Puppeteer** (headless Chrome) to render the Markdown as HTML, then converts to PDF
- No LaTeX or additional dependencies required
- PDFs are generated in the same directory as the source Markdown file

## Output

Each `Findings.md` file will generate a corresponding `Findings.pdf` file in the same directory.

**Example:**
```
HalbornCTF_Solidity_Ethereum/
  ├── Findings.md
  └── Findings.pdf  ← Generated file
```

## Troubleshooting

### Issue: "command not found" or "npx: command not found"

**Solution:** Install Node.js:
```bash
# On Ubuntu/Debian
sudo apt update
sudo apt install nodejs npm

# Verify installation
node --version
npm --version
```

### Issue: PDF generation fails or hangs

**Solution:** The first run downloads Puppeteer (~200MB). Wait for it to complete. If it fails:

```bash
# Clear npm cache
npm cache clean --force

# Try again
npx --yes md-to-pdf Findings.md
```

### Issue: PDF formatting looks incorrect

**Solution:** The PDF should preserve Markdown formatting. If tables or code blocks look wrong:
1. Check the source Markdown file for proper syntax
2. Ensure code blocks use triple backticks (```)
3. Tables should use proper Markdown table syntax

### Issue: Permission denied on script

**Solution:** Make the script executable:
```bash
chmod +x generate_pdfs.sh
```

## Customization (Optional)

To customize PDF output (margins, page size, etc.), create a `md-to-pdf.config.js` file:

```javascript
module.exports = {
  pdf_options: {
    format: 'A4',
    margin: {
      top: '20mm',
      right: '20mm',
      bottom: '20mm',
      left: '20mm'
    },
    printBackground: true
  }
};
```

Place this file in the project directory before running `md-to-pdf`.

## Notes

- PDFs are optimized for printing and digital viewing
- Code blocks preserve syntax highlighting
- Tables are automatically formatted
- Page breaks occur naturally based on content
- File sizes are typically 200-300KB per report

## Verification

After generation, verify the PDF was created:

```bash
ls -lh HalbornCTF_Solidity_Ethereum/Findings.pdf
ls -lh HalbornCTF_Rust_NEAR/Findings.pdf
ls -lh HalbornCTF_Rust_Substrate/Findings.pdf
```

All three files should exist and have reasonable file sizes (typically 200KB-500KB).
