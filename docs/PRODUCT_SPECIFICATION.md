# Ledgerline product specification

## Source and limits

This document records the requirements visible in the conversation for the Windows application. The repository was empty when inspected, and it did not contain `SPEC.md`. The conversation context available for implementation did not include the text of a separate full MASTER PROMPT. Requirements not stated in the visible messages are marked unresolved below rather than inferred as confirmed product policy.

## Product

Ledgerline is an accounting application for Windows. It must have a modern desktop interface, a persistent local SQLite database, and working navigation. It is offline-first. Android is out of scope for this repository and must not be generated or built.

## Visible functional requirements

- English is the default interface language.
- Persian language support includes right-to-left layout.
- Light and dark themes are available and saved between launches.
- A dashboard summarizes the books.
- A chart of accounts is available.
- Journal entries use double-entry accounting and must balance before they are saved.
- Products and inventory quantities can be maintained.
- Sales invoices are available and affect both accounting and inventory.
- Settings are available.
- Smart Import supports reviewing data before it is posted. The latest request specifically requires offline OCR.
- Loading uses skeleton placeholders.
- A Windows build is produced by GitHub Actions and published as a downloadable installer in GitHub Releases.
- Updates must be delivered securely and automatically.

## Accounting and storage constraints

- Persist accounting data locally in SQLite.
- Represent monetary values in integer minor units to avoid floating-point posting errors.
- Post each journal entry atomically and validate total debits against total credits.
- Post invoice sales, tax, cost of goods sold, receivables, and inventory changes together as one transaction.
- Prevent inventory from falling below zero.
- Keep selected source documents and OCR processing on-device unless the owner explicitly chooses otherwise.

## Current visible implementation target

- Windows desktop only.
- Dashboard, journal entry list and creation, account balances, income statement, balance summary, products, stock adjustments, invoices, settings, CSV import preview, and receipt/statement image OCR.
- English/Persian, RTL, light/dark theme, and persisted preferences.
- A Windows installer built on `windows-latest` after automated analysis and tests pass.

## Unresolved decisions from the missing full prompt

- Currency, locale-specific number formatting, tax rules, fiscal year, and accounting jurisdiction.
- Whether users can create, edit, archive, and reconcile accounts, contacts, or invoices.
- Required reports, exports, audit history, data encryption, backup and restore rules, and retention policy.
- OCR languages, document types, supported file formats, confidence thresholds, and whether OCR must work from an unpackaged EXE installer.
- Update signing certificate, trusted publisher, release channel, rollback behavior, and consent rules for automatic installation.
- Company branding, exact design references, accessibility targets, minimum Windows version, and installer architecture.

## Release security constraint

GitHub-hosted workflows can build the Windows application and publish release assets. Automatic updates must verify an update source and publisher before installing. A production code-signing certificate and an agreed update trust/consent policy have not been supplied. Until those are configured, the app must not claim to silently install trusted updates.

The selected Windows OCR engine uses `Windows.Media.Ocr`. Microsoft documents that this API is supported only for desktop apps with package identity (MSIX). The requested Inno Setup EXE is unpackaged, so working OCR from that installer remains blocked until an MSIX packaging and signing identity is supplied or a different fully bundled OCR engine is selected.
