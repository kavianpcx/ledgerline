import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.sha256,
  });

  final String version;
  final String downloadUrl;
  final String sha256;
}

class UpdateService {
  const UpdateService();

  static const _repository = 'kavianpcx/ledgerline';
  static const _installerName = 'ledgerline-windows-setup.exe';
  static const _allowedDownloadHosts = {
    'github.com',
    'release-assets.githubusercontent.com',
    'objects.githubusercontent.com',
  };
  static const _maximumInstallerSize = 256 * 1024 * 1024;

  static bool isVersionNewer(String candidate, String current) {
    final candidateParts = _versionParts(candidate);
    final currentParts = _versionParts(current);
    if (candidateParts == null || currentParts == null) return false;
    for (var index = 0; index < 3; index++) {
      if (candidateParts[index] != currentParts[index]) {
        return candidateParts[index] > currentParts[index];
      }
    }
    return false;
  }

  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  Future<UpdateInfo?> checkForUpdate({
    required String currentVersion,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(Uri.https('api.github.com', '/repos/' + _repository + '/releases/latest'))
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
      if (release is! Map<String, dynamic>) {
        throw const FormatException('Invalid release response.');
      }
      if (release['draft'] == true || release['prerelease'] == true) return null;

      final tag = release['tag_name'];
      if (tag is! String || !isVersionNewer(tag, currentVersion)) return null;

      final assets = release['assets'];
      if (assets is! List) throw const FormatException('Release assets are missing.');
      Map<String, dynamic>? installer;
      for (final item in assets) {
        if (item is Map<String, dynamic> && item['name'] == _installerName) {
          installer = item;
          break;
        }
      }
      if (installer == null || installer['state'] != 'uploaded') {
        throw StateError('The latest release does not include a completed Windows installer.');
      }

      final digestValue = installer['digest'];
      final digestMatch = digestValue is String
          ? RegExp(r'^sha256:([0-9a-fA-F]{64})$').firstMatch(digestValue)
          : null;
      if (digestMatch == null) {
        throw StateError('GitHub did not provide a SHA-256 digest for the installer.');
      }

      final downloadValue = installer['browser_download_url'];
      final downloadUri = downloadValue is String ? Uri.tryParse(downloadValue) : null;
      if (downloadUri == null ||
          downloadUri.scheme != 'https' ||
          downloadUri.host.toLowerCase() != 'github.com' ||
          downloadUri.userInfo.isNotEmpty ||
          (downloadUri.hasPort && downloadUri.port != 443) ||
          !downloadUri.path.startsWith('/' + _repository + '/releases/download/')) {
        throw StateError('The release installer URL is not trusted.');
      }
      return UpdateInfo(
        version: tag,
        downloadUrl: downloadUri.toString(),
        sha256: digestMatch.group(1)!.toLowerCase(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<File> downloadAndVerify(UpdateInfo update) async {
    if (_versionParts(update.version) == null) {
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

  static List<int>? _versionParts(String value) {
    final normalized = value
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first
        .split('-')
        .first;
    final parts = normalized.split('.');
    if (parts.length != 3) return null;
    final numbers = parts.map(int.tryParse).toList(growable: false);
    if (numbers.any((number) => number == null)) return null;
    return numbers.cast<int>();
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
