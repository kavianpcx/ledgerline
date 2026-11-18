# Changelog

## Unreleased

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


## 0.5.1-beta.1

Windows-only milestone prerelease.

- Restore the permanent left Windows sidebar at wide, medium, and narrow window widths.
- Move primary page navigation out of the integrated title bar while retaining the app identity and window controls.
- Add grouped searchable navigation, compact-mode tooltips, sidebar collapse animation, and persisted sidebar preference.
- Keep Android navigation adaptive in source, but this prerelease does not include an Android build.
- Capture Windows screenshots for sidebar widths, title bar, light/dark appearance, Persian layout, and the currency selector.

This is an unfinished product milestone. It does not include the full Android application, secure multi-user access, device synchronization, complete POS/restaurant workflows, full document import, or production-ready financial/security controls.
