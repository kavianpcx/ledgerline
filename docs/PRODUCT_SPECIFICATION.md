# Ledgerline product specification

This document defines the product target, not the currently shipped feature set. See README and PRODUCT_AUDIT for implementation status. Android remains required even though no Android release is available yet.

This file records the product requirements supplied in the project directive. It is the source of truth for product scope. Implementation status and known risks are tracked separately in [PRODUCT_AUDIT.md](PRODUCT_AUDIT.md).

## Product and platform

Ledgerline is an offline-first, open-source business management and accounting application for Windows 10/11 and Android phones and tablets. It serves retail, restaurants and cafes, wholesale, workshops, small factories, medical supply stores, and service businesses through configurable presets and optional modules. The modules share one accounting foundation; enabling or disabling a module must not delete its data.

Standalone use must not require online registration or a paid cloud service. Windows and Android share business rules and visual identity while using platform-appropriate layouts. Optional synchronization supports a local network or a self-hosted service.

## First-run setup and localization

The first-run wizard collects the business name and type, optional logo, country and region, base accounting currency, display currency, language, date/calendar preferences, default warehouse, optional tax/security configuration, optional data import, and optional device pairing. Advanced steps can be skipped. English is the default language. Persian must have complete RTL layout, suitable typography, locale-aware dates/numbers/currencies, aligned dialogs/tables/selects, and Persian search normalization. Localization must be extensible.

Region affects currency suggestions. An Iranian business must be offered toman and rial and must not be forced to USD. Base, display, invoice, and transaction currencies are distinct. Conversion uses explicit rates, source timestamps, correct minor-unit precision, exact arithmetic, and preserved historical values; changing a display preference never converts or rewrites accounting entries.

## Navigation, appearance, and accessibility

Windows uses an integrated title bar for app identity, optional global search/notifications, and window controls. It must preserve minimize, maximize/restore, close, drag, resize, keyboard shortcuts, high-DPI behavior, and Windows Snap where supported. Primary Windows navigation is a fixed left sidebar at every window width, expandable/collapsible, grouped, searchable, highlighted, persistent, animated subtly, and usable in compact mode with tooltips. Narrow Windows windows must not switch to mobile bottom navigation.

Android uses its own adaptive bottom bar, drawer, or navigation rail according to device size. Both platforms support light and dark themes, accessible keyboard/touch operation, loading skeletons, empty states, responsive dialogs, and consistent bounded searchable selects.

## Business roles and security

Standalone single-owner operation may leave authentication optional. Connected multi-user use requires authenticated employee identity and device authorization. Owner, configurable manager, cashier, waiter, and employee permissions are enforced at the data/service boundary, not only by hiding controls. Cashiers and waiters cannot read management reports, profit, salaries, security settings, or unauthorized cached/API/sync data.

A protected manager area includes sales and shift reporting, inventory valuation, approved administration, users/permissions, payroll/tax configuration, backup/restore, device management, payment integrations, and audit records as authorized. Optional security supports PIN/password, Windows Hello where available, Android biometrics where supported, auto-lock, secure credential storage, encrypted backups, recovery, and a polished first-run setup. There is no mandatory online login.

## Accounting and financial integrity

Provide a chart of accounts, balanced double-entry journals, general ledger, trial balance, balance sheet, income statement/profit and loss, cash flow, receivables/payables, expenses, sales/purchase/tax/inventory/customer/employee/shift reports, and auditable reversals/refunds. Every posting is balanced and transactional. Do not use binary floating point for financial postings. Preserve audit history and historical invoice line descriptions/prices when catalog records change.

Tax, payroll, insurance, exemptions, and tax-inclusive/exclusive pricing are configurable through versioned jurisdiction rules. Do not present unverified rules as legal compliance. Reports use real accounting records, explicit date/currency context, filters, pagination, printing, and PDF/Excel export. Forecasts use historical data, expose assumptions and uncertainty, and are omitted when data is insufficient.

The integrated calculator supports arithmetic, percentages, discounts, markups, margins, taxes, installments, and currency conversion. Its results are never posted without explicit user action. Currency and gold calculators show rates and units used.

## Products, inventory, purchasing, and warehouses

Product records include name, description, SKU, barcode/QR identifier, category, brand, image or curated icon, variants, color/size/unit, purchase and selling prices/currencies, tax category, supplier, warehouse, quantity, reorder level, status, notes, and timestamps. Users can add/change/remove an image or select a licensed curated icon. Catalog edits must not rewrite historical invoices.

Support multiple warehouses, stock receiving/adjustments/counts/transfers, purchase and sales returns, supplier records, categories, reorder alerts, product and stock-movement history, inventory valuation, cost of goods sold, barcode/price labels, and serial/batch tracking as appropriate. Every stock change is traceable and reconciles to accounting. Multi-device operations must use a defined consistency rule that prevents unsafe overselling.

Large lists use indexed database-backed pagination, search, sorting, filters, configurable page sizes (10/25/50/100), resizable/visible columns, bulk actions, export, keyboard navigation, skeleton and empty states, and virtualized scrolling where appropriate.

## Retail POS and payment

The retail checkout supports keyboard-first product search, USB/Bluetooth keyboard-wedge barcode scanners and documented provider adapters, variants, quantities, discounts, tax, subtotal/total, payment method, receipt printing, returns/refunds, shortcuts, scanner setup/test/feedback, unknown barcodes, and duplicate-scan safeguards. Android supports offline camera barcode/QR scanning, camera permission, rear-camera default, optional front-camera/flash, manual entry, scan feedback, throttling, local product lookup, and adding results to a cart.

A payment integration must distinguish real authorized terminals from simulators and handle exact amounts, verified responses, pending/timeouts/cancellation, reconciliation, and duplicate charge prevention.

## Restaurant orders

Restaurant workflows provide floor plans and numbered tables with available/reserved/occupied status, menus, modifiers, quantities, notes, waiter order entry, kitchen tickets/status, order changes and additions, cancelled-item audit history, discounts, tax/service charge, split bills, partial payments, multiple payment methods, cashier settlement, receipts, and refunds. Submitting an order is separate from payment; it must never mark an unpaid order as paid.

## Smart Import and offline document processing

Smart Import accepts XLSX/XLS where supported, CSV, DOCX, digital/scanned PDF, PNG/JPG/JPEG/WEBP, and TXT. Parse structured spreadsheet and document tables directly; use OCR only for images/scanned content. Free local OCR must support English and Persian and require no paid AI API. Evaluate Tesseract and PaddleOCR using accuracy and packaging measurements.

Classify likely product catalogs, supplier invoices, purchase orders, expenses, bank statements, customer lists, sales invoices, and inventory sheets. Extract structured names, SKUs/barcodes, quantities, prices, categories, supplier data, currencies/units, and relevant financial fields. Present source documents and an editable preview with suggested mappings, confidence, validation errors, duplicates, provenance, and a clear import summary. Uncertain records are never automatically posted. The user confirms before catalog/stock/accounting changes.

## Shifts, daily close, and management dashboard

Configure business timezone, opening/closing times, shift boundaries, registers, employees, and close policy. A shift stores start/end, assigned employees/register, orders, sales, payments/refunds, cash movements, expected/actual cash, variance, and notes. Closing is idempotent: it records a permanent summary, closes or locks the shift per policy, starts the next shift/business day when appropriate, and resets only live shift counters. It never deletes transactions or resets accounting balances. Unfinished orders, pending payments, offline devices, and interruption must be handled safely.

Provide paginated/filterable shift history and printable/PDF/Excel summaries. The protected manager dashboard shows actual today's/current-shift sales, employee/location/product performance, revenue/profit, payment mix, active/completed orders, register status, inventory warnings, transactions, expenses, and historical comparisons. Connected dashboards show sync state and last-sync time; cached values are never labeled live.

## Synchronization and device pairing

Standalone offline use works on a single device. Optional local-network mode and self-hosted internet mode pair/revoke devices securely, authenticate users, encrypt transport, queue offline operations with retries, expose sync status, detect conflicts, and keep audit logs. Do not copy a mutable SQLite file between devices. Define authority and conflict resolution, idempotency keys, duplicate-payment prevention, and safe inventory consistency. Restrict operations that need central consistency while offline and explain the restriction. Financial postings must never duplicate.

## Markets and business utilities

A Markets & Exchange Rates module uses identified, authorized, documented providers. It displays selected currency and precious-metal quotes only when supported, with source, quote currency/unit, timestamp/freshness, price change when available, and history where supported. Automatic refresh observes provider limits; manual Refresh Now reports failures and cached data as stale. Loading skeletons correspond to real requests; no fabricated values or artificial delays. Users can configure provider credentials. Core accounting works when no market feed is available. Market-data licensing, availability, price, frequency, and usage restrictions must be verified before integration.

Provide currency conversion, gold valuation, gram/ounce conversion, spread and margin calculators using visibly identified rates and units.

## Settings, hardware, backup, and updates

The functional Settings control center covers General/onboarding, Business, Appearance, Language/region, Accounting, currencies, exchange-rate/market providers, POS/orders/restaurant tables, inventory/warehouses, employees/shifts, Security, users/permissions, payment terminals, barcode scanners, printing, Smart Import, notifications, backup/restore, sync, updates, Advanced, and About. Implemented controls persist; do not expose empty or fake controls.

Printing supports A4/A5 invoices, thermal receipts, labels, shift and account statements, PDF, printer selection/test, templates/logo/footer, QR/barcodes, and connection status where available. Backups have integrity validation and a tested recovery path; encrypted backups use a versioned authenticated format.

Windows update discovery uses public GitHub Releases, optional automatic checks, version/release notes, real byte-based progress/speed, cancellation/retry, cryptographic verification, graceful shutdown, a standalone branded installer/updater hand-off, install progress, relaunch, rollback/recovery, and data preservation. Android update discovery for GitHub APKs follows Android download/signature/install consent; do not bypass platform security. Installer/release artifacts must be verified and usable without developer tools.

## Performance, migration, and release quality

Use indexed queries, transactions, lazy pagination, background work for heavy imports/reports, safe migrations, integrity checks, and tested backup/restore. Test with 10,000 products, 10,000 customers, 100,000 transactions, multiple warehouses, long shift histories, hundreds of restaurant orders, large imports, and historical reports without freezing or data loss.

Maintain documentation for users/developers, schema migrations, security, synchronization, hardware, and release operations. CI runs tests and Windows and Android builds. Publish only actual verified artifacts; incomplete milestone builds are prereleases. Do not claim production readiness before financial, security, sync, and release flows pass.

## Acceptance scenarios

Before declaring the product complete, verify:
1. Windows sidebar/titlebar at wide, medium, and narrow widths, including resize and window controls; Android uses adaptive navigation.
2. Spreadsheet mapping/preview/import, product search/edit, and persistence.
3. Restaurant table order, modifications, separate settlement, receipt, and ledger posting.
4. Owner/employee permission boundaries and protected manager access.
5. Shift start, sales, idempotent close, retained history, and next shift.
6. Android rear/front camera barcode and QR scanning, offline lookup, and cart entry on real hardware where possible.
7. Authenticated Windows/Android synchronization online/offline without duplicate posting.
8. Iranian toman/rial accounting, display-only selection, and explicit foreign-exchange conversion.
9. Real market provider source/timestamp/refresh/stale/error behavior without fabricated quotes.
10. CSV/XLSX/DOCX/PDF/image Smart Import with review and confirmation.
11. Older-to-newer update with verified progress, integrity, installation, relaunch, and data preservation.
12. Purchase/receipt/sale/payment/refund/stock/accounting reconciliation, report export, and backup restore.

Every acceptance result must identify whether it was a unit/widget/emulator/CI test, desktop runner run, or physical-device test. Never report a test or integration as passed if it was not executed.
