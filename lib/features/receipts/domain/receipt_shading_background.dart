class ReceiptShadingBackground {
  const ReceiptShadingBackground({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.thumbnailUrl,
    this.sortOrder = 0,
    this.isPremium = false,
  });

  final String id;
  final String name;
  final String imageUrl;
  final String? thumbnailUrl;
  final int sortOrder;
  final bool isPremium;
}
