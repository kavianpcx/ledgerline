# Product audit — 2026-11-18

## Scope and evidence

This review treats the latest GitHub source as authoritative. At the start of POS checkout work, `main` was `ab615a02f369155fbd5ad44ab170f0a3c7c4005a` after merges of PRs #2 through #5. Sidebar repair PR #2, currency-safety PR #3, product-catalog PR #4, and product CSV import PR #5 are merged. The successful post-PR5 Windows build and test workflow is [run 44371927172](https://github.com/kavianpcx/ledgerline/actions/runs/44371927172). It passed analysis, all eight test files, Windows packaging/smoke, and scripted evidence capture; its release-publish job was skipped because it was a PR run.

CI ran the installed Windows application at wide, medium, and narrow window sizes and captured title-bar and settings scenarios. The UI-evidence artifact exists, but its pixels have not been manually reviewed in this workspace. Therefore CI execution is verified, while visual acceptance remains incomplete. The local workspace is a stale, uncommitted snapshot with no repository commits, and this environment has no Flutter or Dart command; it is not used as a source of truth. GitHub Actions is the available build/test path.

The active product target is Windows 10/11 and Android phones/tablets. The product requirements remain broader than the currently released Windows-only prerelease; Android has not been removed from scope.

## What works today

- Flutter Windows desktop application with an integrated caption, window-manager controls, keyboard shortcuts, and a custom title bar.
- Windows sidebar restored by PR #2: fixed to the left at wide, medium, and narrow widths; supports expansion/collapse, grouped search/navigation, compact-mode tooltips, and a persisted preference. Android keeps adaptive navigation in source. The latest Windows CI built the app and captured its desktop scenarios.
- `main` now has SQLite schema version 4 with accounts, journal entries and lines, products, invoices, invoice lines, invoice payments, application settings, and the product-detail migration/indexes.
- Integer-valued amounts and balanced two-line journal posting for the implemented basic entries, opening inventory, sales, and invoice payments. Merged currency safeguards require explicit base-currency confirmation before financial writes, preserve exact minor-unit arithmetic for supported currencies, and prevent changing the base currency after monetary history exists. This remains a small fixed-base-currency ledger, not a complete accounting system.
- Dashboard, chart of accounts, journal, limited summaries, basic product/inventory screens, sales invoices, CSV import, SQLite backup/restore, English/Persian UI, light/dark theme, bounded searchable selects, and a partial release-discovery/update flow.
- Windows installer and CI-generated UI-evidence artifacts. The current verified release is Windows-only.

## Broken or regressed

- The earlier Windows regression that placed primary navigation in the title bar and switched narrow windows to bottom navigation is fixed in PR #2. Automated widget tests and the Windows workflow pass. Windows high-DPI scaling, resize edge behavior, drag/resize acceptance, and Snap layouts still need separate manual verification.
- CI proves that screenshot capture ran; it does not prove that every screenshot looks correct. The captured evidence should receive a visual review before treating the title bar, sidebar, Persian RTL, light/dark pages, and currency popup as visually accepted.
- The merged product screen queries database pages of 10/25/50/100 and has a 10,000-row query test. Some other snapshot flows still materialize product collections, while journal and invoice snapshots are capped at 200 records without full pagination, filters, or bulk actions.
- A local terminal build could not be run: Flutter and Dart are absent in this environment. The GitHub Actions build is the verified package check.

## Incomplete product functionality

- The merged product catalog supports description, category, barcode, editing, and database-backed search/sorting/pagination. Product images/icon selection, variants, suppliers, QR identifiers, multiple warehouses, serial/batch tracking, stock movement history, and purchasing workflows remain unfinished. Product CSV preview and atomic import are merged via PR #5. Branch `feature/pos-checkout` currently adds the basic POS checkout described below; its branch CI is pending.
- The POS work in `feature/pos-checkout` adds database-backed search/pagination, a persisted-across-navigation cart, stale price and stock checks, atomic sale posting, and optional full cash settlement. It does not yet include partial/multiple payments, tax/discount controls, returns/refunds, receipt printing, barcode scanning, keyboard checkout, restaurant tables/kitchen, or payment terminal support. This branch is not in a published release while CI is pending.
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

- Current `main` uses schema version 4. The v3-to-v4 migration adds product description, category, barcode, update timestamps, and indexes; CI covers existing-column compatibility and migration preservation. Product CSV import adds no schema migration and records opening inventory through balanced journal entries. POS checkout adds no schema change; it uses the existing invoice/payment records.
- Future variants, stock movement history, roles, multiple-currency postings, shifts, and sync metadata need separately versioned migrations and upgrade tests. Never reset or delete accounting history during migration.
- Future encrypted backups need a versioned envelope, authenticated integrity checks, and tested recovery. Never reset or delete accounting history during migration.

## Platform-specific constraints

- Windows uses `window_manager`, `WindowCaption`, and `DragToResizeArea`; the integrated caption must preserve native minimize/maximize/close behavior, dragging, resizing, DPI behavior, and Windows Snap.
- Flutter and Dart are not installed in this local workspace. The authenticated GitHub integration can read and write the repository, and GitHub-hosted runners are available for builds and tests.
- Android platform setup is not present in the verified release. Camera scanning, secure storage, biometrics, APK signing, and cross-device sync need Android-specific code and real hardware checks. Emulator or CI evidence must not be described as physical-device testing.

## Required implementation order

1. Complete and visually review the Windows navigation/title-bar repair, including real high-DPI and Snap checks where hardware permits.
2. Currency integrity, paginated product catalog, and transactional product CSV import are merged and passing CI; add product imagery and structured XLSX/DOCX/PDF Smart Import with reviewed destination previews.
3. Verify and merge basic POS checkout after its branch workflow passes, then add partial payments, tax/discount handling, receipts, returns, inventory movement accounting, purchasing, and restaurant orders.
4. Add owner/manager/employee authorization, protected management mode, and idempotent shifts/daily close.
5. Build Android platform-appropriate workflows, scanning, and secure synchronization with conflict and duplicate-posting tests.
6. Finish reports, security, encrypted backups/recovery, updates, printers/terminals, market data, and production installation once their real workflows are verified.

## Acceptance notes

A successful workflow demonstrates only that its included source analysis, automated tests, Windows installer, smoke-start, and scripted screenshot capture passed. It does not establish production readiness or full-product acceptance. No claim is made that Android, physical camera scanning, secure synchronization, complete accounting, or production-grade security is finished.
