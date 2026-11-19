# Product audit — 2026-11-19

## Scope and evidence

This audit compares the current GitHub source with docs/PRODUCT_SPECIFICATION.md and distinguishes merged code from work under review.

At this snapshot, `main` is `c1eb2dd56f1242a178a38d43dca80d8d0c5e7802`. PRs #2 through #9 are merged: Windows sidebar repair, currency safeguards, editable and paginated catalog, reviewed CSV import, transactional POS, barcode lookup, partial receipts, and split tender checkout. Post-merge [workflow run 44447065073](https://github.com/kavianpcx/ledgerline/actions/runs/44447065073) passed analysis, all ten test suites, Windows release packaging, and UI evidence capture. The screenshots were not manually reviewed.

Open PR #10, `feature/pos-payment-history`, adds per-invoice payment history and reconciliation. It links new receipt records to their journal entries, verifies the matching cash/bank debit and receivables credit, and includes a schema v7 migration that matches older payment rows only when date, amount, method, and invoice description agree. Unmatched rows remain visible for review. CI is running on the branch.

## What works on main

- Flutter Windows desktop application with integrated title bar, window controls, keyboard shortcuts, and permanent left sidebar.
- SQLite schema v6 with accounts, journal entries and lines, products, invoices, invoice lines, payment method history, stock movement history, and application settings.
- Integer minor-unit accounting, confirmed/locked base currency, balanced journals, invoice sales/payments, and opening-inventory posting. Accounting remains limited to one base currency.
- Editable product records with indexed database search, sorting, and pagination at 10/25/50/100 rows per page.
- Reviewed CSV product import with mapping, validation, duplicate checks, and atomic catalog/opening-inventory posting.
- Basic retail POS with persisted cart, price/stock revalidation, exact barcode lookup from keyboard input and Enter, cash or bank-transfer payments including partial receipts and split tenders, on-account invoices, and atomic sale/inventory/journal/payment postings.
- Append-only stock history for opening balances, CSV imports, adjustments, and sales. Existing quantities migrate as labeled balance-forward records; earlier events are not reconstructed.
- English and Persian UI, light/dark themes, SQLite backup/restore with integrity checks, offline Tesseract OCR text extraction, and partial GitHub release discovery.

The tagged v0.5.1-beta.1 release predates the current currency, catalog, import, and POS changes. The verified distribution remains Windows-only.

## POS work under review

PR #9 split-tender checkout is merged. Open PR #10 adds payment history and a reconciliation check that verifies each receipt against its linked cash/bank and receivables journal lines. It also provides a schema v7 migration and tests for linked legacy manual payments and mismatched postings.

Refunds/returns, invoice and thermal receipts, keyboard shortcuts, configurable tax/discount, customer records, terminals, and restaurant workflows remain incomplete.

## Incomplete product functionality

- Accounting: no complete general ledger/report suite, full receivables/payables workflows, full reversals/refunds, foreign-currency conversion, transaction-currency snapshots, or configurable jurisdiction rules.
- Product/inventory: no product image uploads or curated icons, variants, suppliers, multiple warehouses, receiving/purchasing, returns/transfers, serial/batch tracking, barcode labels, or stock-count workflow.
- Smart Import: reviewed CSV product import and offline image-to-text OCR exist. XLSX/XLS, DOCX/PDF table parsing, document classification, confidence scoring, and reviewed financial-import drafts are unfinished.
- People/operations: no service-layer employee roles, manager area, shifts, idempotent daily close, payroll, or protected management dashboard.
- Security/sync: no authenticated pairing, transport policy, conflict handling, cross-device duplicate-post prevention, application-encrypted database/backups, credential vault, or verified account recovery.
- Platforms/releases: no Android build/release, camera scanner, biometrics, or physical-device test. The Windows updater still lacks trusted publisher verification, truthful progress/cancel, safe installer handoff, rollback, and an older-to-newer recovery test.
- Markets/hardware: no verified exchange/market provider, printing, authorized terminal workflow, or complete functional settings center.

## Risks and verification limits

CI proves only the checks included in a workflow. Manual review of the PR #6 and PR #7 Windows UI artifacts found blank application windows; later screenshot artifacts have not been manually reviewed. Capture success alone is not visual acceptance. The snapshot query loads the full product catalog while recent entries and invoices are capped at 200; large-data dashboard/report pagination and aggregation still need work. High-DPI, resize-edge, drag, Snap, Android hardware, and physical-device camera behavior remain unverified. The application is not ready for sensitive multi-user or multi-device production use.

## Next implementation order

1. Finish and merge payment history/reconciliation, then add returns, refunds, and receipts.
2. Add inventory purchasing, movement/accounting reconciliation, returns, and warehouse support.
3. Add service-layer permissions, protected management, shifts, and idempotent close.
4. Implement Android workflows and secure synchronization with explicit conflict and duplicate-posting rules.
5. Expand Smart Import, reports, multi-currency records, backup/update security, hardware, market data, and release verification.
