# Ledgerline

Ledgerline is a Windows-first accounting desktop application. It stores the books in a local SQLite database and validates journal transactions with double-entry accounting.

## Current capabilities

- Dashboard, chart of accounts, journal, income statement, and balance summary.
- Balanced journal entries saved in atomic SQLite transactions.
- Product catalog, stock tracking, and sales invoices that post receivables, revenue, tax, cost of goods sold, and inventory together.
- English by default, Persian with right-to-left layout, and persisted light/dark themes.
- Smart Import with CSV preview/import and bundled offline Tesseract OCR for English and Persian.
- Database backup export and validated restore with a retained recovery copy.
- Windows installer and GitHub Releases built by GitHub Actions.

## Install

Download `ledgerline-windows-setup.exe` from the [Releases page](https://github.com/kavianpcx/ledgerline/releases), run it, then launch Ledgerline from the Start menu or desktop shortcut. The installer is per-user and does not require administrator privileges.

## Build and test

Use Flutter stable and Visual Studio 2022 with the Desktop development with C++ workload. From the repository root:

```powershell
flutter create --platforms=windows --project-name=ledgerline --org=com.ledgerline .
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter run -d windows
flutter build windows --release --dart-define=APP_VERSION=0.3.1
```

GitHub Actions runs analysis and tests on Ubuntu and builds the Windows release on `windows-latest`. The Windows job bundles Tesseract, pinned English/Persian models, their license files, and the installer. This repository intentionally does not build Android.

## Offline Smart Import OCR

Choose an image in Smart Import and Ledgerline runs the bundled Tesseract engine locally with English and Persian language data. It displays editable recognized text. Nothing is posted to the ledger until you review and import it. OCR requires no network connection after installation. The Windows release workflow also runs a recognition smoke test against a generated sample receipt.

## Local data and privacy

The SQLite database is stored in the operating system's application-support directory. Journal entries, products, invoices, and preferences remain on the device. The release updater contacts GitHub only to check for a newer public release and download an installer after the user chooses to do so.

## Backups

Settings can export the local SQLite database or restore a Ledgerline backup. Before replacing the active books, Ledgerline checks the database integrity, required tables, foreign-key references, and journal balance. After a successful restore, the previous database is retained beside the active database as a timestamped recovery file; the app shows its path. Restoring replaces the current ledger, products, invoices, and settings.

## Updates

Release builds check GitHub Releases in the background. The updater verifies the official release asset URL, follows HTTPS redirects only to GitHub release hosts, and compares the complete installer against GitHub's published SHA-256 digest. It asks before opening the installer and shows the digest for review. Current releases are not Authenticode-signed, so Windows cannot verify the publisher identity.

## Scope and limitations

The accessible conversation did not include a full separate MASTER PROMPT or `SPEC.md`. The visible requirements are recorded in [`docs/PRODUCT_SPECIFICATION.md`](docs/PRODUCT_SPECIFICATION.md); additional detailed requirements remain unresolved and should not be inferred from this initial app.

## License

No project source license has been selected yet. Do not redistribute the source code unless the owner selects a license.
