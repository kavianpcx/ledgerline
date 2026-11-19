# Product audit — 2026-11-19

## Scope and evidence

This audit compares the current GitHub source with docs/PRODUCT_SPECIFICATION.md and distinguishes merged code from remaining work.

PR #10 was merged as `ea9542effc418144c47b20018da5b46ccd557330`. Post-merge [workflow run 44451374234](https://github.com/kavianpcx/ledgerline/actions/runs/44451374234) passed analysis, all ten test suites, Windows release packaging, installer packaging, and UI evidence capture. The captured screenshots were not manually reviewed.

PR #2 through #10 provide Windows sidebar repair, currency safeguards, editable and paginated catalog, reviewed CSV import, transactional POS, barcode lookup, partial and split receipts, invoice payment history, and receipt-to-journal reconciliation. The v7 migration links existing manual payments only when date, amount, method, and invoice description match; unmatched receipts remain flagged for review. PR #11 adds a saved default sales-tax rate and per-invoice discounts, including a v8 migration and balanced journal postings; its Actions results are pending and it is not part of main until merged.

## What works on main

- Flutter Windows desktop application with integrated title bar, window controls, keyboard shortcuts, and permanent left sidebar.
- SQLite schema v7 with accounts, journal entries and lines, products, invoices, invoice lines, payment method and journal-entry history, stock movement history, and application settings.
- Integer minor-unit accounting, confirmed/locked base currency, balanced journals, invoice sales/payments, and opening-inventory posting. Accounting remains limited to one base currency.
- Editable product records with indexed database search, sorting, and pagination at 10/25/50/100 rows per page.
- Reviewed CSV product import with mapping, validation, duplicate checks, and atomic catalog/opening-inventory posting.
- Basic retail POS with persisted cart, price/stock revalidation, exact barcode lookup from keyboard input and Enter, cash or bank-transfer payments including partial receipts and split tenders, on-account invoices, and atomic sale/inventory/journal/payment postings.
- Append-only stock history for opening balances, CSV imports, adjustments, and sales. Existing quantities migrate as labeled balance-forward records; earlier events are not reconstructed.
- English and Persian UI, light/dark themes, SQLite backup/restore with integrity checks, offline Tesseract OCR text extraction, and partial GitHub release discovery.

The tagged v0.5.1-beta.1 release predates the current currency, catalog, import, and POS changes. The verified distribution remains Windows-only.

## POS gaps remaining

Refunds/returns, invoice and thermal receipts, keyboard shortcuts, customer records, terminals, and restaurant workflows remain incomplete. Configurable default tax and invoice discounts are being reviewed in PR #11 and are not yet part of main.

## Incomplete product functionality

- Accounting: no complete general ledger/report suite, full receivables/payables workflows, full reversals/refunds, foreign-currency conversion, transaction-currency snapshots, or configurable jurisdiction rules.
- Product/inventory: no product image uploads or curated icons, variants, suppliers, multiple warehouses, receiving/purchasing, returns/transfers, serial/batch tracking, barcode labels, or stock-count workflow.
- Smart Import: reviewed CSV product import and offline image-to-text OCR exist. XLSX/XLS, DOCX/PDF table parsing, document classification, confidence scoring, and reviewed financial-import drafts are unfinished.
- People/operations: no service-layer employee roles, manager area, shifts, idempotent daily close, payroll, or protected management dashboard.
- Security/sync: no authenticated pairing, transport policy, conflict handling, cross-device duplicate-post prevention, application-encrypted database/backups, credential vault, or verified account recovery.
- Platforms/releases: no Android build/release, camera scanner, biometrics, or physical-device test. The Windows updater still lacks trusted publisher verification, truthful progress/cancel, safe installer handoff, rollback, and an older-to-newer recovery test.
- Markets/hardware: no verified exchange/market provider, printing, authorized terminal workflow, or complete functional settings center.

## Risks and verification limits

CI proves only the checks included in a workflow. Manual review of the PR #6 and PR #7 Windows UI artifacts found blank application windows; later screenshot artifacts, including PR #10, have not been manually reviewed. Capture success alone is not visual acceptance. The snapshot query loads the full product catalog while recent entries and invoices are capped at 200; large-data dashboard/report pagination and aggregation still need work. High-DPI, resize-edge, drag, Snap, Android hardware, and physical-device camera behavior remain unverified. The application is not ready for sensitive multi-user or multi-device production use.

## Next implementation order

1. Add POS returns and refunds with linked stock and journal reversals, then invoice and thermal receipts.
2. Add inventory purchasing, movement/accounting reconciliation, returns, and warehouse support.
3. Add service-layer permissions, protected management, shifts, and idempotent close.
4. Implement Android workflows and secure synchronization with explicit conflict and duplicate-posting rules.
5. Expand Smart Import, reports, multi-currency records, backup/update security, hardware, market data, and release verification.
