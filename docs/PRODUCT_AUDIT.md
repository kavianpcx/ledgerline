# Product audit — 2026-11-19

## Scope and evidence

This audit compares the current GitHub source with docs/PRODUCT_SPECIFICATION.md and distinguishes merged code from work under review.

Current main is b37ece300e3d35d2231c3aa2049077c583d098f3. PRs #2 through #7 are merged: Windows sidebar repair, currency safeguards, editable and paginated catalog, reviewed product CSV import, transactional POS with stock history, and exact keyboard-wedge barcode lookup. PR #7's [workflow run 44427000553](https://github.com/kavianpcx/ledgerline/actions/runs/44427000553) passed analyzer, all ten test suites, Windows release build, installer packaging, screenshot capture, and artifact upload. Manual review found blank application windows in the screenshot evidence; visual acceptance is not established.

Open PR #8 adds partial payment entry to the POS checkout. Its cashier-facing amount field, integer minor-unit parsing, remaining-balance display, and widget/accounting tests have not yet passed CI.

## What works on main

- Flutter Windows desktop application with integrated title bar, window controls, keyboard shortcuts, and permanent left sidebar.
- SQLite schema v6 with accounts, journal entries and lines, products, invoices, invoice lines, payment method history, stock movement history, and application settings.
- Integer minor-unit accounting, confirmed/locked base currency, balanced journals, invoice sales/payments, and opening-inventory posting. Accounting remains limited to one base currency.
- Editable product records with indexed database search, sorting, and pagination at 10/25/50/100 rows per page.
- Reviewed CSV product import with mapping, validation, duplicate checks, and atomic catalog/opening-inventory posting.
- Basic retail POS with persisted cart, price/stock revalidation, exact barcode lookup from keyboard input and Enter, cash or bank-transfer payments, on-account invoices, and atomic sale/inventory/journal/payment postings.
- Append-only stock history for opening balances, CSV imports, adjustments, and sales. Existing quantities migrate as labeled balance-forward records; earlier events are not reconstructed.
- English and Persian UI, light/dark themes, SQLite backup/restore with integrity checks, offline Tesseract OCR text extraction, and partial GitHub release discovery.

The tagged v0.5.1-beta.1 release predates the current currency, catalog, import, and POS changes. The verified distribution remains Windows-only.

## POS work under review

PR #8 exposes the transactional invoice payment amount for cashier entry. Tests cover overpayment rejection, remaining-balance display, partial receipt posting, receivables, and the accounting equation.

Split tenders, payment history/reconciliation, refunds/returns, receipts/printing, shortcuts, configurable tax/discount, customer records, terminals, and restaurant workflows remain incomplete. PR #8 does not test split tender behavior.

## Incomplete product functionality

- Accounting: no complete general ledger/report suite, full receivables/payables workflows, full reversals/refunds, foreign-currency conversion, transaction-currency snapshots, or configurable jurisdiction rules.
- Product/inventory: no product image uploads or curated icons, variants, suppliers, multiple warehouses, receiving/purchasing, returns/transfers, serial/batch tracking, barcode labels, or stock-count workflow.
- Smart Import: reviewed CSV product import and offline image-to-text OCR exist. XLSX/XLS, DOCX/PDF table parsing, document classification, confidence scoring, and reviewed financial-import drafts are unfinished.
- People/operations: no service-layer employee roles, manager area, shifts, idempotent daily close, payroll, or protected management dashboard.
- Security/sync: no authenticated pairing, transport policy, conflict handling, cross-device duplicate-post prevention, application-encrypted database/backups, credential vault, or verified account recovery.
- Platforms/releases: no Android build/release, camera scanner, biometrics, or physical-device test. The Windows updater still lacks trusted publisher verification, truthful progress/cancel, safe installer handoff, rollback, and an older-to-newer recovery test.
- Markets/hardware: no verified exchange/market provider, printing, authorized terminal workflow, or complete functional settings center.

## Risks and verification limits

CI proves only the checks included in a workflow. Manual review of the PR #6 and PR #7 Windows UI artifacts found blank application windows; capture success alone is not visual acceptance. High-DPI, resize-edge, drag, Snap, Android hardware, and physical-device camera behavior remain unverified. The application is not ready for sensitive multi-user or multi-device production use.

## Next implementation order

1. Merge partial payment after CI; then add split tenders, payment history/reconciliation, returns, and receipts.
2. Add inventory purchasing, movement/accounting reconciliation, returns, and warehouse support.
3. Add service-layer permissions, protected management, shifts, and idempotent close.
4. Implement Android workflows and secure synchronization with explicit conflict and duplicate-posting rules.
5. Expand Smart Import, reports, multi-currency records, backup/update security, hardware, market data, and release verification.
