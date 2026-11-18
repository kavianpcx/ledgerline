# Product audit — 2026-11-18

## Scope and evidence

This audit is based on the current `main` source at `dbd72dd8644c2f6fa1894e272c4cfe21d5473ae1`, the repository README and product specification, and the successful Windows CI run 44288432959. The local workspace contains an older, uncommitted 0.3.0 snapshot and cannot reach GitHub from its terminal, so it is not treated as the source of truth. CI has built and launched the Windows app and captured five UI scenarios; those screenshots were not visually inspected for this source audit.

The current directive expands the product scope to Windows and Android. The older repository specification says Android is out of scope; this audit treats the newer directive as authoritative and records Android as missing work.

## What works today

- Flutter desktop application with a Windows custom caption area, window-manager integration, resize behavior, and Ctrl+Shift+M / Ctrl+Shift+F shortcuts.
- Local SQLite database (schema version 3) with accounts, journal entries/lines, products, invoices, invoice lines, invoice payments, and key/value settings.
- Integer minor-unit amounts and balanced two-line journal posting for basic entries, opening inventory, sales, and invoice payments.
- Dashboard, chart of accounts, journal, limited financial summaries, basic products/inventory, sales invoices, CSV import, backup/restore, English/Persian UI, light/dark themes, bounded searchable currency/language selects, and a partial GitHub-release updater.
- A Windows installer and screenshot artifacts are produced by GitHub Actions. On current main, all six test suites and the Windows build/evidence steps passed in run 44288432959.

## Broken or regressed

- **Windows navigation:** the custom title bar contains nine primary page icons. The desktop NavigationRail is explicitly disabled on Windows. At widths below 900 logical pixels the scaffold uses Android-style bottom navigation. This conflicts with the requested permanent left sidebar at every Windows width.
- **Title bar responsibilities:** the title bar mixes primary navigation and a page-specific add-entry action into the window caption. It should retain Ledgerline identity and window controls, with optional global actions only.
- **Sidebar preferences:** no expanded/collapsed state is stored, and the current menu has no searchable grouped sidebar.
- **Data scale:** the snapshot query loads every product into memory; entries and invoices are capped at 200 without database-backed page navigation, totals, sorting or filtering. Large tables will be incomplete or slow.
- The latest CI evidence confirms successful capture execution, not visual acceptance. The new sidebar must be captured and inspected after its change.

## Incomplete product functionality

- Product fields are limited to SKU, name, purchase/selling cost, and stock. There is no complete editing flow, variants, images, categories, suppliers, barcode/QR field, warehouse, batch/serial tracking, or traceable stock movement ledger.
- Sales are invoices, not a fast POS or restaurant order workflow. There are no tables, kitchen tickets, modifiers, split bills, terminal integrations, returns, full refunds, receipt printing, or cashier shortcuts.
- Smart Import is a CSV/text OCR interface. It does not parse XLSX/XLS, DOCX or PDF tables, perform column mapping/confidence review, deduplicate, or import document-derived records. Offline OCR models are bundled for Windows, but this is not an end-to-end document importer.
- Settings cover a small subset of the requested control center. Security, users/roles, manager mode, shifts, warehouses, sync, printing, devices, notifications, payroll/tax, market data, and recovery configuration are absent or incomplete.
- Update support discovers/downloads a release installer and checks a digest, but lacks a separate branded updater, real progress/cancel UI, signed package verification, safe hand-off/rollback, and an older-to-newer end-to-end test.
- The repository builds Windows only. It has no Android build workflow or verified Android release artifact.

## Financial safety risks

- The integer-cent model is better than binary floating point for a fixed two-decimal currency, but the schema and naming assume `*_cents`. No currency minor-unit metadata exists, so this cannot safely represent zero-decimal currencies or toman/rial conversion rules.
- Settings select a display currency, but accounting records do not retain base, transaction, and display currency with explicit exchange rate and timestamp. Changing the display selection must not be treated as conversion.
- Stock is a mutable quantity on the product row. There is no immutable movement journal tying receipt, sale, return, adjustment, and transfer to accounting entries, which weakens reconciliation and auditability.
- Invoice and journal history is not a complete immutable accounting subledger. Refunds, reversals, and edit history need explicit balanced reversal entries rather than destructive updates.
- Current product loading has no pagination or concurrency policy. It is not suitable for large catalogs or simultaneous offline sales on multiple devices.

## Security deficiencies

- No user identities, roles, authorization checks, employee sessions, or management unlock flow.
- SQLite files and exported backups are not application-encrypted. There is no encryption key management or authenticated recovery flow.
- No device pairing, authenticated sync, transport protection, conflict policy, revocation, or audit trail.
- The updater digest check detects accidental mismatch but does not authenticate publisher identity with a signed manifest or trusted signature. The Windows installer is unsigned.
- No Android biometric or Windows Hello integration exists.

## Database migrations

- Schema version is 3. The sidebar preference can be added safely to the existing key/value `app_settings` table without a schema-version bump.
- The next structural schema changes should increment the database version and include upgrade tests from versions 1, 2, and 3 before adding product variants, stock movement history, roles, multi-currency postings, shifts, or sync metadata.
- Backups currently preserve SQLite data, but future encrypted backups need a versioned envelope, authenticated integrity checks, and a tested recovery path. Never reset or delete accounting history during migration.

## Platform-specific constraints

- Windows uses `window_manager`, `WindowCaption`, and `DragToResizeArea`; the custom caption must keep native window controls, system dragging, resizing, DPI behavior, and Snap integration intact.
- Flutter/Dart and Android SDK are not installed in this workspace, and terminal DNS cannot resolve GitHub. Windows/Linux GitHub Actions are available through the authenticated repository integration, so CI is the build/test path.
- There is no Android platform setup in the current source tree or CI. Camera scanning, biometrics, secure storage, APK signing, and device synchronization need Android-specific implementation and real-device checks. Emulator/CI coverage must not be described as physical-device testing.

## Required redesign and implementation order

1. Restore a fixed, collapsible, grouped, searchable Windows left sidebar at every window width; persist its preference. Keep navigation out of the title bar and keep Android navigation adaptive.
2. Verify the sidebar at wide, medium, and narrow Windows widths and capture new UI evidence in CI; run the app on Windows and visually inspect the result.
3. Expand settings and data models with migration and tests before adding financial or security workflows.
4. Build database-backed product editing/search/pagination, then structured import preview and audited import.
5. Add POS, restaurant orders, stock movements, accounting reports, roles, shifts, and secure device synchronization in independently tested steps.
6. Add Android camera scanning, secure storage, and APK release automation; prove hardware features on real devices.
7. Complete update, backup encryption/recovery, printer and market-data integrations only with verified sources and operational tests.

## Acceptance notes

The existing successful workflow is not proof that the full product requirements are complete. It establishes only that the current code analyzes, passes its current tests, packages a Windows installer, and launches in the CI runner. No production-readiness claim is warranted.
