# Ledgerline product specification

## Source and limits

This document records requirements visible in the conversation for the Windows application. The repository did not contain `SPEC.md`, and the complete original MASTER PROMPT text was not present in the accessible conversation context. Items beyond the visible requirements remain unresolved instead of being invented.

## Product

Ledgerline is an offline-first accounting application for Windows. It uses a local SQLite database and has working navigation. Android is out of scope.

## Visible requirements and delivered scope

- English interface by default.
- Persian language support with right-to-left layout.
- Light and dark themes saved between launches.
- Dashboard, chart of accounts, journal, income statement, and balance summary.
- Double-entry journal entries that must balance before saving.
- Product catalog and inventory quantities.
- Sales invoices that affect accounting and inventory.
- Settings and skeleton loading states.
- Smart Import with CSV preview and review before posting.
- Local image OCR using bundled Tesseract and English/Persian language data.
- Windows build and installer produced through GitHub Actions.
- SQLite backup export and validated restore; a successful restore keeps the prior database as a recovery copy.
- Update check against public GitHub Releases; HTTPS redirects are restricted to GitHub release hosts; installer digest is checked before user approval.

## Current implementation boundaries

- Restore accepts compatible Ledgerline SQLite databases and replaces the active local ledger after integrity, schema, foreign-key, and journal-balance checks. The previous database is retained as a timestamped recovery copy.
- The initial account list and USD display are defaults.
- Data is stored locally on a single Windows device; synchronization is not implemented.
- OCR returns editable text for review. It does not infer a balanced journal automatically or post without user confirmation.
- Update integrity uses GitHub's release asset SHA-256 digest. Current installers do not have Authenticode signatures, so verified publisher identity is not available.
- Full accounting policy, tax rules, currencies, recurring transactions, permissions, audit workflows, hardware integrations, AI-assisted import, and other requirements from the unavailable prompt remain unspecified here.
