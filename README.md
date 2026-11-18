# Ledgerline

Ledgerline is an offline-first accounting and business-management application in active development for Windows 10/11 and Android. The product target includes bookkeeping, retail POS, restaurant orders, inventory, document import, and optional secure device synchronization. The current verified release is Windows-only; the Android application and most advanced workflows are not yet implemented.

The complete product requirements are in [docs/PRODUCT_SPECIFICATION.md](docs/PRODUCT_SPECIFICATION.md). The current code and risks are assessed in [docs/PRODUCT_AUDIT.md](docs/PRODUCT_AUDIT.md).

## Current verified functionality

The existing Windows release provides:

- Local SQLite storage for accounts, journal entries/lines, products, invoices, invoice lines, invoice payments, and settings.
- Integer minor-unit amounts and balanced journal posting for supported entries, inventory opening, sales, and invoice payments.
- Dashboard, chart of accounts, journal, limited financial summaries, basic product/inventory screens, sales invoices, and partial invoice receipts.
- English and Persian RTL, light/dark themes, persisted preferences, and a bounded searchable currency/language selector.
- CSV import and local English/Persian Tesseract OCR that returns editable text for review.
- SQLite backup export and integrity-checked restore with the previous database retained as a recovery copy.
- A custom Windows caption area, keyboard shortcuts, Windows installer, and GitHub Actions build/test workflow.

The left Windows sidebar repair is in active development on [PR #2](https://github.com/kavianpcx/ledgerline/pull/2). Its Windows build, narrow-window screenshots, and test run must complete before that change is treated as verified.

## Current limitations

The current published build is a basic single-device Windows ledger. It is not production-ready and does not provide Android builds, secure roles/authentication, multi-device synchronization, complete multi-currency accounting, restaurant table/kitchen workflows, full retail POS, warehouse movement accounting, structured XLSX/DOCX/PDF import, encrypted backups, payroll/tax rules, market data, or a complete updater. See the product audit for financial and security risks. The absence of a feature from the current build is not a change to the product target.

## Install the verified Windows release

Download the current Windows installer from [GitHub Releases](https://github.com/kavianpcx/ledgerline/releases), run it, then launch Ledgerline from the Start menu or desktop shortcut. The installer is per-user and does not require administrator privileges. Do not use this link as evidence that the in-progress sidebar repair or Android artifacts are released.

## Build and verify

Use Flutter stable and Visual Studio 2022 with the Desktop development with C++ workload for Windows. CI uses GitHub-hosted Windows and Ubuntu runners. From the repository root:

```powershell
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter run -d windows
flutter build windows --release
```

The Windows Actions workflow builds and packages the Windows application, runs automated checks, and captures UI evidence. Android packaging and device-camera acceptance tests are not currently available.

## Local data, OCR, and updates

Ledgerline stores its SQLite database in the operating system's application-support directory. Supported local business data remains on the device. Smart Import currently supports CSV plus offline image-to-text OCR; extracted text must be reviewed and is not automatically posted to accounting.

The partial update flow checks public GitHub Releases and validates the published asset digest before offering the installer. It is not a complete standalone updater: signed publisher verification, download progress/cancellation, install progress, rollback, and full recovery are not implemented.

Backups in the current release are not encrypted. Current installer packages are not Authenticode-signed. Do not store highly sensitive production data in this build.

## Development status

This repository is an evolving product. Feature work should preserve accounting history, use safe versioned schema migrations, and include tests for financial behavior. CI success is evidence only for the code paths exercised by that run. Release notes must identify actual artifacts and distinguish CI/emulator evidence from tests on Windows or physical Android hardware.

## License

No source license has been selected in the repository. Until a license is added, redistribution permissions are not granted.
