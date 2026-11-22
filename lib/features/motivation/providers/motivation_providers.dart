import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/motivation_models.dart';
import '../repositories/motivation_repository.dart';

final motivationRepositoryProvider = Provider<MotivationRepository>((ref) {
  return MotivationRepository(Supabase.instance.client);
});

final motivationCategoriesProvider = FutureProvider<List<MotivationCategory>>((
  ref,
) {
  return ref.watch(motivationRepositoryProvider).getCategories();
});

final selectedMotivationCategoriesProvider =
    FutureProvider<List<MotivationCategory>>((ref) {
      return ref.watch(motivationRepositoryProvider).getSelectedCategories();
    });

final dailyMotivationQuoteProvider = FutureProvider<MotivationQuote?>((ref) {
  return ref.watch(motivationRepositoryProvider).getDailyQuote();
});
