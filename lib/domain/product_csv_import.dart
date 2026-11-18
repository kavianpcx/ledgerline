import 'money.dart';
import 'product.dart';

enum ProductImportField {
  sku,
  name,
  sellingPrice,
  unitCost,
  stockQuantity,
  description,
  category,
  barcode,
}

class ProductCsvImportRow {
  const ProductCsvImportRow({
    required this.lineNumber,
    required this.draft,
    this.issue,
  });

  final int lineNumber;
  final ProductDraft? draft;
  final String? issue;

  ProductCsvImportRow withIssue(String value) =>
      ProductCsvImportRow(lineNumber: lineNumber, draft: draft, issue: value);
}

class ProductCsvImportResult {
  const ProductCsvImportResult({
    required this.headers,
    required this.mapping,
    required this.rows,
    required this.delimiter,
  });

  final List<String> headers;
  final Map<ProductImportField, int> mapping;
  final List<ProductCsvImportRow> rows;
  final String delimiter;

  int get validCount =>
      rows.where((row) => row.draft != null && row.issue == null).length;
  int get invalidCount => rows.length - validCount;
  List<ProductDraft> get validDrafts => [
        for (final row in rows)
          if (row.draft != null && row.issue == null) row.draft!,
      ];
}

class ProductCsvImport {
  const ProductCsvImport._();

  static ProductCsvImportResult parse(
    String input, {
    required String currencyCode,
    Map<ProductImportField, int>? mapping,
  }) {
    final content = input.startsWith('\uFEFF') ? input.substring(1) : input;
    final delimiter = _detectDelimiter(content);
    final records = _readCsv(content, delimiter);
    final nonEmpty = records
        .where((row) => row.values.any((value) => value.trim().isNotEmpty))
        .toList(growable: false);
    if (nonEmpty.length < 2) {
      throw const FormatException('Add a header row and at least one product row.');
    }

    final headers = nonEmpty.first.values.map((value) => value.trim()).toList();
    final activeMapping = mapping == null
        ? _suggestMapping(headers)
        : Map<ProductImportField, int>.from(mapping);
    if (activeMapping.values.any((index) => index < 0 || index >= headers.length)) {
      throw const FormatException('A mapped column is no longer available.');
    }
    if (activeMapping.values.toSet().length != activeMapping.length) {
      throw const FormatException('Each product field must use a different CSV column.');
    }
    for (final required in const [
      ProductImportField.sku,
      ProductImportField.name,
      ProductImportField.sellingPrice,
    ]) {
      if (!activeMapping.containsKey(required)) {
        throw FormatException('Map the SKU, product name, and selling price columns.');
      }
    }

    final rows = <ProductCsvImportRow>[];
    final firstSkuLine = <String, int>{};
    final firstBarcodeLine = <String, int>{};
    for (final record in nonEmpty.skip(1)) {
      final lineNumber = record.lineNumber;
      if (record.values.length > headers.length) {
        rows.add(ProductCsvImportRow(
          lineNumber: lineNumber,
          draft: null,
          issue: 'This row has more values than the header row.',
        ));
        continue;
      }

      String value(ProductImportField field) {
        final column = activeMapping[field];
        if (column == null || column >= record.values.length) return '';
        return record.values[column].trim();
      }

      final sku = value(ProductImportField.sku).toUpperCase();
      final name = value(ProductImportField.name);
      final price = _parseAmount(
        value(ProductImportField.sellingPrice),
        currencyCode,
      );
      final rawCost = value(ProductImportField.unitCost);
      final cost = rawCost.isEmpty ? 0 : _parseAmount(rawCost, currencyCode);
      final rawStock = value(ProductImportField.stockQuantity);
      final stock = rawStock.isEmpty ? 0 : _parseQuantity(rawStock);
      final barcode = value(ProductImportField.barcode);
      final issues = <String>[];

      if (sku.isEmpty) issues.add('SKU is required.');
      if (name.isEmpty) issues.add('Product name is required.');
      if (price == null || price <= 0) issues.add('Selling price is invalid.');
      if (cost == null || cost < 0) issues.add('Unit cost is invalid.');
      if (stock == null || stock < 0) issues.add('Stock quantity is invalid.');
      if (barcode.contains(RegExp(r'\s'))) issues.add('Barcode cannot contain spaces.');

      ProductDraft? draft;
      if (issues.isEmpty) {
        draft = ProductDraft(
          sku: sku,
          name: name,
          unitPriceCents: price!,
          unitCostCents: cost!,
          stockQuantity: stock!,
          description: value(ProductImportField.description),
          category: value(ProductImportField.category),
          barcode: barcode,
        );
      }

      final rowIndex = rows.length;
      if (draft != null) {
        final previousSku = firstSkuLine[sku];
        if (previousSku != null) {
          const issue = 'SKU is duplicated in this file.';
          rows[previousSku] = rows[previousSku].withIssue(issue);
          issues.add(issue);
        } else {
          firstSkuLine[sku] = rowIndex;
        }

        if (barcode.isNotEmpty) {
          final previousBarcode = firstBarcodeLine[barcode];
          if (previousBarcode != null) {
            const issue = 'Barcode is duplicated in this file.';
            rows[previousBarcode] = rows[previousBarcode].withIssue(issue);
            issues.add(issue);
          } else {
            firstBarcodeLine[barcode] = rowIndex;
          }
        }
      }
      rows.add(ProductCsvImportRow(
        lineNumber: lineNumber,
        draft: draft,
        issue: issues.isEmpty ? null : issues.join(' '),
      ));
    }

    if (rows.isEmpty) {
      throw const FormatException('No product rows were found.');
    }
    return ProductCsvImportResult(
      headers: List.unmodifiable(headers),
      mapping: Map.unmodifiable(activeMapping),
      rows: List.unmodifiable(rows),
      delimiter: delimiter,
    );
  }

  static Map<ProductImportField, int> _suggestMapping(List<String> headers) {
    const aliases = <ProductImportField, Set<String>>{
      ProductImportField.sku: {
        'sku', 'productsku', 'itemsku', 'productcode', 'itemcode', 'code',
        'کدکالا', 'شناسهکالا', 'کدمحصول',
      },
      ProductImportField.name: {
        'name', 'productname', 'itemname', 'کالانام', 'نامکالا', 'ناممحصول',
      },
      ProductImportField.sellingPrice: {
        'sellingprice', 'saleprice', 'unitprice', 'retailprice', 'price',
        'قیمتفروش', 'قیمتواحد', 'قیمت',
      },
      ProductImportField.unitCost: {
        'unitcost', 'cost', 'purchaseprice', 'buyingprice', 'بهایواحد',
        'بهایتمامشده', 'قیمتخرید',
      },
      ProductImportField.stockQuantity: {
        'stock', 'quantity', 'qty', 'openingstock', 'stockquantity',
        'موجودی', 'تعداد', 'موجودیابتدایی',
      },
      ProductImportField.description: {
        'description', 'details', 'توضیحات', 'شرح',
      },
      ProductImportField.category: {
        'category', 'group', 'دسته', 'دستهبندی',
      },
      ProductImportField.barcode: {
        'barcode', 'ean', 'upc', 'بارکد',
      },
    };
    final result = <ProductImportField, int>{};
    for (var column = 0; column < headers.length; column++) {
      final normalized = _normalizeHeader(headers[column]);
      for (final field in ProductImportField.values) {
        if (!result.containsKey(field) &&
            aliases[field]!.contains(normalized)) {
          result[field] = column;
          break;
        }
      }
    }
    return result;
  }

  static String _normalizeHeader(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]'), '');

  static int? _parseAmount(String raw, String currencyCode) {
    var value = raw.trim();
    final upper = value.toUpperCase();
    value = upper
        .replaceAll(currencyCode.toUpperCase(), '')
        .replaceAll('\$', '')
        .replaceAll('€', '')
        .replaceAll('£', '')
        .replaceAll('﷼', '')
        .replaceAll('تومان', '')
        .replaceAll('ریال', '')
        .trim();
    return CurrencyDefinition.parseMinorUnits(value, currencyCode: currencyCode);
  }

  static int? _parseQuantity(String raw) {
    var value = raw.trim().replaceAll(RegExp(r'\s+'), '');
    value = value.replaceAllMapped(
      RegExp('[\u0660-\u0669\u06F0-\u06F9]'),
      (match) {
        final code = match.group(0)!.codeUnitAt(0);
        final zero = code <= 0x0669 ? 0x0660 : 0x06F0;
        return String.fromCharCode(0x30 + code - zero);
      },
    );
    if (RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(value)) {
      value = value.replaceAll(',', '');
    }
    return RegExp(r'^\d+$').hasMatch(value) ? int.tryParse(value) : null;
  }

  static String _detectDelimiter(String input) {
    const candidates = [',', ';', '\t'];
    final counts = <String, int>{for (final value in candidates) value: 0};
    var quoted = false;
    for (var index = 0; index < input.length; index++) {
      final character = input[index];
      if (character == '"') {
        if (quoted && index + 1 < input.length && input[index + 1] == '"') {
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && counts.containsKey(character)) {
        counts[character] = counts[character]! + 1;
      }
    }
    var selected = ',';
    for (final candidate in candidates.skip(1)) {
      if (counts[candidate]! > counts[selected]!) selected = candidate;
    }
    return selected;
  }

  static List<_CsvRecord> _readCsv(String input, String delimiter) {
    final result = <_CsvRecord>[];
    final row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    var quoteClosed = false;
    var lineNumber = 1;
    var rowStartLine = 1;

    void finishField() {
      row.add(field.toString().trim());
      field.clear();
      quoteClosed = false;
    }

    void finishRow() {
      finishField();
      result.add(_CsvRecord(List.unmodifiable(row), rowStartLine));
      row.clear();
    }

    for (var index = 0; index < input.length; index++) {
      final character = input[index];
      if (quoted) {
        if (character == '"') {
          if (index + 1 < input.length && input[index + 1] == '"') {
            field.write('"');
            index++;
          } else {
            quoted = false;
            quoteClosed = true;
          }
        } else {
          if (character == '\r') {
            if (index + 1 < input.length && input[index + 1] == '\n') index++;
            field.write('\n');
            lineNumber++;
          } else if (character == '\n') {
            field.write('\n');
            lineNumber++;
          } else {
            field.write(character);
          }
        }
        continue;
      }

      if (character == '"' && field.toString().trim().isEmpty && !quoteClosed) {
        field.clear();
        quoted = true;
      } else if (character == delimiter) {
        finishField();
      } else if (character == '\n' || character == '\r') {
        finishRow();
        if (character == '\r' &&
            index + 1 < input.length &&
            input[index + 1] == '\n') {
          index++;
        }
        lineNumber++;
        rowStartLine = lineNumber;
      } else if (quoteClosed && character.trim().isNotEmpty) {
        throw FormatException(
          'Unexpected text after a quoted field on line ' + lineNumber.toString() + '.',
        );
      } else if (character == '"' && field.toString().trim().isNotEmpty) {
        throw FormatException(
          'Unexpected quote in an unquoted field on line ' + lineNumber.toString() + '.',
        );
      } else if (!quoteClosed) {
        field.write(character);
      }
    }

    if (quoted) {
      throw FormatException('A quoted field was not closed on line ' + rowStartLine.toString() + '.');
    }
    if (field.length > 0 || row.isNotEmpty || quoteClosed) finishRow();
    return result;
  }
}

class _CsvRecord {
  const _CsvRecord(this.values, this.lineNumber);

  final List<String> values;
  final int lineNumber;
}
