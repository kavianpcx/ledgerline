# Product audit — 2026-11-19

## Scope and evidence

This audit compares the current GitHub source with docs/PRODUCT_SPECIFICATION.md and distinguishes merged code from remaining work.

PR #15 was merged as `416b98a2c28984a87e737f959dd239b220f3bed4`. [PR workflow run 44471741999](https://github.com/kavianpcx/ledgerline/actions/runs/44471741999) passed analysis, all ten test suites, Windows release packaging, installer packaging, and UI evidence capture. Post-merge [run 44473357416](https://github.com/kavianpcx/ledgerline/actions/runs/44473357416) is running. The screenshots were captured but not manually reviewed.

PR #2 through #15 provide Windows sidebar repair, currency safeguards, editable and paginated catalog, reviewed CSV/XLSX import, transactional POS, barcode lookup, partial and split receipts, invoice payment history and reconciliation, configurable default sales tax, invoice discounts, full-invoice returns, product images/icons, and F2/F4 POS shortcuts. The v7 migration links existing manual payments only when date, amount, method, and invoice description match; unmatched receipts remain flagged for review. Schema v8 stores discounts on new invoices and migrates older invoices with a zero discount. Schema v9 records full-invoice returns and customer-return stock movements. Schema v10 adds built-in product icons and optional product-image BLOBs.

## What works on main

- Flutter Windows desktop application with integrated title bar, window controls, keyboard shortcuts, and permanent left sidebar.
- SQLite schema v10 with accounts, journal entries and lines, products, invoices, invoice lines, invoice discounts, invoice payment and return history, stock movement history, application settings, product icon keys, and bounded image BLOBs.
- Integer minor-unit accounting, confirmed/locked base currency, balanced journals, invoice sales/payments, and opening-inventory posting. Accounting remains limited to one base currency.
- Editable product records with indexed database search, sorting, and pagination at 10/25/50/100 rows per page.
- Reviewed CSV and XLSX product import with mapping, validation, duplicate checks, and atomic catalog/opening-inventory posting. Product images and built-in icons are also supported on main.
- Basic retail POS with persisted cart, price/stock revalidation, exact barcode lookup from keyboard input and Enter, F2/F4 keyboard shortcuts, cash or bank-transfer payments including partial receipts and split tenders, on-account invoices, and atomic sale/inventory/journal/payment postings. Full-invoice returns refund collected payments, cancel remaining receivables, restore stock, and reverse journal postings transactionally.
- Append-only stock history for opening balances, CSV imports, adjustments, sales, and full-invoice customer returns. Existing quantities migrate as labeled balance-forward records; earlier events are not reconstructed.
- English and Persian UI, light/dark themes, SQLite backup/restore with integrity checks, offline Tesseract OCR text extraction, and partial GitHub release discovery.

The tagged v0.5.1-beta.1 release predates the current currency, catalog, import, and POS changes. The verified distribution remains Windows-only.

## PR #16 POS recent-customer selection candidate under validation

The checkout field offers searchable suggestions from distinct, recent invoice customer names while keeping free-form names available. A bounded repository query supplies the suggestions; there is no customer profile table or new schema migration. Widget coverage selects a suggested name, and repository coverage checks deduplication, recency ordering, limits, and invalid bounds. CI verification is pending.
## POS gaps remaining

Full-invoice refunds/returns are implemented on main; partial-line returns, invoice and thermal receipts, customer records, terminals, and restaurant workflows remain incomplete. F2/F4 POS shortcuts are merged into main. Searchable suggestions for prior invoice customers are proposed in PR #16 pending CI. Tax and invoice discounts are also merged into main.

## Incomplete product functionality

- Accounting: no complete general ledger/report suite, full receivables/payables workflows, full reversals/refunds, foreign-currency conversion, transaction-currency snapshots, or configurable jurisdiction rules.
- Product/inventory: product images/icons, editable products, catalog search/pagination, reviewed CSV/XLSX import, and product barcode lookup work. Variants, suppliers, multiple warehouses, receiving/purchasing, purchase/partial-line returns/transfers, serial/batch tracking, barcode labels, and stock-count workflow remain open.
- Smart Import: reviewed CSV/XLSX product import and offline image-to-text OCR exist on main. DOCX/PDF table parsing, document classification, OCR-to-structured fields, confidence scoring, and reviewed financial-import drafts remain unfinished.
- People/operations: no service-layer employee roles, manager area, shifts, idempotent daily close, payroll, or protected management dashboard.
- Security/sync: no authenticated pairing, transport policy, conflict handling, cross-device duplicate-post prevention, application-encrypted database/backups, credential vault, or verified account recovery.
- Platforms/releases: no Android build/release, camera scanner, biometrics, or physical-device test. The Windows updater still lacks trusted publisher verification, truthful progress/cancel, safe installer handoff, rollback, and an older-to-newer recovery test.
- Markets/hardware: no verified exchange/market provider, printing, authorized terminal workflow, or complete functional settings center.

## Risks and verification limits

CI proves only the checks included in a workflow. Manual review of the PR #6 and PR #7 Windows UI artifacts found blank application windows; later screenshot artifacts, including PR #10 and PR #13, have not been manually reviewed. Capture success alone is not visual acceptance. The snapshot query loads the full product catalog while recent entries and invoices are capped at 200; large-data dashboard/report pagination and aggregation still need work. High-DPI, resize-edge, drag, Snap, Android hardware, and physical-device camera behavior remain unverified. The application is not ready for sensitive multi-user or multi-device production use.

## Next implementation order

1. Add partial-line returns, invoice/thermal receipt printing, and customer records.
2. Add document table parsing and structured OCR with review and confidence signals.
3. Add purchasing, suppliers, stock reconciliation, and multiple warehouses.
4. Implement service-layer permissions, protected management, shifts, and idempotent close.
5. Extend Android workflows, reports, currency support, secure synchronization, update/backup security, and verified releases.
