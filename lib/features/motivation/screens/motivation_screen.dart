import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/theme_provider.dart';
import '../../dashboard/dashboard_screen.dart';
import '../models/motivation_models.dart';
import '../providers/motivation_providers.dart';

class MotivationScreen extends ConsumerStatefulWidget {
  const MotivationScreen({super.key});

  @override
  ConsumerState<MotivationScreen> createState() => _MotivationScreenState();
}

class _MotivationScreenState extends ConsumerState<MotivationScreen> {
  Color get cardColor => Theme.of(context).colorScheme.surface;
  Color get orange => Theme.of(context).colorScheme.primary;

  bool checking = true;
  bool saving = false;
  bool categoryLoading = false;
  bool showCategoryPicker = false;
  bool quoteLoaded = false;

  String? errorMessage;

  int secondsRemaining = 35;
  Timer? countdownTimer;

  List<Map<String, dynamic>> allCategories = [];
  final Set<String> selectedIds = {};

  @override
  void initState() {
    super.initState();
    checkCategories();
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    super.dispose();
  }

  void startCountdown() {
    if (!mounted || quoteLoaded) return;

    quoteLoaded = true;
    countdownTimer?.cancel();

    setState(() {
      secondsRemaining = 35;
    });

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (secondsRemaining <= 1) {
        timer.cancel();
        openDashboard();
      } else {
        setState(() {
          secondsRemaining--;
        });
      }
    });
  }

  void openDashboard() {
    countdownTimer?.cancel();

    if (!mounted) return;

    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const DashboardScreen()));
  }

  Future<void> checkCategories() async {
    if (!mounted) return;

    setState(() {
      checking = true;
      errorMessage = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) {
        throw Exception('Please log in again.');
      }

      final rows = await Supabase.instance.client
          .from('user_selected_categories')
          .select('category_id')
          .eq('user_id', user.id)
          .timeout(const Duration(seconds: 8));

      if (rows.isEmpty) {
        await loadCategoryChoices();
        return;
      }

      if (!mounted) return;

      setState(() {
        showCategoryPicker = false;
        checking = false;
      });

      await loadQuote();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        checking = false;
        errorMessage = 'Could not check your categories: $e';
      });
    }
  }

  Future<void> loadCategoryChoices() async {
    if (!mounted) return;

    setState(() {
      categoryLoading = true;
      checking = false;
      showCategoryPicker = true;
      errorMessage = null;
    });

    try {
      final rows = await Supabase.instance.client
          .from('motivation_categories')
          .select('id, name')
          .eq('is_active', true)
          .order('name')
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;

      setState(() {
        allCategories = List<Map<String, dynamic>>.from(rows);
        categoryLoading = false;
      });

      if (allCategories.isEmpty) {
        setState(() {
          errorMessage = 'No active categories found in Supabase.';
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        categoryLoading = false;
        errorMessage = 'Unable to load categories: $e';
      });
    }
  }

  Future<void> saveCategories() async {
    if (selectedIds.isEmpty) {
      setState(() {
        errorMessage = 'Select at least one category.';
      });
      return;
    }

    setState(() {
      saving = true;
      errorMessage = null;
    });

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;

      if (user == null) {
        throw Exception('Please log in again.');
      }

      await client
          .from('user_selected_categories')
          .delete()
          .eq('user_id', user.id)
          .timeout(const Duration(seconds: 8));

      await client
          .from('user_selected_categories')
          .insert(
            selectedIds
                .map((id) => {'user_id': user.id, 'category_id': id})
                .toList(),
          )
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;

      setState(() {
        saving = false;
        showCategoryPicker = false;
        checking = false;
      });

      ref.invalidate(selectedMotivationCategoriesProvider);
      ref.invalidate(dailyMotivationQuoteProvider);

      await loadQuote();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        saving = false;
        errorMessage = 'Could not save categories: $e';
      });
    }
  }

  Future<void> loadQuote() async {
    if (!mounted) return;

    countdownTimer?.cancel();
    quoteLoaded = false;

    ref.invalidate(dailyMotivationQuoteProvider);
    ref.invalidate(selectedMotivationCategoriesProvider);

    try {
      final quote = await ref
          .read(dailyMotivationQuoteProvider.future)
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;

      if (quote != null) {
        startCountdown();
      } else {
        setState(() {
          errorMessage = 'No quote available today.';
        });
      }
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Quote loading took too long. Please try again.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Unable to load today’s quote: $e';
      });
    }
  }

  Widget categoryPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CHOOSE YOUR MOTIVATION',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'What inspires you?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 27,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose the topics you want your daily quotes to focus on. Select at least one.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        if (categoryLoading)
          Center(child: CircularProgressIndicator(color: orange))
        else
          Wrap(
            spacing: 10,
            runSpacing: 12,
            children: allCategories.map((category) {
              final id = category['id'].toString();
              final name = category['name'].toString();
              final active = selectedIds.contains(id);

              return FilterChip(
                label: Text(name),
                selected: active,
                showCheckmark: true,
                selectedColor: orange.withValues(alpha: 0.18),
                backgroundColor: cardColor,
                checkmarkColor: orange,
                labelStyle: TextStyle(
                  color: active
                      ? orange
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
                side: BorderSide(
                  color: active
                      ? orange
                      : Theme.of(context).colorScheme.outline,
                ),
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      selectedIds.add(id);
                    } else {
                      selectedIds.remove(id);
                    }
                    errorMessage = null;
                  });
                },
              );
            }).toList(),
          ),
        const SizedBox(height: 20),
        Text(
          '${selectedIds.length} selected',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            onPressed: loadCategoryChoices,
            child: const Text('RETRY'),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: saving || categoryLoading ? null : saveCategories,
            style: ElevatedButton.styleFrom(
              backgroundColor: orange,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: saving
                ? CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.onPrimary,
                  )
                : const Text(
                    'CONTINUE',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

  Widget quoteSection() {
    final quoteAsync = ref.watch(dailyMotivationQuoteProvider);

    return quoteAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(35),
        child: Center(child: CircularProgressIndicator(color: orange)),
      ),
      error: (error, stack) =>
          _ErrorCard(message: error.toString(), onRetry: loadQuote),
      data: (quote) {
        if (quote == null) {
          return const _EmptyQuoteCard();
        }

        return _DailyQuoteCard(quote: quote);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: orange)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'ELEVEN11',
          style: TextStyle(
            color: kSignatureOrange,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: orange,
        backgroundColor: cardColor,
        onRefresh: () async {
          if (showCategoryPicker) {
            await loadCategoryChoices();
          } else {
            await loadQuote();
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 12),
            if (showCategoryPicker)
              categoryPicker()
            else ...[
              Text(
                'YOUR DAILY MOTIVATION',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Make today count.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              quoteSection(),

              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: loadQuote,
                  child: const Text('TRY AGAIN'),
                ),
              ],

              const SizedBox(height: 20),

              if (quoteLoaded) ...[
                Text(
                  'Continuing in $secondsRemaining seconds',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: openDashboard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    child: Text(
                      'CONTINUE TO DASHBOARD',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              OutlinedButton.icon(
                onPressed: () async {
                  countdownTimer?.cancel();
                  selectedIds.clear();
                  await loadCategoryChoices();
                },
                icon: const Icon(Icons.tune),
                label: const Text('CHANGE CATEGORIES'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 32),

              Text(
                'DISCIPLINE. FOCUS. ACHIEVE.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                'Small actions repeated daily create extraordinary results.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DailyQuoteCard extends StatefulWidget {
  final MotivationQuote quote;

  const _DailyQuoteCard({required this.quote});

  @override
  State<_DailyQuoteCard> createState() => _DailyQuoteCardState();
}

class _DailyQuoteCardState extends State<_DailyQuoteCard>
    with SingleTickerProviderStateMixin {
  Color get orange => Theme.of(context).colorScheme.primary;

  bool liked = false;
  bool saving = false;
  bool checkingEngagement = true;

  late final AnimationController controller;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      lowerBound: 1,
      upperBound: 1.35,
    );

    loadEngagement();
  }

  String get localDate {
    final now = DateTime.now();

    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> loadEngagement() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;

      if (user == null) return;

      final row = await client
          .from('motivation_daily_engagement')
          .select('engagement_date')
          .eq('user_id', user.id)
          .eq('engagement_date', localDate)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        liked = row != null;
        checkingEngagement = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        checkingEngagement = false;
      });

      debugPrint('Engagement loading failed: $e');
    }
  }

  Future<void> recordHeart() async {
    if (liked || saving || checkingEngagement) return;

    setState(() => saving = true);

    try {
      final result = await Supabase.instance.client.rpc(
        'record_motivation_engagement',
        params: {'p_quote_id': widget.quote.id, 'p_local_date': localDate},
      );

      if (!mounted) return;

      setState(() {
        liked = true;
        saving = false;
      });

      controller.forward().then((_) {
        if (mounted) controller.reverse();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == true
                ? 'Motivation streak updated! 🔥'
                : 'Today’s motivation is already recorded! 🔥',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not record motivation: $e')),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote, color: orange),
              SizedBox(width: 8),
              Text(
                'QUOTE OF THE DAY',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '“${quote.content}”',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 21,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '— ${quote.displayAuthor}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (quote.categoryName != null) ...[
            const SizedBox(height: 8),
            Text(
              quote.categoryName!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          Divider(color: Theme.of(context).colorScheme.outline, height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Let these words guide your day.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              ScaleTransition(
                scale: controller,
                child: IconButton(
                  tooltip: 'Record today’s motivation',
                  onPressed: liked || saving || checkingEngagement
                      ? null
                      : recordHeart,
                  icon: saving
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: orange,
                          ),
                        )
                      : Icon(
                          liked ? Icons.favorite : Icons.favorite_border,
                          color: liked ? Colors.redAccent : orange,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            'Could not load today’s quote.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'TRY AGAIN',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyQuoteCard extends StatelessWidget {
  const _EmptyQuoteCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'No active quotes are available in your selected categories yet. Please try again later.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          height: 1.5,
        ),
      ),
    );
  }
}
