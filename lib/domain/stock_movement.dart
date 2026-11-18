class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.productSku,
    required this.productName,
    required this.movementType,
    required this.quantityDelta,
    required this.unitCostCents,
    required this.referenceId,
    required this.description,
    required this.occurredAt,
    required this.recordedAt,
  });

  final int id;
  final String productId;
  final String productSku;
  final String productName;
  final String movementType;
  final int quantityDelta;
  final int unitCostCents;
  final String referenceId;
  final String description;
  final DateTime occurredAt;
  final DateTime recordedAt;

  factory StockMovement.fromRow(Map<String, Object?> row) => StockMovement(
        id: row['id']! as int,
        productId: row['product_id']! as String,
        productSku: row['product_sku']! as String,
        productName: row['product_name']! as String,
        movementType: row['movement_type']! as String,
        quantityDelta: row['quantity_delta']! as int,
        unitCostCents: row['unit_cost_cents']! as int,
        referenceId: row['reference_id']! as String,
        description: row['description']! as String,
        occurredAt: DateTime.parse(row['occurred_at']! as String),
        recordedAt: DateTime.parse(row['recorded_at']! as String),
      );
}

class StockMovementPage {
  const StockMovementPage({
    required this.movements,
    required this.totalCount,
    required this.pageIndex,
    required this.pageSize,
  });

  final List<StockMovement> movements;
  final int totalCount;
  final int pageIndex;
  final int pageSize;

  int get pageCount => totalCount == 0 ? 1 : (totalCount + pageSize - 1) ~/ pageSize;
}
