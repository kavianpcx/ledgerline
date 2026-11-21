# Product audit — 2026-11-20

## Scope and evidence

This audit compares the current GitHub source with docs/PRODUCT_SPECIFICATION.md and distinguishes merged code from remaining work.

The audited main source includes PR #18, `f191f1ba2ea92be24c2cead6040d204ef9843cb2`, which added transactional partial-line returns. The current 0.6.0-beta.1 changes add onboarding, More Tools, Android support, and a market-rate display; their workflow results are recorded with the release.

PR #2 through #18 provide Windows sidebar repair, currency safeguards, editable and paginated catalog, reviewed CSV/XLSX import, transactional POS, keyboard-wedge barcode lookup, partial and split receipts, invoice payment history and reconciliation, configurable default sales tax, invoice discounts, full and partial-line returns, product images/icons, F2/F4 POS shortcuts, and recent-invoice customer selection. The v7 migration links existing manual payments only when date, amount, method, and invoice description match; unmatched receipts remain flagged for review. Schema v8 stores discounts on new invoices and migrates older invoices with a zero discount. Schema v9 records full-invoice returns and customer-return stock movements. Schema v10 adds built-in product icons and optional product-image BLOBs. Schema v11 adds partial-return history and stock movements.

## What works on main

- Flutter Windows desktop application with integrated title bar, window controls, keyboard shortcuts, and permanent left sidebar. Android release runner generation and APK packaging are included in CI.
- SQLite schema v11 with accounts, journal entries and lines, products, invoices, invoice lines, invoice discounts, invoice payment and return history, stock movement history, application settings, product icon keys, and bounded image BLOBs.
- Integer minor-unit accounting, confirmed/locked base currency, balanced journals, invoice sales/payments, and opening-inventory posting. Accounting remains limited to one base currency.
- Editable product records with indexed database search, sorting, and pagination at 10/25/50/100 rows per page.
- Reviewed CSV and XLSX product import with mapping, validation, duplicate checks, and atomic catalog/opening-inventory posting. Product images and built-in icons are also supported on main.
- Basic retail POS with persisted cart, price/stock revalidation, exact barcode lookup from keyboard input and Enter, F2/F4 keyboard shortcuts, searchable suggestions from prior invoice customer names, cash or bank-transfer payments including partial receipts and split tenders, on-account invoices, and atomic sale/inventory/journal/payment postings. Full and partial-line returns refund collected payments, cancel remaining receivables, restore stock, and reverse journal postings transactionally. A4 invoice and 80 mm receipt PDFs render saved invoice snapshots in English and Persian and open the system print dialog; physical printer output is not verified.
- Append-only stock history for opening balances, CSV imports, adjustments, sales, and full-invoice customer returns. Existing quantities migrate as labeled balance-forward records; earlier events are not reconstructed.
- English and Persian UI, light/dark themes, SQLite backup/restore with integrity checks, offline Tesseract OCR text extraction, and partial GitHub release discovery.
- First-run setup for business name/type, country, interface language, and base accounting currency. Legacy monetary values require explicit confirmation before setting their currency.
- A More Tools hub with a four-operation calculator, a reviewed Smart Import shortcut, and a currency card/converter screen. Its quotes use NerkhAra's Tehran free-market data, display source timestamps/staleness, and remain separate from accounting postings.
- Android SQLite backend selection, Android runner generation in CI, a universal APK build, a compact camera barcode dialog on product forms, and Android release download handoff through the OS.
- A MIT source license; the Noto font keeps its separate OFL license.

The tagged v0.5.1-beta.1 release predates the current currency, catalog, import, and POS changes. The 0.6.0-beta.1 release workflow now packages Windows and Android artifacts; CI and device acceptance results must be recorded separately.

## POS gaps remaining

Full and partial-line returns, A4/80 mm receipts, F2/F4 POS shortcuts, and searchable suggestions from prior invoice customer names are implemented on main. Persistent customer records, terminals, and restaurant workflows remain incomplete. Tax and invoice discounts are also merged into main.

## Incomplete product functionality

- Accounting: no complete general ledger/report suite, full receivables/payables workflows, foreign-currency accounting with transaction-currency snapshots, or configurable jurisdiction rules.
- Product/inventory: product images/icons, editable products, catalog search/pagination, reviewed CSV/XLSX import, and product barcode lookup work. Variants, suppliers, multiple warehouses, receiving/purchasing, purchase returns/transfers, serial/batch tracking, barcode labels, and stock-count workflow remain open.
- Smart Import: reviewed CSV/XLSX product import and offline image-to-text OCR exist on main. DOCX/PDF table parsing, PowerPoint table extraction, document classification, OCR-to-structured fields, confidence scoring, and reviewed financial-import drafts remain unfinished.
- People/operations: no service-layer employee roles, manager area, shifts, idempotent daily close, payroll, or protected management dashboard.
- Security/sync: no PIN or biometric lock, authenticated pairing, transport policy, conflict handling, cross-device duplicate-post prevention, application-encrypted database/backups, credential vault, or verified account recovery. The new setup and Android build do not add these controls.
- Platforms/releases: Android runner generation and APK packaging are in CI, and the product form has a camera scanner. Android release APKs currently use CI's generated debug signing key; Android can reject in-place upgrades when the signing key changes. A persistent private release keystore must be configured before Android upgrades are reliable. Android emulator/physical-device camera acceptance and an older-to-newer Android install test remain open. The Windows updater still lacks trusted publisher verification, truthful progress/cancel, rollback, and an older-to-newer recovery test.
- Markets/hardware: NerkhAra free-market quotes are now identified with source and timestamp, but the feed has no warranty and is not an official rate or trade quote. No authorized card-terminal adapter exists; the terminal vendor and protocol must be selected. Printer hardware and model-specific formatting remain unverified.

## Risks and verification limits

CI proves only the checks included in a workflow. Manual review of the PR #6 and PR #7 Windows UI artifacts found blank application windows; later screenshot artifacts, including PR #10 and PR #13, have not been manually reviewed. The 0.6.0-beta.1 workflow adds a More Tools capture; its image must still be visually checked. Capture success alone is not visual acceptance. The snapshot query loads the full product catalog while recent entries and invoices are capped at 200; large-data dashboard/report pagination and aggregation still need work. High-DPI, resize-edge, drag, Snap, Android hardware, and physical-device camera behavior remain unverified. The application is not ready for sensitive multi-user or multi-device production use.

## Next implementation order

1. Verify the Android APK, camera scanner, upgrade path, and local database on real devices; correct any CI or device issues.
2. Add secure PIN/biometric access and protect local database/backup data.
3. Add document table parsing and structured OCR with review and confidence signals.
4. Select authorized payment terminal vendors/protocols before implementing terminal approval and reconciliation.
5. Add persistent customer records, purchasing, suppliers, stock reconciliation, multiple warehouses, service-layer roles, shifts, and idempotent close.
