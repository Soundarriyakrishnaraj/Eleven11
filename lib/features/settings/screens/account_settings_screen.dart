import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../authentication/auth_service.dart';
import '../../calendar/services/google_calendar_service.dart';
import '../widgets/settings_tile.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  Color get _orange => Theme.of(context).colorScheme.primary;
  Color get _card => Theme.of(context).colorScheme.surface;

  String _name = '';
  String _email = '';
  String _username = '';
  DateTime? _dateOfBirth;
  bool _loading = true;
  bool _saving = false;

  final GoogleCalendarService _calendarService = GoogleCalendarService();
  GoogleCalendarStatus _calendarStatus = GoogleCalendarStatus.disconnected;
  bool _calendarLoading = true;
  bool _calendarActionInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadCalendarStatus();
  }

  @override
  void dispose() {
    _calendarService.dispose();
    super.dispose();
  }

  Future<void> _loadCalendarStatus() async {
    try {
      final status = await _calendarService.getStatus();
      if (mounted) {
        setState(() {
          _calendarStatus = status;
          _calendarLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _calendarLoading = false);
      }
    }
  }

  Future<void> _connectCalendar() async {
    setState(() => _calendarActionInProgress = true);
    try {
      await _calendarService.startAuthorization(
        onCompleted: (status) {
          if (mounted) {
            setState(() {
              _calendarStatus = status;
              _calendarActionInProgress = false;
            });
            _snack('Google Calendar connected: ${status.email ?? ''}');
          }
        },
        onError: (err) {
          if (mounted) {
            setState(() => _calendarActionInProgress = false);
            _snack(err);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _calendarActionInProgress = false);
        _snack('$e');
      }
    }
  }

  Future<void> _disconnectCalendar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Disconnect Calendar?'),
        content: const Text(
          'Eleven11 will no longer synchronize your events with Google Calendar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _calendarActionInProgress = true);
    try {
      await _calendarService.disconnect();
      if (mounted) {
        setState(() {
          _calendarStatus = GoogleCalendarStatus.disconnected;
          _calendarActionInProgress = false;
        });
        _snack('Google Calendar disconnected.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _calendarActionInProgress = false);
        _snack('$e');
      }
    }
  }

  Future<void> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('full_name, username, date_of_birth')
          .eq('id', user.id)
          .maybeSingle();

      final fullName =
          row?['full_name']?.toString() ??
          user.userMetadata?['full_name']?.toString() ??
          user.userMetadata?['name']?.toString() ??
          'Eleven11 Member';

      if (mounted) {
        setState(() {
          _name = fullName;
          _email = user.email ?? '';
          _username = row?['username']?.toString() ?? '';
          final dob = row?['date_of_birth']?.toString();
          _dateOfBirth = dob == null ? null : DateTime.tryParse(dob);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _name =
              user.userMetadata?['full_name']?.toString() ?? 'Eleven11 Member';
          _email = user.email ?? '';
          _loading = false;
        });
      }
    }
  }

  Future<void> _editUsername() async {
    final controller = TextEditingController(text: _username);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Username'),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          decoration: const InputDecoration(
            labelText: '3–30 letters, numbers, or underscores',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    if (!RegExp(r'^[A-Za-z0-9_]{3,30}$').hasMatch(result)) {
      _snack('Use 3–30 letters, numbers, or underscores.');
      return;
    }

    await _saveProfileField({'username': result});
  }

  Future<void> _editDateOfBirth() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? today,
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'Select your date of birth',
    );
    if (selected == null || !mounted) return;
    await _saveProfileField({
      'date_of_birth':
          '${selected.year.toString().padLeft(4, '0')}-'
          '${selected.month.toString().padLeft(2, '0')}-'
          '${selected.day.toString().padLeft(2, '0')}',
    });
  }

  Future<void> _saveProfileField(Map<String, dynamic> values) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        ...values,
      });
      if (!mounted) return;
      setState(() {
        if (values.containsKey('username')) {
          _username = values['username'] as String;
        }
        if (values.containsKey('date_of_birth')) {
          _dateOfBirth = DateTime.parse(values['date_of_birth'] as String);
        }
      });
      _snack('Account details updated.');
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        _snack('This username is already taken.');
      } else {
        _snack('Could not update account details. Please try again.');
      }
    } catch (_) {
      _snack('Could not update account details. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Edit Name',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Your name',
            hintStyle: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Theme.of(ctx).colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _orange),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty || !mounted) return;

    setState(() => _saving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'full_name': result,
      });

      if (mounted) setState(() => _name = result);
      _snack('Name updated successfully.');
    } catch (e) {
      _snack('Could not update name: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    bool obscure = true;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: _card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Change Password',
            style: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                obscureText: obscure,
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'New password',
                  hintStyle: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => setS(() => obscure = !obscure),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: Theme.of(ctx).colorScheme.outline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _orange),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: obscure,
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Confirm password',
                  hintStyle: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: Theme.of(ctx).colorScheme.outline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _orange),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
              ),
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );

    if (result == null || result.isEmpty || !mounted) return;

    final passwordError = PasswordPolicy.validate(result);
    if (passwordError != null) {
      _snack(passwordError);
      return;
    }

    if (result != confirmController.text.trim()) {
      _snack('Passwords do not match.');
      return;
    }

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: result),
      );
      _snack('Password updated successfully.');
    } catch (e) {
      _snack('Could not update password: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Sign Out?',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to sign out of Eleven11?',
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await AuthService().signOut();
      if (!mounted) return;
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
    } catch (e) {
      _snack('Sign out failed: $e');
    }
  }

  Widget _buildCalendarTile() {
    final connected = _calendarStatus.connected;
    final email = _calendarStatus.email;

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  color: _orange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Google Calendar',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _calendarLoading
                          ? 'Checking status...'
                          : connected
                              ? (email ?? 'Connected')
                              : 'Not connected',
                      style: TextStyle(
                        fontSize: 12,
                        color: connected
                            ? _orange
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_calendarLoading || _calendarActionInProgress)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _orange,
                  ),
                )
              else if (connected)
                TextButton(
                  onPressed: _disconnectCalendar,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('Disconnect'),
                )
              else
                FilledButton(
                  onPressed: _connectCalendar,
                  style: FilledButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Connect',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'YOUR ACCOUNT',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 15,
          ),
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Avatar
                Center(
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: _orange, width: 2.5),
                    ),
                    child: Icon(
                      Icons.person,
                      color: Theme.of(context).colorScheme.primary,
                      size: 50,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    _name,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    _email,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                const SettingsSectionHeader('Profile'),
                const SizedBox(height: 8),

                SettingsTile(
                  icon: Icons.person_outline,
                  title: 'Display Name',
                  subtitle: _name,
                  onTap: _editName,
                  showArrow: true,
                ),
                const SizedBox(height: 10),
                SettingsTile(
                  icon: Icons.email_outlined,
                  title: 'Email Address',
                  subtitle: _email,
                  showArrow: false,
                  onTap: null,
                ),
                const SizedBox(height: 10),
                SettingsTile(
                  icon: Icons.alternate_email,
                  title: 'Username',
                  subtitle: _username.isEmpty
                      ? 'Set a username to enable username sign-in'
                      : _username,
                  showArrow: true,
                  onTap: _editUsername,
                ),
                const SizedBox(height: 10),
                SettingsTile(
                  icon: Icons.cake_outlined,
                  title: 'Date of Birth',
                  subtitle: _dateOfBirth == null
                      ? 'Not set'
                      : '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}',
                  showArrow: true,
                  onTap: _editDateOfBirth,
                ),
                const SizedBox(height: 10),
                SettingsTile(
                  icon: Icons.lock_outline,
                  title: 'Change Password',
                  subtitle: 'Update your login password',
                  onTap: _changePassword,
                ),

                const SizedBox(height: 24),
                const SettingsSectionHeader('Integrations'),
                const SizedBox(height: 8),

                _buildCalendarTile(),

                const SizedBox(height: 28),
                if (_saving)
                  Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),

                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text(
                      'SIGN OUT',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
