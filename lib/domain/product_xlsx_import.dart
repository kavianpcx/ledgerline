import 'package:excel/excel.dart';

/// Converts the first populated worksheet into CSV for the reviewed catalog flow.
class ProductXlsxImport {
  const ProductXlsxImport._();

  static const maxFileBytes = 20 * 1024 * 1024;
  static const maxDataRows = 10000;
  static const maxColumns = 64;

  static String toCsv(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('The selected workbook is empty.');
    }
    if (bytes.length > maxFileBytes) {
      throw const FormatException('The XLSX file exceeds the 20 MiB import limit.');
    }

    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } on Object {
      throw const FormatException('The selected file is not a readable XLSX workbook.');
    }

    Sheet? selected;
    for (final sheet in workbook.tables.values) {
      if (sheet.rows.any(
        (row) => row.any((cell) => _cellText(cell).trim().isNotEmpty),
      )) {
        selected = sheet;
        break;
      }
    }
    if (selected == null) {
      throw const FormatException('The workbook does not contain a populated worksheet.');
    }
    if (selected.maxRows > maxDataRows + 100) {
      throw const FormatException('The worksheet exceeds the 10,000 product row import limit.');
    }

    final rows = <List<String>>[];
    for (final row in selected.rows) {
      final values = row.map(_cellText).toList(growable: true);
      while (values.isNotEmpty && values.last.trim().isEmpty) {
        values.removeLast();
      }
      if (values.isEmpty || values.every((value) => value.trim().isEmpty)) {
        continue;
      }
      if (values.length > maxColumns) {
        throw const FormatException('The worksheet exceeds the 64 column import limit.');
      }
      rows.add(values);
      if (rows.length > maxDataRows + 1) {
        throw const FormatException('The worksheet exceeds the 10,000 product row import limit.');
      }
    }

    if (rows.length < 2) {
      throw const FormatException('The worksheet needs a header and at least one product row.');
    }
    return rows
        .map((row) => row.map(_encodeCsvField).join(','))
        .join('\r\n');
  }

  static String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    return switch (value) {
      TextCellValue(:final value) => value.toString(),
      IntCellValue(:final value) => value.toString(),
      DoubleCellValue(:final value) => value.toString(),
      BoolCellValue(:final value) => value ? 'true' : 'false',
      DateCellValue() => value.asDateTimeLocal().toIso8601String().substring(0, 10),
      DateTimeCellValue() => value.asDateTimeLocal().toIso8601String(),
      TimeCellValue() => value.asDuration().toString(),
      FormulaCellValue() => throw const FormatException(
          'Formula cells are not imported. Replace them with calculated values first.',
        ),
    };
  }

  static String _encodeCsvField(String value) =>
      '"${value.replaceAll('"', '""')}"';
}
