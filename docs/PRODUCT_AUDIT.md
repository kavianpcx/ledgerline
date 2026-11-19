# Product audit — 2026-11-19

## Scope and evidence

This audit compares the current GitHub source with `docs/PRODUCT_SPECIFICATION.md` and distinguishes merged code from changes under review.

Current `main` is `571db3cfc8452d1ee28b64574918a13fb571f2b6`. PRs #2 through #6 are merged: Windows sidebar repair, currency safeguards, editable/paginated catalog, reviewed product CSV import, and transactional POS with stock history. PR #6's head passed [workflow run 44424250900](https://github.com/kavianpcx/ledgerline/actions/runs/44424250900), including analysis, ten test suites, Windows release build, and installer smoke. The post-merge main workflow [run 44425936458](https://github.com/kavianpcx/ledgerline/actions/runs/44425936458) was still in progress when this snapshot was recorded.

PR #6 merged as `571db3c`. Run 91 passed the merged source head immediately before the squash merge. It included all ten test suites, a Windows release build, installer smoke checks, and the UI-capture workflow. The release-publish job is skipped for pull-request events.

Manual review of the run #90 and #91 UI artifacts found blank application windows in light and dark scenarios. The workflow currently checks that a window exists and captures pixels, but it does not confirm that Flutter content rendered; visual acceptance is not established. High-DPI, resize-edge, drag, and Snap behavior remain unverified. CI is the available build/test path in this workspace.

## What works on main

- Flutter Windows desktop app with an integrated caption, window controls, keyboard shortcuts, and the permanent left sidebar at all window widths.
- SQLite schema v4 with accounts, journal entries and lines, products, invoices, payments, and application settings.
- Integer minor-unit accounting, base-currency confirmation and locking, basic balanced journals, invoice sales/payments, and opening-inventory posting. Accounting remains limited and uses one base currency.
- Editable product records and indexed database search/sort/pagination at 10/25/50/100 rows per page.
- Reviewed CSV product import with field mapping, validation, duplicate checks, and atomic catalog/opening-inventory posting.
- Paginated retail POS with cart persistence, stale price/stock revalidation, cash or bank-transfer receipts, on-account invoices, and atomic inventory/journal/payment writes. Existing invoice payments migrate as cash.
- Append-only schema v5 stock movements with product history pages; existing balances migrate as aggregate balance-forward entries.
- English and Persian UI, light/dark themes, SQLite backup/restore with integrity checks, offline Tesseract OCR text extraction, and a partial GitHub release-discovery flow.

The tagged v0.5.1-beta.1 release predates the currency, catalog, and CSV-import merges. The verified distribution remains Windows-only.

## Active checkout work

The merged POS rechecks price and stock, posts invoice, inventory, sales/COGS journals, stock movements, and optional cash or bank-transfer payments in a single SQLite transaction. Unpaid invoices remain on account. The rollback regression forces receipt insertion to fail after sale writes and verifies that invoice, inventory, movement, and journal changes all roll back.

Schema v5 records opening stock, CSV imports, adjustments, and sales as append-only movements with paginated product history. Existing quantities migrate as one labeled `migration_balance` per product, without inventing prior events or changing accounting balances. Schema v6 adds payment method history; existing payment rows retain their values and default to cash.

The active `feature/pos-barcode-entry` branch adds exact barcode lookup from the POS field's Enter action, aimed at keyboard-wedge scanners. It keeps leading zeroes and reuses the cart's stock cap and quantity controls. CI is pending. Purchasing, returns, transfers, warehouses, and other inventory operations remain unmodeled.

## Incomplete product functionality

- Accounting: no complete general ledger/report suite, receivables/payables workflows, full reversals/refunds, currency conversion, transaction-currency snapshots, or configurable jurisdiction rules.
- Inventory: no product images/variants/suppliers, multiple warehouses, receiving/purchasing, returns/transfers, serial/batch tracking, barcode labels, or stock-count workflow. The stock history covers only the movement sources listed above.
- POS and restaurants: basic retail checkout supports cash/bank transfer and on-account invoices. The active follow-up branch adds typed barcode lookup for keyboard-wedge scanners; camera scanning is not implemented. POS tax/discount controls, split or partial settlement, refunds/returns, receipts, payment history/reconciliation, terminals, tables, modifiers, kitchen tickets, and waiter/cashier flows remain unfinished.
- Smart Import: CSV import and offline image-to-text OCR exist. XLSX/XLS, DOCX/PDF table parsing, document classification, confidence scoring, and reviewed financial import drafts are unfinished.
- People and operations: no service-boundary employee roles, manager area, shifts, idempotent daily close, payroll, or protected management dashboard.
- Sync and security: no authenticated device pairing, transport policy, conflict handling, duplicate-post prevention across devices, application-encrypted database/backup, credential vault, or verified account recovery.
- Platforms and releases: no Android project/build/release, camera scanner, biometrics, or physical-device test. The Windows updater lacks trusted publisher verification, truthful progress/cancel, safe install handoff, rollback, and an older-to-newer recovery test.
- Markets and hardware: no verified exchange/market provider, printer/terminal workflows, or complete settings center.

## Risks and verification limits

The product snapshot still loads the full catalog for dashboard state, and journal/invoice snapshots are capped at 200 rows; those paths need pagination and indexed filters before large datasets. Product history is bounded by database pages, but its oldest migrated record is only an aggregate balance, not a reconstructed audit trail.

CI proves only the checks included in that run. Manual review found the current Windows UI-capture artifacts blank, so Windows visual acceptance remains open. Emulator/CI results are not physical Android evidence. The current source is not production-ready for multi-user, multi-device, or sensitive financial use.

## Next implementation order

1. Verify the barcode-entry follow-up, then add configurable POS tax/discount, partial and split settlement, payment history/reconciliation, returns, and receipts.
2. Add inventory purchasing, movement/accounting reconciliation, returns, and warehouse support.
3. Add service-layer permissions, protected management, shifts, and idempotent close.
4. Implement Android workflows and secure synchronization with explicit conflict and duplicate-posting rules.
5. Expand Smart Import, reports, multi-currency records, backup/update security, hardware, market data, and release verification.
