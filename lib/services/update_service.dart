import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.sha256,
    this.isAndroidApk = false,
  });

  final String version;
  final String downloadUrl;
  final String sha256;
  final bool isAndroidApk;
}

class UpdateService {
  const UpdateService();

  static const _repository = 'kavianpcx/ledgerline';
  static const _installerName = 'ledgerline-windows-setup.exe';
  static const _androidPackageName = 'ledgerline-android.apk';
  static const _allowedDownloadHosts = {
    'github.com',
    'release-assets.githubusercontent.com',
    'objects.githubusercontent.com',
  };
  static const _maximumInstallerSize = 512 * 1024 * 1024;

  static bool isVersionNewer(String candidate, String current) {
    final candidateVersion = _parseVersion(candidate);
    final currentVersion = _parseVersion(current);
    if (candidateVersion == null || currentVersion == null) return false;
    for (var index = 0; index < 3; index++) {
      if (candidateVersion.parts[index] != currentVersion.parts[index]) {
        return candidateVersion.parts[index] > currentVersion.parts[index];
      }
    }
    if (candidateVersion.prerelease == null) return currentVersion.prerelease != null;
    if (currentVersion.prerelease == null) return false;
    for (var index = 0; index < candidateVersion.prerelease!.length && index < currentVersion.prerelease!.length; index++) {
      final candidateIdentifier = candidateVersion.prerelease![index];
      final currentIdentifier = currentVersion.prerelease![index];
      if (candidateIdentifier == currentIdentifier) continue;
      final candidateNumber = int.tryParse(candidateIdentifier);
      final currentNumber = int.tryParse(currentIdentifier);
      if (candidateNumber != null && currentNumber != null) return candidateNumber > currentNumber;
      if (candidateNumber != null) return true;
      if (currentNumber != null) return false;
      return candidateIdentifier.compareTo(currentIdentifier) > 0;
    }
    return candidateVersion.prerelease!.length > currentVersion.prerelease!.length;
  }

  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  Future<UpdateInfo?> checkForUpdate({
    required String currentVersion,
    bool android = false,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(Uri.https('api.github.com', '/repos/' + _repository + '/releases', {'per_page': '100'}))
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Ledgerline/' + currentVersion);
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('GitHub returned HTTP ' + response.statusCode.toString());
      }
      final release = jsonDecode(
        await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 10)),
      );
      if (release is! List) throw const FormatException('Invalid release list.');
      final allowPrereleases = currentVersion.contains('-');
      Map<String, dynamic>? selectedRelease;
      Map<String, dynamic>? selectedAsset;
      String? selectedTag;
      for (final item in release) {
        if (item is! Map<String, dynamic> || item['draft'] == true) continue;
        if (item['prerelease'] == true && !allowPrereleases) continue;
        final tag = item['tag_name'];
        if (tag is! String || !isVersionNewer(tag, currentVersion)) continue;
        final assets = item['assets'];
        if (assets is! List) continue;
        final assetName = android ? _androidPackageName : _installerName;
        Map<String, dynamic>? candidateAsset;
        for (final asset in assets) {
          if (asset is Map<String, dynamic> && asset['name'] == assetName) {
            candidateAsset = asset;
            break;
          }
        }
        if (candidateAsset == null || candidateAsset['state'] != 'uploaded') continue;
        if (selectedTag == null || isVersionNewer(tag, selectedTag)) {
          selectedRelease = item;
          selectedAsset = candidateAsset;
          selectedTag = tag;
        }
      }
      if (selectedRelease == null || selectedAsset == null || selectedTag == null) return null;

      final digestValue = selectedAsset['digest'];
      final digestMatch = digestValue is String
          ? RegExp(r'^sha256:([0-9a-fA-F]{64})$').firstMatch(digestValue)
          : null;
      if (digestMatch == null) {
        throw StateError('GitHub did not provide a SHA-256 digest for the release package.');
      }

      final downloadValue = selectedAsset['browser_download_url'];
      final downloadUri = downloadValue is String ? Uri.tryParse(downloadValue) : null;
      if (downloadUri == null ||
          downloadUri.scheme != 'https' ||
          downloadUri.host.toLowerCase() != 'github.com' ||
          downloadUri.userInfo.isNotEmpty ||
          (downloadUri.hasPort && downloadUri.port != 443) ||
          !downloadUri.path.startsWith('/' + _repository + '/releases/download/')) {
        throw StateError('The release package URL is not trusted.');
      }
      return UpdateInfo(
        version: selectedTag,
        downloadUrl: downloadUri.toString(),
        sha256: digestMatch.group(1)!.toLowerCase(),
        isAndroidApk: android,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<File> downloadAndVerify(UpdateInfo update) async {
    if (update.isAndroidApk) {
      throw StateError('Android packages must be installed through Android.');
    }
    if (_parseVersion(update.version) == null) {
      throw StateError('The update version is invalid.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      var uri = Uri.parse(update.downloadUrl);
      for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
        _validateDownloadUri(uri);
        final request = await client.getUrl(uri).timeout(const Duration(seconds: 20));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'Ledgerline updater');
        final response = await request.close().timeout(const Duration(seconds: 30));
        if (_isRedirect(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null) throw StateError('The installer redirect had no target.');
          uri = uri.resolve(location);
          continue;
        }
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          throw HttpException('Installer download returned HTTP ' + response.statusCode.toString());
        }
        if (response.contentLength > _maximumInstallerSize) {
          await response.drain<void>();
          throw StateError('The installer is larger than the supported download limit.');
        }
        final bytes = await response
            .fold<List<int>>(<int>[], (buffer, chunk) {
              buffer.addAll(chunk);
              return buffer;
            })
            .timeout(const Duration(minutes: 2));
        if (bytes.length > _maximumInstallerSize) {
          throw StateError('The installer is larger than the supported download limit.');
        }
        if (sha256Hex(bytes) != update.sha256.toLowerCase()) {
          throw StateError('The downloaded installer failed SHA-256 verification.');
        }

        final temporaryDirectory = await getTemporaryDirectory();
        final installer = File(
          p.join(temporaryDirectory.path, 'ledgerline-update-' + update.version + '.exe'),
        );
        await installer.writeAsBytes(bytes, flush: true);
        return installer;
      }
      throw StateError('The installer redirected too many times.');
    } finally {
      client.close(force: true);
    }
  }

  static _ParsedVersion? _parseVersion(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    final separator = normalized.indexOf('-');
    final core = separator < 0 ? normalized : normalized.substring(0, separator);
    final prerelease = separator < 0 ? null : normalized.substring(separator + 1).split('.');
    if (prerelease != null && (prerelease.isEmpty || prerelease.any((part) => part.isEmpty))) return null;
    final parts = core.split('.').map(int.tryParse).toList(growable: false);
    if (parts.length != 3 || parts.any((part) => part == null)) return null;
    return _ParsedVersion(parts.cast<int>(), prerelease);
  }

  Future<bool> openAndroidUpdate(UpdateInfo update) async {
    if (!update.isAndroidApk) throw ArgumentError('The update is not an Android package.');
    return launchUrl(Uri.parse(update.downloadUrl), mode: LaunchMode.externalApplication);
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == 308;

  static void _validateDownloadUri(Uri uri) {
    if (uri.scheme != 'https' ||
        !_allowedDownloadHosts.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      throw StateError('The installer download redirected to an untrusted host.');
    }
  }
}

class _ParsedVersion {
  const _ParsedVersion(this.parts, this.prerelease);

  final List<int> parts;
  final List<String>? prerelease;
}
