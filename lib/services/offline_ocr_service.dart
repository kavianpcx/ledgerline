import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class OfflineOcrService {
  const OfflineOcrService();

  Future<String> recognizeImage(String imagePath) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Offline OCR is currently available in the Windows build.');
    }

    final applicationDirectory = p.dirname(Platform.resolvedExecutable);
    final engineDirectory = p.join(applicationDirectory, 'ocr');
    final executable = File(p.join(engineDirectory, 'tesseract.exe'));
    final tessdata = Directory(p.join(engineDirectory, 'tessdata'));
    if (!await executable.exists() || !await tessdata.exists()) {
      throw StateError('The offline OCR engine is not installed with this application.');
    }
    if (!await File(imagePath).exists()) {
      throw FileSystemException('The selected image could not be found.', imagePath);
    }

    final arguments = [
      imagePath,
      'stdout',
      '--tessdata-dir',
      tessdata.path,
      '-l',
      'eng+fas',
      '--oem',
      '1',
      '--psm',
      '3',
    ];
    final result = await Process.run(
      executable.path,
      arguments,
      workingDirectory: engineDirectory,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      runInShell: false,
    );
    if (result.exitCode != 0) {
      final detail = result.stderr.toString().trim();
      throw ProcessException(
        executable.path,
        arguments,
        detail.isEmpty ? 'OCR process failed.' : detail,
        result.exitCode,
      );
    }
    return result.stdout.toString().trim();
  }
}
