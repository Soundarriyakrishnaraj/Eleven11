import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/motivation_models.dart';

class MotivationRepository {
  final SupabaseClient _client;

  MotivationRepository(this._client);

  // Load all active motivation categories.
  Future<List<MotivationCategory>> getCategories() async {
    final data = await _client
        .from('motivation_categories')
        .select('id, name, description')
        .eq('is_active', true)
        .order('name');

    return (data as List).map((e) => MotivationCategory.fromJson(e)).toList();
  }

  // Load categories selected by the current user.
  Future<List<MotivationCategory>> getSelectedCategories() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw Exception('Please log in.');
    }

    final data = await _client
        .from('user_selected_categories')
        .select('category_id, motivation_categories(id, name, description)')
        .eq('user_id', user.id);

    return (data as List).map((row) {
      final category = row['motivation_categories'];

      if (category == null) {
        throw Exception('A selected category no longer exists.');
      }

      return MotivationCategory.fromJson(
        Map<String, dynamic>.from(category as Map),
      );
    }).toList();
  }

  // Save the user's selected categories.
  Future<void> saveSelectedCategories(List<String> categoryIds) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw Exception('Please log in.');
    }

    // Remove previous selections.
    await _client
        .from('user_selected_categories')
        .delete()
        .eq('user_id', user.id);

    if (categoryIds.isEmpty) {
      return;
    }

    // Save new selections.
    await _client
        .from('user_selected_categories')
        .insert(
          categoryIds
              .toSet()
              .map((id) => {'user_id': user.id, 'category_id': id})
              .toList(),
        );
  }

  // Get or create today's stable daily quote using a secure database RPC.
  Future<MotivationQuote?> getDailyQuote() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw Exception('Please log in.');
    }

    final now = DateTime.now();

    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final result = await _client.rpc(
      'get_or_assign_daily_quote',
      params: {'p_local_date': today},
    );

    final rows = result as List;

    if (rows.isEmpty) {
      final selected = await getSelectedCategories();

      if (selected.isEmpty) {
        throw Exception('Please select your motivation categories first.');
      }

      return null;
    }

    final row = Map<String, dynamic>.from(rows.first as Map);
    final quoteId = row['quote_id'].toString();

    return _getQuote(quoteId);
  }

  // Load a quote by ID with its author and category.
  Future<MotivationQuote?> _getQuote(String quoteId) async {
    final data = await _client
        .from('quotes')
        .select(
          'id, content, author, author_id, category_id, '
          'authors(name), motivation_categories(name)',
        )
        .eq('id', quoteId)
        .eq('is_active', true)
        .maybeSingle();

    if (data == null) {
      return null;
    }

    return MotivationQuote.fromJson(data);
  }

  // Browse quotes by category.
  Future<List<MotivationQuote>> getQuotesByCategory(String categoryId) async {
    final data = await _client
        .from('quotes')
        .select(
          'id, content, author, author_id, category_id, '
          'authors(name), motivation_categories(name)',
        )
        .eq('category_id', categoryId)
        .eq('is_active', true)
        .order('created_at', ascending: false);

    return (data as List).map((e) => MotivationQuote.fromJson(e)).toList();
  }

  // Browse quotes by author.
  Future<List<MotivationQuote>> getQuotesByAuthor(String authorId) async {
    final data = await _client
        .from('quotes')
        .select(
          'id, content, author, author_id, category_id, '
          'authors(name), motivation_categories(name)',
        )
        .eq('author_id', authorId)
        .eq('is_active', true)
        .order('created_at', ascending: false);

    return (data as List).map((e) => MotivationQuote.fromJson(e)).toList();
  }

  // Browse quotes by emotion.
  Future<List<MotivationQuote>> getQuotesByEmotion(String emotionTagId) async {
    final relations = await _client
        .from('quote_emotion_tags')
        .select('quote_id')
        .eq('emotion_tag_id', emotionTagId);

    final ids = (relations as List)
        .map((e) => e['quote_id'].toString())
        .toSet()
        .toList();

    if (ids.isEmpty) {
      return [];
    }

    final data = await _client
        .from('quotes')
        .select(
          'id, content, author, author_id, category_id, '
          'authors(name), motivation_categories(name)',
        )
        .inFilter('id', ids)
        .eq('is_active', true);

    return (data as List).map((e) => MotivationQuote.fromJson(e)).toList();
  }
}
