# Ledgerline

Ledgerline is an offline-first accounting and store-management app for Windows and Android. The current prerelease target is **0.7.0-beta.1**. It is a single-device product; local business data stays on the device and no online account is required.

The product requirements are in [docs/PRODUCT_SPECIFICATION.md](docs/PRODUCT_SPECIFICATION.md). Current implementation and test limits are in [docs/PRODUCT_AUDIT.md](docs/PRODUCT_AUDIT.md).

## What is in this build

- First-run setup for business name, type, country, language, and base accounting currency. Existing ledger amounts require explicit currency confirmation and are never converted by setup.
- Double-entry bookkeeping, products and inventory, reviewed CSV/XLSX product import, sales invoices, POS checkout, receipts, returns, and local SQLite backups.
- A More Tools hub with a Windows-style calculator, currency quotes/converter, and a Smart Import shortcut. The calculator supports keyboard entry and memory controls.
- Tehran free-market currency quotes from [NerkhAra](https://nerkhara.com/en/api/), displayed with their source time and stale state. These indicative rates are not Central Bank rates or offers to trade. Conversion is for reference and does not post foreign-currency accounting transactions.
- Android camera barcode scanning in a compact dialog while adding or editing a product. Windows POS continues to accept USB/Bluetooth keyboard-wedge barcode scanners.
- Optional 6–12 digit app passcode during first-run setup or later in Security settings. Android can use enrolled fingerprint/face authentication as an unlock shortcut.
- Windows installer updates with SHA-256 checking. Android update downloads open through Android so installation remains under the user's approval.
- English and Persian layouts, local storage, light/dark themes, and a MIT license.

![Ledgerline More Tools screen](https://github.com/kavianpcx/ledgerline/releases/download/v0.7.0-beta.1/more-tools.png)

Smart Import currently supports reviewed CSV/XLSX product catalogs and offline image-to-text OCR. OCR does not classify documents or automatically create accounting records. PowerPoint, DOCX, and structured PDF import are not supported yet.

## Download

The [GitHub Releases page](https://github.com/kavianpcx/ledgerline/releases) provides the Windows installer and Android APK when the prerelease workflow succeeds. The release includes Windows UI screenshots. The APK is a universal Android build; Android camera scanning and installation still need physical-device acceptance testing.

This is a beta milestone, not production-ready accounting software. The passcode locks the app screen but does not encrypt the database or backups; a person with access to the device files can still read local data. There is no user/role system, synchronization, or verified payment-terminal integration. Do not use it for sensitive or mission-critical records without your own backup and review process.

## Build and verify

Install Flutter stable. The repository generates the native runners during CI; to build locally, generate the platform you need once:

```sh
flutter create --platforms=windows,android --project-name=ledgerline --org=com.ledgerline .
flutter pub get
flutter analyze
flutter test --reporter expanded
```

Build Windows with Visual Studio 2022 and the Desktop development with C++ workload:

```sh
flutter build windows --release
```

Build Android with the Android SDK and Java toolchain installed:

```sh
python3 tool/patch_android_manifest.py
flutter build apk --release
```

GitHub Actions runs analysis, the test matrix, a Windows installer smoke test, an Android APK build, and Windows UI captures. A green CI run does not replace hardware testing.

## Data, exchange rates, and hardware

The SQLite database lives in the operating system's application-support directory. The accounting ledger has one base currency. Market-rate conversion is display-only; it does not change stored balances. NerkhAra says its feed is rebuilt about every ten minutes and requires visible attribution and rate timestamps. Its rates are Tehran free-market readings, not official CBI rates or trade quotes.

The POS supports cash, bank transfer, and on-account sales. A real card-terminal integration depends on the terminal model, payment provider, and an authorized protocol; Ledgerline does not simulate a terminal approval. Printer hardware output, Android camera behavior, and Android install/update flows have not yet been verified on physical devices.

Backups are not encrypted, and Windows packages are not Authenticode-signed. The app passcode is an on-device screen lock, not full-disk or database encryption. The public CI Android APK also lacks a persistent private release key; Android may reject an in-place upgrade when a later APK has a different signing key. A maintainer must configure a private keystore in GitHub Actions before relying on Android in-app upgrades. Review the audit before relying on the app for important records.

## License

Ledgerline source code is distributed under the [MIT License](LICENSE). The bundled Noto Arabic font remains under its separate [SIL Open Font License](assets/fonts/OFL.txt).
