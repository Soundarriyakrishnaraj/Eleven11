import 'package:material_ui/material_ui.dart';

import 'auth_service.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  DateTime? _dateOfBirth;
  int _step = 0;
  bool _loading = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _chooseDateOfBirth() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'Select your date of birth',
    );
    if (selected != null) setState(() => _dateOfBirth = selected);
  }

  Future<void> _verifyDetails() async {
    final username = _username.text.trim();
    final email = _email.text.trim();
    if (username.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
        _dateOfBirth == null) {
      setState(() {
        _error = 'Enter your username, a valid email, and date of birth.';
      });
      return;
    }

    await _run(() async {
      await AuthService().startPasswordRecovery(
        username: username,
        email: email,
        dateOfBirth: _dateOfBirth!,
      );
      if (mounted) {
        setState(() {
          _step = 1;
          _error = null;
        });
      }
    });
  }

  Future<void> _verifyCode() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Enter the verification code.');
      return;
    }

    await _run(() async {
      await AuthService().verifyRecoveryCode(
        email: _email.text,
        code: _code.text,
      );
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() {
          _step = 2;
          _error = null;
        });
      }
    }, failureMessage: 'The code is invalid or expired. Request a new code.');
  }

  Future<void> _resetPassword() async {
    final passwordError = PasswordPolicy.validate(_password.text);
    if (passwordError != null) {
      setState(() => _error = passwordError);
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    await _run(() async {
      await AuthService().resetPassword(_password.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your password has been reset.')),
      );
      Navigator.of(context).pop();
    });
  }

  Future<void> _run(
    Future<void> Function() action, {
    String failureMessage = 'Unable to process your request. Please try again.',
  }) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } on AuthFlowException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = failureMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _title => switch (_step) {
    0 => 'Verify your account',
    1 => 'Enter your email code',
    _ => 'Choose a new password',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_step == 0) ...[
                    const Text(
                      'Enter the details associated with your account. If they match, we will send a one-time code to your registered email.',
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _username,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Registered email address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _chooseDateOfBirth,
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        _dateOfBirth == null
                            ? 'Date of birth'
                            : '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}',
                      ),
                    ),
                  ] else if (_step == 1) ...[
                    const Text(
                      'If the details matched an account, a code was sent to the registered email address. Codes expire and can only be used once.',
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'One-time verification code',
                        prefixIcon: Icon(Icons.verified_user_outlined),
                      ),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                              _step = 0;
                              _error = null;
                              _code.clear();
                            }),
                      child: const Text('Use different account details'),
                    ),
                  ] else ...[
                    const Text(
                      'Choose a strong password that you have not used elsewhere.',
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _password,
                      obscureText: _hidePassword,
                      keyboardType: TextInputType.visiblePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmPassword,
                      obscureText: true,
                      keyboardType: TextInputType.visiblePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading
                        ? null
                        : switch (_step) {
                            0 => _verifyDetails,
                            1 => _verifyCode,
                            _ => _resetPassword,
                          },
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(switch (_step) {
                            0 => 'VERIFY',
                            1 => 'VERIFY CODE',
                            _ => 'RESET PASSWORD',
                          }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
