# Changelog

## 0.6.0-beta.1

- Add first-run business setup for name, type, country, language, and base accounting currency. Require explicit confirmation before assigning a currency to legacy monetary values.
- Replace duplicate navigation shortcuts in More Tools with a calculator, Smart Import shortcut, and currency market/converter tools.
- Add a precedence-aware calculator with percentage operations and arithmetic validation.
- Add timestamped Tehran free-market currency cards from NerkhAra, selectable display currency, stale-rate handling, manual refresh, and a converter with optional arithmetic. Market rates remain display-only and never post to the ledger.
- Add a compact Android camera barcode scanner dialog to product forms with scan feedback and barcode persistence on product save.
- Use SQLite's Android database plugin on Android while retaining FFI SQLite on Windows and in tests.
- Add a universal Android APK build to CI and attach it to prereleases. Android installation remains under the OS approval flow.
- Extend release discovery to prereleases for beta builds, add Android APK update handoff, and compare prerelease versions correctly.
- Add a More Tools screenshot to the release UI evidence and publish both Windows and Android artifacts.
- Select the MIT License for Ledgerline source; keep the bundled Noto font under OFL.

## Earlier changes included in this release

- Require an explicit base accounting currency before recording monetary data.
- Ask owners to confirm the currency of legacy records without changing amounts.
- Lock base currency changes once monetary history exists.
- Add integer-only amount parsing and formatting for decimal and zero-decimal currencies, including IRR and the internal TOMAN unit.
- Add currency precision, exact rial/toman unit conversion, and repository currency-safety tests.
- Add a product-catalog schema migration with description, category, barcode, update timestamps, and indexes.
- Add database-backed product search, sorting, and pagination for 10/25/50/100 rows per page.
- Add product editing that preserves historical invoice line values and posts inventory valuation changes when on-hand stock cost changes.
- Add migration, catalog paging, invoice history, and 10,000-product tests.
- Add RFC 4180-style CSV parsing for product catalogs, automatic English/Persian column suggestions, editable mapping, row validation, and duplicate checks.
- Import approved products and opening stock in one SQLite transaction with balanced inventory/equity journal entries; add parser, rollback, accounting, and 10,000-row coverage.

- Add a database-paginated POS catalog and a cart that survives page navigation.
- Revalidate cart prices and stock before checkout, and reject changed prices again inside the SQLite sale transaction.
- Post invoice, stock reduction, sales/COGS journals, and an optional full cash or bank-transfer receipt atomically; unpaid checkout remains in receivables.
- Add cash and bank-transfer payment choices to POS checkout, persist the method, and debit the matching cash or bank account.
- Migrate existing invoice payments to the cash method while preserving their balances.
- Add POS widget and repository coverage for cash, bank-transfer, and on-account checkout, balanced accounting, inventory reduction, stale prices, and cart clearing.
- Add append-only stock movement records for opening stock, CSV imports, manual adjustments, and sales.
- Migrate existing on-hand quantities as labeled balance-forward entries without changing ledger balances or inventing prior transactions.
- Add indexed, database-paginated product stock history and prevent movement rows from being edited or deleted.
- Verify stock history across migrations, imports, adjustments, sales, and failed checkout rollback.

## 0.5.1-beta.1

Windows-only milestone prerelease.

- Restore the permanent left Windows sidebar at wide, medium, and narrow window widths.
- Move primary page navigation out of the integrated title bar while retaining the app identity and window controls.
- Add grouped searchable navigation, compact-mode tooltips, sidebar collapse animation, and persisted sidebar preference.
- Keep Android navigation adaptive in source, but this prerelease does not include an Android build.
- Capture Windows screenshots for sidebar widths, title bar, light/dark appearance, Persian layout, and the currency selector.

This is an unfinished product milestone. It does not include the full Android application, secure multi-user access, device synchronization, complete POS/restaurant workflows, full document import, or production-ready financial/security controls.
