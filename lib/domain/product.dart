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

  factory Product.fromRow(Map<String, Object?> row) => Product(
        id: row['id']! as String,
        sku: row['sku']! as String,
        name: row['name']! as String,
        unitPriceCents: row['unit_price_cents']! as int,
        unitCostCents: row['unit_cost_cents']! as int,
        stockQuantity: row['stock_quantity']! as int,
        description: row['description'] as String? ?? '',
        category: row['category'] as String? ?? '',
        barcode: row['barcode'] as String? ?? '',
      );
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
  });

  final String sku;
  final String name;
  final int unitPriceCents;
  final int unitCostCents;
  final int stockQuantity;
  final String description;
  final String category;
  final String barcode;
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
