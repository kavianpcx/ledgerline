# Product audit — 2026-11-19

## Scope and evidence

This audit compares the current GitHub source with `docs/PRODUCT_SPECIFICATION.md` and distinguishes merged code from changes under review.

Current `main` is `ab615a02f369155fbd5ad44ab170f0a3c7c4005a`. PRs #2 through #5 are merged: Windows sidebar repair, currency safeguards, editable/paginated catalog, and reviewed product CSV import. The main push workflow [run 44371927172](https://github.com/kavianpcx/ledgerline/actions/runs/44371927172) completed successfully, including analysis, the test matrix, and Windows packaging/smoke checks.

Open PR #6, `feature/pos-checkout`, is based on that main commit. Its previous head `2b44cbf47cc8000635087e66af48dc41876a52d3` passed [workflow run 44380788797](https://github.com/kavianpcx/ledgerline/actions/runs/44380788797): Windows build and installer smoke, analysis, and all ten test-file jobs passed. The release-publish job was skipped for the pull-request event. The stock-history changes in the current PR head require a fresh workflow run; the older run does not verify them.

CI has captured Windows screenshots at wide, medium, and narrow sizes, but their pixels have not been manually reviewed here. High-DPI, resize-edge, drag, and Snap behavior remain unverified. This environment has no Flutter/Dart SDK and terminal DNS cannot reach GitHub; GitHub Actions is the available build/test path.

## What works on main

- Flutter Windows desktop app with an integrated caption, window controls, keyboard shortcuts, and the permanent left sidebar at all window widths.
- SQLite schema v4 with accounts, journal entries and lines, products, invoices, payments, and application settings.
- Integer minor-unit accounting, base-currency confirmation and locking, basic balanced journals, invoice sales/payments, and opening-inventory posting. Accounting remains limited and uses one base currency.
- Editable product records and indexed database search/sort/pagination at 10/25/50/100 rows per page.
- Reviewed CSV product import with field mapping, validation, duplicate checks, and atomic catalog/opening-inventory posting.
- English and Persian UI, light/dark themes, SQLite backup/restore with integrity checks, offline Tesseract OCR text extraction, and a partial GitHub release-discovery flow.

The tagged v0.5.1-beta.1 release predates the currency, catalog, and CSV-import merges. The verified distribution remains Windows-only.

## Active checkout work

PR #6 adds a paginated POS catalog and navigation-persistent cart. Checkout rechecks price and stock in the SQLite transaction, posts invoice, inventory, sales/COGS journals, and an optional immediate cash payment atomically; unpaid invoices remain on account.

This revision adds schema v5 stock movement records for opening stock, CSV imports, manual adjustments, and sales. It exposes a product-level, database-paginated history view and prevents movement rows from being updated or deleted. The v4-to-v5 migration records each product's current on-hand quantity as one `migration_balance` row. It does not fabricate past events or alter accounting balances. Purchasing, returns, transfers, warehouses, and other inventory operations are not yet modeled.

## Incomplete product functionality

- Accounting: no complete general ledger/report suite, receivables/payables workflows, full reversals/refunds, currency conversion, transaction-currency snapshots, or configurable jurisdiction rules.
- Inventory: no product images/variants/suppliers, multiple warehouses, receiving/purchasing, returns/transfers, serial/batch tracking, barcode labels, or stock-count workflow. The stock history covers only the movement sources listed above.
- POS and restaurants: the open branch covers basic retail checkout only. Tax/discount controls, split or multiple payments, refunds, receipts, hardware scanners, payment terminals, tables, modifiers, kitchen tickets, and waiter/cashier flows remain absent.
- Smart Import: CSV import and offline image-to-text OCR exist. XLSX/XLS, DOCX/PDF table parsing, document classification, confidence scoring, and reviewed financial import drafts are unfinished.
- People and operations: no service-boundary employee roles, manager area, shifts, idempotent daily close, payroll, or protected management dashboard.
- Sync and security: no authenticated device pairing, transport policy, conflict handling, duplicate-post prevention across devices, application-encrypted database/backup, credential vault, or verified account recovery.
- Platforms and releases: no Android project/build/release, camera scanner, biometrics, or physical-device test. The Windows updater lacks trusted publisher verification, truthful progress/cancel, safe install handoff, rollback, and an older-to-newer recovery test.
- Markets and hardware: no verified exchange/market provider, printer/terminal workflows, or complete settings center.

## Risks and verification limits

The product snapshot still loads the full catalog for dashboard state, and journal/invoice snapshots are capped at 200 rows; those paths need pagination and indexed filters before large datasets. Product history is bounded by database pages, but its oldest migrated record is only an aggregate balance, not a reconstructed audit trail.

CI proves only the checks included in that run. Screenshot capture is not a visual review, and emulator/CI results are not physical Android evidence. The current source is not production-ready for multi-user, multi-device, or sensitive financial use.

## Next implementation order

1. Verify the current PR #6 head on CI, then complete retail POS controls and receipts.
2. Add inventory purchasing, movement/accounting reconciliation, returns, and warehouse support.
3. Add service-layer permissions, protected management, shifts, and idempotent close.
4. Implement Android workflows and secure synchronization with explicit conflict and duplicate-posting rules.
5. Expand Smart Import, reports, multi-currency records, backup/update security, hardware, market data, and release verification.
