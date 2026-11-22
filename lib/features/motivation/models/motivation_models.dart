class MotivationCategory {
  final String id;
  final String name;
  final String? description;

  const MotivationCategory({
    required this.id,
    required this.name,
    this.description,
  });

  factory MotivationCategory.fromJson(Map<String, dynamic> json) {
    return MotivationCategory(
      id: json['id'].toString(),
      name: json['name'] as String,
      description: json['description'] as String?,
    );
  }
}

class MotivationQuote {
  final String id;
  final String content;
  final String? author;
  final String? authorName;
  final String? categoryId;
  final String? categoryName;
  final List<String> emotionTags;

  const MotivationQuote({
    required this.id,
    required this.content,
    this.author,
    this.authorName,
    this.categoryId,
    this.categoryName,
    this.emotionTags = const [],
  });

  factory MotivationQuote.fromJson(Map<String, dynamic> json) {
    final authorData = json['authors'];
    final categoryData = json['motivation_categories'];

    final authorMap = authorData is Map
        ? Map<String, dynamic>.from(authorData)
        : null;

    final categoryMap = categoryData is Map
        ? Map<String, dynamic>.from(categoryData)
        : null;

    return MotivationQuote(
      id: json['id'].toString(),
      content: json['content'] as String,
      author: json['author'] as String?,
      authorName: authorMap?['name'] as String?,
      categoryId: json['category_id']?.toString(),
      categoryName: categoryMap?['name'] as String?,
    );
  }

  String get displayAuthor => authorName ?? author ?? 'Unknown author';
}
