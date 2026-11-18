# Ledgerline

Ledgerline is an offline-first accounting and business-management application in active development for Windows 10/11 and Android phones and tablets. The product target includes bookkeeping, retail POS, restaurant orders, inventory, document import, and optional secure device synchronization. The latest published build is a Windows-only prerelease. No Android build is available yet.

The complete product requirements are in [docs/PRODUCT_SPECIFICATION.md](docs/PRODUCT_SPECIFICATION.md). The current code status, evidence, and risks are assessed in [docs/PRODUCT_AUDIT.md](docs/PRODUCT_AUDIT.md).

## Verified Windows prerelease

The current v0.5.1-beta.1 release provides a basic single-device Windows ledger with:

- Local SQLite storage for accounts, journal entries and lines, products, invoices, invoice lines, invoice payments, and application settings.
- Integer arithmetic for recorded amounts and balanced journal posting for supported entries, inventory opening, sales, and invoice payments. Current reports are limited.
- A dashboard, chart of accounts, journal, basic product/inventory screen, sales invoices, and partial invoice receipt workflow.
- English and Persian RTL, light and dark themes, persisted preferences, and a bounded searchable currency selector. Currency selection in this release is not full multi-currency accounting or an exchange-rate conversion.
- Journal CSV import and offline English/Persian Tesseract OCR that extracts editable text. The current source branch adds a separate product-catalog CSV preview with detected column mapping and transactional inventory posting; OCR does not yet classify documents or create records automatically.
- SQLite backup export and integrity-checked restore, keeping a recovery copy of the prior database.
- An integrated Windows caption area, keyboard shortcuts, per-user installer, and GitHub Actions build/test workflow.

PR [#2](https://github.com/kavianpcx/ledgerline/pull/2) restored permanent left-side Windows navigation at wide, medium, and narrow widths. The successful [PR workflow](https://github.com/kavianpcx/ledgerline/actions/runs/44306432838) built and smoke-installed the installer, ran the test matrix, and captured Windows sidebar and settings scenarios. The screenshots are retained as CI artifacts; they have not been manually pixel-reviewed in this workspace. High-DPI and Windows Snap behavior have not been separately verified.

## Current source and development work

Currency-safety PR [#3](https://github.com/kavianpcx/ledgerline/pull/3) is merged into `main` at `2f444d3e2e81aa927a42bba4fd272bc1900bbeb7`. The successful [CI run](https://github.com/kavianpcx/ledgerline/actions/runs/44326912497) passed analysis, all eight test files, Windows packaging and installer smoke checks, and captured eight Windows UI scenarios. Its workflow artifact includes the installer and screenshots. The screenshots have not been manually pixel-reviewed in this workspace. The source changes require a confirmed base currency before monetary writes, handle minor units with integer arithmetic, confirm the interpretation of legacy amounts, and lock the base currency once records exist. These source changes are not included in the published v0.5.1-beta.1 installer. There is still no mixed-currency accounting or exchange-rate conversion.

Product-catalog PR [#4](https://github.com/kavianpcx/ledgerline/pull/4) is merged into `main` at `bf9d2ed1c821e648360521a69700073bd360f15a`. Its successful [PR workflow](https://github.com/kavianpcx/ledgerline/actions/runs/44336060124) passed analysis, all eight test files, Windows packaging and installer smoke checks, and scripted UI capture. Main now uses schema v4 with catalog search, sorting, pagination, product editing, history-preserving invoice snapshots, and inventory valuation adjustments. The Windows build for the merge commit runs separately on push to `main`.

The next source branch, `feature/csv-product-import`, adds structured product CSV parsing, a reviewable column mapping/preview, duplicate detection, and atomic product plus opening-inventory posting. This implementation is not part of the published Windows release and remains subject to CI.

## Known limitations

Ledgerline is not production-ready. The Android application, secure roles and authentication, multi-device synchronization, complete multi-currency accounting, restaurant table/kitchen workflows, full retail POS, warehouse movement accounting, XLSX/DOCX/PDF import, encrypted backups, payroll/tax rules, market data, and a complete updater remain unfinished. The product requirements stay active; see the audit for risks and implementation status.

## Install the verified Windows release

Download the Windows prerelease from [GitHub Releases](https://github.com/kavianpcx/ledgerline/releases), run the installer, then launch Ledgerline from the Start menu or desktop shortcut. The per-user installer does not require administrator privileges. The release page does not contain an Android APK.

## Build and verify

Use Flutter stable and Visual Studio 2022 with the Desktop development with C++ workload to build Windows locally. CI uses GitHub-hosted Windows and Ubuntu runners. From the repository root:

```powershell
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter run -d windows
flutter build windows --release
```

The Windows Actions workflow builds and packages the application, runs automated checks, and captures UI evidence. Android packaging and physical-device camera acceptance tests are not available yet.

## Local data, OCR, and updates

Ledgerline stores its SQLite database in the operating system's application-support directory. Local business data remains on the device. Smart Import currently supports CSV plus offline image-to-text OCR; extracted text requires user review and is not automatically posted to the ledger.

The update flow can discover GitHub Releases and check the published asset digest before offering the installer. It is not a complete standalone updater: publisher signature verification, genuine download progress and cancellation, install progress, rollback, and an older-to-newer end-to-end test are not implemented.

Backups in the published release are not encrypted, and installer packages are not Authenticode-signed. Do not use this prerelease for highly sensitive production data.

## Development status

This repository is evolving. Changes should preserve accounting history, use tested database migrations, and include automated coverage for financial behavior. A green workflow proves only the code paths exercised by that run. Release notes must identify actual artifacts and distinguish CI and emulator evidence from physical-device tests.

## License

No source license has been selected in the repository. Until a license is added, redistribution permissions are not granted.
