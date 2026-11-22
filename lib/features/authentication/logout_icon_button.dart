import 'package:material_ui/material_ui.dart';

import 'auth_service.dart';

class LogoutIconButton extends StatelessWidget {
  const LogoutIconButton({super.key, @visibleForTesting this.signOut});

  @visibleForTesting
  final Future<void> Function()? signOut;

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out of Eleven11?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      await (signOut ?? AuthService().signOut)();

      if (!context.mounted) return;

      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Logout failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Logout',
      onPressed: () => _logout(context),
      icon: Icon(
        Icons.logout_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
