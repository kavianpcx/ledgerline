# Product audit — 2026-11-19

## Scope and evidence

This audit compares the current GitHub source with docs/PRODUCT_SPECIFICATION.md and distinguishes merged code from remaining work.

PR #18 is merged as `f191f1ba2ea92be24c2cead6040d204ef9843cb2`. [PR workflow run 44492408849](https://github.com/kavianpcx/ledgerline/actions/runs/44492408849) and [post-merge main run 44494674461](https://github.com/kavianpcx/ledgerline/actions/runs/44494674461) passed analysis, all ten test suites, and Windows packaging. PR #18's earlier capture only checked for a visible window. [Run 44487141126](https://github.com/kavianpcx/ledgerline/actions/runs/44487141126) also passed those checks, while `publish-release` was skipped by design: `.github/workflows/build.yml` requires a push to `main` and `[release]` in the head commit message. No release marker was added. The latest published prerelease remains [v0.5.1-beta.1](https://github.com/kavianpcx/ledgerline/releases/tag/v0.5.1-beta.1) (November 18, 2026).

Open, review-only [PR #19](https://github.com/kavianpcx/ledgerline/pull/19) currently points to `e3397eea2e607103f59ea0ee764b3a9ecf05b8a7`. [Run 44510332969](https://github.com/kavianpcx/ledgerline/actions/runs/44510332969) passed analysis, all ten test suites, Windows release packaging, visible-content checks, and installer launch smoke. OCR verified the dashboard, title bar, all three sidebar widths, light/dark settings, Persian RTL settings, and currency popup; the contact sheet was visually inspected and showed the expected Ledgerline content in each. CI silently installed the package, launched the installed executable, recognized dashboard text, and recorded the executable SHA-256 in its report. The screenshots, report, and installer are attached to the run. This is CI evidence for the silent install and launch path, not interactive installer acceptance, code-signing verification, or physical printer output. No tag, existing release asset, or public release was changed.

PR #2 through #18 provide Windows sidebar repair, currency safeguards, editable and paginated catalog, reviewed CSV/XLSX import, transactional POS, barcode lookup, partial and split receipts, invoice payment history and reconciliation, configurable default sales tax, invoice discounts, full and partial-line returns, invoice and thermal receipt PDFs, product images/icons, F2/F4 POS shortcuts, and recent-invoice customer selection. The v7 migration links existing manual payments only when date, amount, method, and invoice description match; unmatched receipts remain flagged for review. Schema v8 stores discounts on new invoices and migrates older invoices with a zero discount. Schema v9 records full-invoice returns and customer-return stock movements. Schema v10 adds built-in product icons and optional product-image BLOBs. Schema v11 adds per-return headers and line snapshots for partial-line invoice returns without rewriting existing invoices or payment rows.

## What works on main

- Flutter Windows desktop application with integrated title bar, window controls, keyboard shortcuts, and permanent left sidebar.
- SQLite schema v11 with accounts, journal entries and lines, products, invoices and lines, discounts, invoice payment and full/partial return history, stock movement history, application settings, product icon keys, and bounded image BLOBs.
- Integer minor-unit accounting, confirmed/locked base currency, balanced journals, invoice sales/payments, and opening-inventory posting. Accounting remains limited to one base currency.
- Editable product records with indexed database search, sorting, and pagination at 10/25/50/100 rows per page.
- Reviewed CSV and XLSX product import with mapping, validation, duplicate checks, and atomic catalog/opening-inventory posting. Product images and built-in icons are also supported on main.
- Basic retail POS with persisted cart, price/stock revalidation, exact barcode lookup from keyboard input and Enter, F2/F4 keyboard shortcuts, searchable suggestions from prior invoice customer names, cash or bank-transfer payments including partial receipts and split tenders, on-account invoices, and atomic sale/inventory/journal/payment postings. Full and partial-line returns refund collected amounts, credit remaining receivables, restore returned stock, and reverse revenue, tax, and cost postings transactionally. Partial-line returns prorate invoice discounts and tax over returned quantities and preserve return/payment history. A4 invoice and 80 mm receipt PDFs render saved invoice snapshots in English and Persian, show returned value, and open the system print dialog; physical printer output is not verified.
- Append-only stock history for opening balances, CSV imports, adjustments, sales, and full/partial customer returns. Existing quantities migrate as labeled balance-forward records; earlier events are not reconstructed.
- English and Persian UI, light/dark themes, SQLite backup/restore with integrity checks, offline Tesseract OCR text extraction, and partial GitHub release discovery.

The tagged v0.5.1-beta.1 release predates the current currency, catalog, import, and POS changes. The verified distribution remains Windows-only.

## POS gaps remaining

Full and partial-line returns, A4 invoice and thermal receipt PDFs, F2/F4 POS shortcuts, and searchable suggestions from prior invoice customer names are implemented on main. Persistent customer records, authorized terminals, and restaurant workflows remain incomplete. Tax and invoice discounts are also merged into main.

## Incomplete product functionality

- Accounting: no complete general ledger/report suite, full receivables/payables workflows, full reversals/refunds, foreign-currency conversion, transaction-currency snapshots, or configurable jurisdiction rules.
- Product/inventory: product images/icons, editable products, catalog search/pagination, reviewed CSV/XLSX import, and product barcode lookup work. Variants, suppliers, multiple warehouses, receiving/purchasing, purchase/partial-line returns/transfers, serial/batch tracking, barcode labels, and stock-count workflow remain open.
- Smart Import: reviewed CSV/XLSX product import and offline image-to-text OCR exist on main. DOCX/PDF table parsing, document classification, OCR-to-structured fields, confidence scoring, and reviewed financial-import drafts remain unfinished.
- People/operations: no service-layer employee roles, manager area, shifts, idempotent daily close, payroll, or protected management dashboard.
- Security/sync: no authenticated pairing, transport policy, conflict handling, cross-device duplicate-post prevention, application-encrypted database/backups, credential vault, or verified account recovery.
- Platforms/releases: no Android build/release, camera scanner, biometrics, or physical-device test. The Windows updater still lacks trusted publisher verification, truthful progress/cancel, safe installer handoff, rollback, and an older-to-newer recovery test.
- Markets/hardware: no verified exchange/market provider, authorized terminal workflow, or complete functional settings center. Printer hardware and model-specific formatting remain unverified.

## Risks and verification limits

CI proves only the checks included in a workflow. The published v0.5.1-beta.1 screenshots from run 44487141126 contain nearly blank currency-popup, Persian settings, and titlebar images; its narrow-sidebar capture shows a blank app with a console behind it. PR #19's run 44510332969 recaptured and asserted visible content for the title bar, three sidebar widths, light/dark settings, Persian RTL settings, currency popup, and installer-launched dashboard. The contact sheet was visually inspected; the app window and expected text and controls are visible. The installed executable's hash is recorded in the CI evidence report. This does not replace interactive installer, Authenticode signature, high-DPI, resize-edge, drag, Snap, or physical printer verification. The snapshot query loads the full product catalog while recent entries and invoices are capped at 200; large-data dashboard/report pagination and aggregation still need work. Android hardware and physical-device camera behavior remain unverified. The application is not ready for sensitive multi-user or multi-device production use.

## Next implementation order

1. Review and decide whether to merge PR #19; keep any release publication separately gated by an explicit marked push to `main`.
2. Add persistent customer records and validate A4/thermal output with supported printer hardware.
3. Add document table parsing and structured OCR with review and confidence signals.
4. Add purchasing, suppliers, stock reconciliation, and multiple warehouses.
5. Implement service-layer permissions, protected management, shifts, idempotent close, and continue Android and secure synchronization work.
