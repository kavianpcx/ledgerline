# Ledgerline

Ledgerline is an offline-first accounting and business-management application in active development for Windows 10/11 and Android phones and tablets. The product target includes bookkeeping, retail POS, restaurant orders, inventory, document import, and optional secure device synchronization. The latest published build is a Windows-only prerelease. No Android build is available yet.

The complete product requirements are in [docs/PRODUCT_SPECIFICATION.md](docs/PRODUCT_SPECIFICATION.md). The current code status, evidence, and risks are assessed in [docs/PRODUCT_AUDIT.md](docs/PRODUCT_AUDIT.md).

## Verified Windows prerelease

The tagged v0.5.1-beta.1 Windows prerelease provides a basic single-device ledger with the following features. It predates the current `main` branch's product CSV importer and is not a POS release:

- Local SQLite storage for accounts, journal entries and lines, products, invoices, invoice lines, invoice payments, and application settings.
- Integer arithmetic for recorded amounts and balanced journal posting for supported entries, inventory opening, sales, and invoice payments. Current reports are limited.
- A dashboard, chart of accounts, journal, basic product/inventory screen, sales invoices, and partial invoice receipt workflow.
- English and Persian RTL, light and dark themes, persisted preferences, and a bounded searchable currency selector. Currency selection in this release is not full multi-currency accounting or an exchange-rate conversion.
- Journal CSV import and offline English/Persian Tesseract OCR that extracts editable text. Product-catalog CSV mapping and transactional opening-inventory posting are now merged into `main`; OCR still extracts text only and does not classify documents or create records automatically.
- SQLite backup export and integrity-checked restore, keeping a recovery copy of the prior database.
- An integrated Windows caption area, keyboard shortcuts, per-user installer, and GitHub Actions build/test workflow.

PR [#2](https://github.com/kavianpcx/ledgerline/pull/2) restored permanent left-side Windows navigation at wide, medium, and narrow widths. The successful [PR workflow](https://github.com/kavianpcx/ledgerline/actions/runs/44306432838) built and smoke-installed the installer, ran the test matrix, and captured Windows sidebar and settings scenarios. The screenshots are retained as CI artifacts; they have not been manually pixel-reviewed in this workspace. High-DPI and Windows Snap behavior have not been separately verified.

## Current source and development work

Currency-safety PR [#3](https://github.com/kavianpcx/ledgerline/pull/3) is merged into `main`. Product-catalog PR [#4](https://github.com/kavianpcx/ledgerline/pull/4) and CSV import PR [#5](https://github.com/kavianpcx/ledgerline/pull/5) are also merged. Current `main` is `ab615a02f369155fbd5ad44ab170f0a3c7c4005a`; its successful post-merge build and test workflow is [run 44371927172](https://github.com/kavianpcx/ledgerline/actions/runs/44371927172). The successful [CI run](https://github.com/kavianpcx/ledgerline/actions/runs/44326912497) passed analysis, all eight test files, Windows packaging and installer smoke checks, and captured eight Windows UI scenarios. Its workflow artifact includes the installer and screenshots. The screenshots have not been manually pixel-reviewed in this workspace. The source changes require a confirmed base currency before monetary writes, handle minor units with integer arithmetic, confirm the interpretation of legacy amounts, and lock the base currency once records exist. These source changes are not included in the published v0.5.1-beta.1 installer. There is still no mixed-currency accounting or exchange-rate conversion.

PR #4 added schema v4 and the indexed, editable, paginated product catalog. Its successful [PR workflow](https://github.com/kavianpcx/ledgerline/actions/runs/44336060124) passed analysis, all eight test files, Windows packaging and installer smoke checks, and scripted UI capture. Main now uses schema v4 with catalog search, sorting, pagination, product editing, history-preserving invoice snapshots, and inventory valuation adjustments. The Windows build for the merge commit runs separately on push to `main`.

PR #5 added structured product CSV parsing, reviewable column mapping/preview, duplicate detection, and atomic product plus opening-inventory posting. These source changes pass CI but are not included in the older tagged Windows installer. The active `feature/pos-checkout` branch adds a database-paginated checkout screen with cart persistence, stale price/stock revalidation, and an atomic invoice plus optional full cash or bank-transfer receipt to the matching asset account. It now also records append-only, paginated stock history for opening stock, CSV imports, adjustments, and sales. Existing stock is represented as one labeled migration balance; prior movements cannot be reconstructed. The previous branch head passed all checks; GitHub Actions on PR #6 is the verification gate for new commits.

## Known limitations

Ledgerline is not production-ready. The Android application, secure roles and authentication, multi-device synchronization, complete multi-currency accounting, restaurant table/kitchen workflows, full retail POS, multi-warehouse purchasing/transfers/returns, XLSX/DOCX/PDF import, encrypted backups, payroll/tax rules, market data, and a complete updater remain unfinished. The active POS branch is not part of a published release. The product requirements stay active; see the audit for risks and implementation status.

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
