import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_text.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, this.initialCategory});

  final String? initialCategory;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();

  int _rating = 5;
  late String _category;
  bool _isSubmitting = false;
  String? _statusMessage;
  bool _isError = false;

  static const List<Map<String, String>> _categories = [
    {'value': 'general', 'label': 'General Feedback'},
    {'value': 'bug_report', 'label': 'Bug Report'},
    {'value': 'feature_request', 'label': 'Feature Request'},
    {'value': 'performance', 'label': 'Performance Issue'},
    {'value': 'theme_eink', 'label': 'E-Ink & Themes'},
  ];

  @override
  void initState() {
    super.initState();
    final validValues = _categories.map((c) => c['value']).toSet();
    _category = (widget.initialCategory != null &&
            validValues.contains(widget.initialCategory))
        ? widget.initialCategory!
        : 'general';
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('You must be signed in to submit feedback.');
      }

      // Try inserting with category and status (enhanced schema)
      try {
        await Supabase.instance.client.from('user_feedback').insert({
          'user_id': user.id,
          'message': _messageController.text.trim(),
          'rating': _rating,
          'category': _category,
          'status': 'new',
        });
      } catch (insertErr) {
        // Fallback for baseline schema if category/status columns do not exist
        await Supabase.instance.client.from('user_feedback').insert({
          'user_id': user.id,
          'message': '[${_category.toUpperCase()}] ${_messageController.text.trim()}',
          'rating': _rating,
        });
      }

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _statusMessage = 'Thank you! Your feedback has been securely submitted.';
        _isError = false;
        _messageController.clear();
        _rating = 5;
        _category = 'general';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_statusMessage!),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _statusMessage = 'Failed to submit feedback: ${e.toString().replaceAll("Exception: ", "")}';
        _isError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const AppText('SUBMIT FEEDBACK'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  'We value your feedback',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                AppText(
                  'Help us improve Eleven11. All feedback is directly reviewed by the product team.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),

                // Rating Stars
                AppText('Rating', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (index) {
                    final star = index + 1;
                    return IconButton(
                      icon: Icon(
                        star <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
                        color: star <= _rating ? Colors.amber : colorScheme.onSurfaceVariant,
                        size: 32,
                      ),
                      onPressed: () => setState(() => _rating = star),
                    );
                  }),
                ),
                const SizedBox(height: 20),

                // Category Dropdown
                AppText('Category', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _categories.map((c) {
                    return DropdownMenuItem<String>(
                      value: c['value'],
                      child: Text(c['label']!),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _category = val);
                  },
                ),
                const SizedBox(height: 20),

                // Message Field
                AppText('Your Message', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _messageController,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    hintText: 'Describe your suggestion, bug report, or experience in detail...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().length < 5) {
                      return 'Please provide at least 5 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                if (_statusMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isError
                          ? colorScheme.error.withValues(alpha: 0.12)
                          : colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _isError ? colorScheme.error : colorScheme.primary,
                      ),
                    ),
                    child: AppText(
                      _statusMessage!,
                      style: TextStyle(
                        color: _isError ? colorScheme.error : colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submitFeedback,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: AppText(_isSubmitting ? 'Submitting...' : 'Submit Feedback'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
