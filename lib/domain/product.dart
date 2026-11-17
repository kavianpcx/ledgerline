class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.unitPriceCents,
    required this.unitCostCents,
    required this.stockQuantity,
  });

  final String id;
  final String sku;
  final String name;
  final int unitPriceCents;
  final int unitCostCents;
  final int stockQuantity;

  factory Product.fromRow(Map<String, Object?> row) => Product(
        id: row['id']! as String,
        sku: row['sku']! as String,
        name: row['name']! as String,
        unitPriceCents: row['unit_price_cents']! as int,
        unitCostCents: row['unit_cost_cents']! as int,
        stockQuantity: row['stock_quantity']! as int,
      );
}

class ProductDraft {
  const ProductDraft({
    required this.sku,
    required this.name,
    required this.unitPriceCents,
    required this.unitCostCents,
    required this.stockQuantity,
  });

  final String sku;
  final String name;
  final int unitPriceCents;
  final int unitCostCents;
  final int stockQuantity;
}
