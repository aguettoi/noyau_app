import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/app_routes.dart';
import '../../../core/localization/app_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/providers/supabase_client_provider.dart';

class PasswordRecoveryPage extends ConsumerStatefulWidget {
  const PasswordRecoveryPage({super.key});

  @override
  ConsumerState<PasswordRecoveryPage> createState() =>
      _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends ConsumerState<PasswordRecoveryPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final client = ref.read(optionalSupabaseClientProvider);
    if (client?.auth.currentSession == null) {
      setState(
        () => _error = AppWords.of(context).text('auth.recovery.expired'),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await client!.auth.updateUser(UserAttributes(password: _password.text));
      if (mounted) context.go(AppRoutes.home);
    } on AuthException {
      if (mounted) {
        setState(
          () => _error = AppWords.of(context).text('auth.recovery.error'),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = AppWords.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(words.text('auth.recovery.title'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: AppSpacing.page,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('recovery-password'),
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: words.text('auth.password'),
                      ),
                      validator: (value) => value == null || value.length < 8
                          ? words.text('auth.validation.password_length')
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      key: const Key('recovery-password-confirmation'),
                      controller: _confirmation,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: words.text('auth.confirm_password'),
                      ),
                      validator: (value) => value != _password.text
                          ? words.text('auth.validation.password_match')
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      key: const Key('recovery-submit'),
                      onPressed: _submitting ? null : _updatePassword,
                      child: Text(words.text('auth.recovery.submit')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
