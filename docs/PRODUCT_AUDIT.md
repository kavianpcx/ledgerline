# Product audit — 2026-11-18

## Scope and evidence

This review treats the latest GitHub source as authoritative. Current `main` at the start of this follow-on work is `2f444d3e2e81aa927a42bba4fd272bc1900bbeb7`; currency-safety PR [#3](https://github.com/kavianpcx/ledgerline/pull/3) is merged. Sidebar repair PR [#2](https://github.com/kavianpcx/ledgerline/pull/2) is merged. Its successful Windows workflow is [run 44306432838](https://github.com/kavianpcx/ledgerline/actions/runs/44306432838); the currency-safety Windows build and test workflow is [run 44326912497](https://github.com/kavianpcx/ledgerline/actions/runs/44326912497). It passed analysis, all eight test files, Windows packaging/smoke, and scripted evidence capture; its release-publish job was skipped because it was a PR run.

CI ran the installed Windows application at wide, medium, and narrow window sizes and captured title-bar and settings scenarios. The UI-evidence artifact exists, but its pixels have not been manually reviewed in this workspace. Therefore CI execution is verified, while visual acceptance remains incomplete. The local workspace is a stale, uncommitted snapshot with no repository commits, and this environment has no Flutter or Dart command; it is not used as a source of truth. GitHub Actions is the available build/test path.

The active product target is Windows 10/11 and Android phones/tablets. The product requirements remain broader than the currently released Windows-only prerelease; Android has not been removed from scope.

## What works today

- Flutter Windows desktop application with an integrated caption, window-manager controls, keyboard shortcuts, and a custom title bar.
- Windows sidebar restored by PR #2: fixed to the left at wide, medium, and narrow widths; supports expansion/collapse, grouped search/navigation, compact-mode tooltips, and a persisted preference. Android keeps adaptive navigation in source. The latest Windows CI built the app and captured its desktop scenarios.
- The merged main branch has SQLite schema version 3 with accounts, journal entries and lines, products, invoices, invoice lines, invoice payments, and application settings. The active product-catalog PR proposes the v4 product migration.
- Integer-valued amounts and balanced two-line journal posting for the implemented basic entries, opening inventory, sales, and invoice payments. Merged currency safeguards require explicit base-currency confirmation before financial writes, preserve exact minor-unit arithmetic for supported currencies, and prevent changing the base currency after monetary history exists. This remains a small fixed-base-currency ledger, not a complete accounting system.
- Dashboard, chart of accounts, journal, limited summaries, basic product/inventory screens, sales invoices, CSV import, SQLite backup/restore, English/Persian UI, light/dark theme, bounded searchable selects, and a partial release-discovery/update flow.
- Windows installer and CI-generated UI-evidence artifacts. The current verified release is Windows-only.

## Broken or regressed

- The earlier Windows regression that placed primary navigation in the title bar and switched narrow windows to bottom navigation is fixed in PR #2. Automated widget tests and the Windows workflow pass. Windows high-DPI scaling, resize edge behavior, drag/resize acceptance, and Snap layouts still need separate manual verification.
- CI proves that screenshot capture ran; it does not prove that every screenshot looks correct. The captured evidence should receive a visual review before treating the title bar, sidebar, Persian RTL, light/dark pages, and currency popup as visually accepted.
- On the main branch at the start of the product-catalog work, products are still loaded into memory and rendered as one list. The active PR replaces the product screen with database search, sorting, and pages of 10/25/50/100, and adds a 10,000-row query test. Journal and invoice snapshots remain capped at 200 records without full pagination, filters, or bulk actions.
- A local terminal build could not be run: Flutter and Dart are absent in this environment. The GitHub Actions build is the verified package check.

## Incomplete product functionality

- The active product-catalog PR adds description, category, barcode, current-item editing, and paginated search. Product images/icon selection, variants, suppliers, QR identifiers, multiple warehouses, serial/batch tracking, stock movement history, and purchasing workflows remain unfinished until separately implemented and verified.
- Sales are invoice-based, not a complete retail POS or restaurant order system. Table plans, kitchen tickets, modifiers, split bills, refunds/returns, payment terminal integrations, receipt printing, and checkout shortcuts are unfinished.
- Smart Import supports CSV and OCR text extraction only. It does not parse XLSX/XLS, DOCX/PDF tables, map fields with confidence, deduplicate records, or create products or accounting drafts from documents.
- Settings remain a partial control center. User roles, manager mode, shifts, warehouse configuration, synchronization, printing, devices, notifications, payroll/tax, live market data, encrypted backup, and secure recovery are absent or incomplete.
- The updater can discover/download a GitHub release and check an asset digest, but it lacks a separate branded updater, truthful progress/cancel UI, trusted publisher signature verification, safe install handoff/rollback, and an end-to-end older-to-newer update test.
- No Android build workflow or Android release artifact exists. Camera scanning, biometrics, Android secure storage, APK signing, synchronization, and physical-device acceptance tests remain to be implemented.

## Financial safety risks

- The current schema stores integer amounts in columns named `*_cents`, assumes one base currency, and does not persist transaction/display currency or rate snapshots. The published release’s currency selector must not be interpreted as conversion. Mixed-currency transactions are unsupported.
- Currency-safety is merged in PR #3 and passed CI run 44326912497. It adds base-currency setup, decimal/zero-decimal minor-unit parsing, legacy-data confirmation, and write guards. It still supports one base currency per ledger; it does not convert transactions or retain per-invoice exchange-rate snapshots.
- Stock is a mutable quantity on a product row. No immutable stock-movement ledger ties receiving, sales, returns, adjustments, and transfers to accounting entries.
- The journal does not yet provide a complete immutable subledger. Refunds, reversals, and edits need balanced reversal records and audit history rather than destructive updates.
- Product and report loading is not designed for a large catalog or simultaneous offline sales on multiple devices. There is no oversell/conflict-resolution policy.

## Security deficiencies

- No owner/manager/employee identities, service-layer role authorization, employee sessions, or protected management area.
- SQLite files and exported backups are not application-encrypted. There is no key management or authenticated recovery flow.
- No device pairing, authenticated sync, encrypted transport policy, conflict handling, device revocation, or sync audit log.
- The updater digest detects mismatched bytes but does not establish trusted publisher identity. The Windows installer is unsigned.
- Windows Hello and Android biometrics have not been integrated.

## Database migrations

- Main at the start of the product-catalog PR uses schema version 3. The active PR adds a version 4 migration for product description, category, barcode, update timestamps, active state, and indexes; it includes a v3-to-v4 preservation test. Currency configuration uses the existing `app_settings` key/value table.
- Future variants, stock movement history, roles, multiple-currency postings, shifts, and sync metadata need separately versioned migrations and upgrade tests. Never reset or delete accounting history during migration.
- Future encrypted backups need a versioned envelope, authenticated integrity checks, and tested recovery. Never reset or delete accounting history during migration.

## Platform-specific constraints

- Windows uses `window_manager`, `WindowCaption`, and `DragToResizeArea`; the integrated caption must preserve native minimize/maximize/close behavior, dragging, resizing, DPI behavior, and Windows Snap.
- Flutter and Dart are not installed in this local workspace. The authenticated GitHub integration can read and write the repository, and GitHub-hosted runners are available for builds and tests.
- Android platform setup is not present in the verified release. Camera scanning, secure storage, biometrics, APK signing, and cross-device sync need Android-specific code and real hardware checks. Emulator or CI evidence must not be described as physical-device testing.

## Required implementation order

1. Complete and visually review the Windows navigation/title-bar repair, including real high-DPI and Snap checks where hardware permits.
2. Currency integrity is implemented in source and passing CI. Finish and merge product editing/search/pagination; then add image/icon selection and structured Smart Import with reviewed destination previews.
3. Integrate POS, restaurant orders, inventory movement accounting, purchasing, and receipts with balanced journal records.
4. Add owner/manager/employee authorization, protected management mode, and idempotent shifts/daily close.
5. Build Android platform-appropriate workflows, scanning, and secure synchronization with conflict and duplicate-posting tests.
6. Finish reports, security, encrypted backups/recovery, updates, printers/terminals, market data, and production installation once their real workflows are verified.

## Acceptance notes

A successful workflow demonstrates only that its included source analysis, automated tests, Windows installer, smoke-start, and scripted screenshot capture passed. It does not establish production readiness or full-product acceptance. No claim is made that Android, physical camera scanning, secure synchronization, complete accounting, or production-grade security is finished.
