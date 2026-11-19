import 'dart:typed_data';

const productImageMaxBytes = 512 * 1024;
const productImageMaxUploadBytes = 20 * 1024 * 1024;
const productIconKeys = <String>[
  'inventory',
  'shopping_bag',
  'restaurant',
  'beverage',
  'electronics',
  'medicine',
  'tools',
  'book',
];

class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.unitPriceCents,
    required this.unitCostCents,
    required this.stockQuantity,
    this.description = '',
    this.category = '',
    this.barcode = '',
    this.iconKey = 'inventory',
    this.imageBytes,
  });

  final String id;
  final String sku;
  final String name;
  final int unitPriceCents;
  final int unitCostCents;
  final int stockQuantity;
  final String description;
  final String category;
  final String barcode;
  final String iconKey;
  final Uint8List? imageBytes;

  factory Product.fromRow(Map<String, Object?> row) {
    final storedImage = row['image_bytes'];
    final Uint8List? imageBytes;
    if (storedImage is Uint8List) {
      imageBytes = storedImage;
    } else if (storedImage is List<int>) {
      imageBytes = Uint8List.fromList(storedImage);
    } else {
      imageBytes = null;
    }
    final storedIconKey = row['icon_key'] as String?;
    return Product(
      id: row['id']! as String,
      sku: row['sku']! as String,
      name: row['name']! as String,
      unitPriceCents: row['unit_price_cents']! as int,
      unitCostCents: row['unit_cost_cents']! as int,
      stockQuantity: row['stock_quantity']! as int,
      description: row['description'] as String? ?? '',
      category: row['category'] as String? ?? '',
      barcode: row['barcode'] as String? ?? '',
      iconKey: productIconKeys.contains(storedIconKey)
          ? storedIconKey!
          : 'inventory',
      imageBytes: imageBytes,
    );
  }
}

class ProductDraft {
  const ProductDraft({
    required this.sku,
    required this.name,
    required this.unitPriceCents,
    required this.unitCostCents,
    required this.stockQuantity,
    this.description = '',
    this.category = '',
    this.barcode = '',
    this.iconKey,
    this.imageBytes,
    this.clearImage = false,
  });

  final String sku;
  final String name;
  final int unitPriceCents;
  final int unitCostCents;
  final int stockQuantity;
  final String description;
  final String category;
  final String barcode;
  final String? iconKey;
  final Uint8List? imageBytes;
  final bool clearImage;
}

class ProductPage {
  const ProductPage({
    required this.products,
    required this.totalCount,
    required this.pageIndex,
    required this.pageSize,
  });

  final List<Product> products;
  final int totalCount;
  final int pageIndex;
  final int pageSize;

  int get pageCount => totalCount == 0 ? 1 : (totalCount + pageSize - 1) ~/ pageSize;
  int get firstItemNumber => totalCount == 0 ? 0 : pageIndex * pageSize + 1;
  int get lastItemNumber {
    final pageEnd = (pageIndex + 1) * pageSize;
    return pageEnd < totalCount ? pageEnd : totalCount;
  }
}
