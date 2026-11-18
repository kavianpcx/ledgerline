# Ledgerline

Ledgerline is a Windows-first accounting desktop application. It stores the books in a local SQLite database and validates journal transactions with double-entry accounting.

## Implemented

- Dashboard, chart of accounts, journal, income statement, and balance summary.
- Balanced journal entries saved in atomic SQLite transactions.
- Product catalog and stock tracking. Sales invoices post receivables, revenue, tax, cost of goods sold, and inventory together; partial payments post balanced cash and receivable entries.
- English by default, Persian with right-to-left layout, and persisted light/dark themes.
- A unified Windows caption integrated into the app header, with drag and resize support plus minimize, maximize, restore, and close controls.
- A reusable searchable select used across the app. Its popup is bounded, scrollable, keyboard-operable, theme-aware, and RTL-aware.
- Settings control center for general/onboarding, business information, appearance, language and region, currency, accounting, sales/POS navigation, inventory navigation, Smart Import, backup/restore, and updates.
- Smart Import with CSV preview/import and bundled offline Tesseract OCR for English and Persian.
- Database backup export and validated restore with a retained recovery copy.
- Windows installer and GitHub Releases built by GitHub Actions.

## Install

Download `ledgerline-windows-setup.exe` from the [Releases page](https://github.com/kavianpcx/ledgerline/releases), run it, then launch Ledgerline from the Start menu or desktop shortcut. The installer is per-user and does not require administrator privileges.

## Build and verify

Use Flutter stable and Visual Studio 2022 with the Desktop development with C++ workload. From the repository root:

```powershell
flutter create --platforms=windows --project-name=ledgerline --org=com.ledgerline .
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter run -d windows
flutter build windows --release --dart-define=APP_VERSION=0.5.0
```

GitHub Actions runs analysis and the test suite on Ubuntu, then builds and smoke-installs the Windows installer on a Windows runner. The Windows job bundles Tesseract, pinned English/Persian models, and their license files; it also runs an OCR recognition smoke test. The runner launches the app in titlebar, light settings, dark settings, Persian RTL settings, and open currency-selector scenarios and uploads screenshots as a workflow artifact and release assets.

This repository intentionally does not build Android.

## Offline Smart Import OCR

Choose an image in Smart Import and Ledgerline runs the bundled Tesseract engine locally with English and Persian language data. It displays editable recognized text. Nothing is posted to the ledger until you review and import it. OCR requires no network connection after installation.

## Local data and privacy

The SQLite database is stored in the operating system's application-support directory. Journal entries, products, invoices, and preferences remain on the device. The release updater contacts GitHub to check for a newer public release and download an installer after the user chooses to do so.

## Backups

Settings can export the local SQLite database or restore a Ledgerline backup. Before replacing the active books, Ledgerline checks database integrity, required tables, foreign-key references, and journal balance. After a successful restore, the previous database is retained beside the active database as a timestamped recovery file; the app shows its path. Restoring replaces the current ledger, products, invoices, and settings. Backups are not encrypted in this release.

## Updates

Release builds check GitHub Releases and validate the official asset URL and published SHA-256 digest before prompting to open the installer. The app requests a graceful window close before launching the installer. Current releases are not Authenticode-signed, so Windows cannot verify publisher identity. A standalone updater, download progress, cancel/resume, install progress, rollback, and recovery flow are not implemented yet.

## Known gaps

This release does not yet include PIN/password authentication, Windows Hello, auto-lock, encrypted backups, or credential storage. It also does not yet provide paginated/resizable data tables, large-dataset performance verification, payment-terminal integrations, full POS workflows, printing, tax/payroll, user permissions, notification controls, advanced settings, or managed exchange rates and warehouses. These remain follow-up work; the current settings page does not present them as working controls.

The accessible conversation did not include a separate `SPEC.md` or the full original MASTER PROMPT. The requirements visible in the conversation are recorded in [`docs/PRODUCT_SPECIFICATION.md`](docs/PRODUCT_SPECIFICATION.md). Unprovided details remain unresolved and have not been inferred.

## License

No project source license has been selected yet. Do not redistribute the source code unless the owner selects a license.
