import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../application/providers/supabase_client_provider.dart';

class SupabaseAuthPage extends ConsumerStatefulWidget {
  const SupabaseAuthPage({super.key});

  @override
  ConsumerState<SupabaseAuthPage> createState() => _SupabaseAuthPageState();
}

class _SupabaseAuthPageState extends ConsumerState<SupabaseAuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(supabaseAuthGatewayProvider)
          .signInWithPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'Connexion impossible. Vérifiez votre e-mail et votre mot de passe.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: AppSpacing.page,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: AppSpacing.dialog,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AppIcons.overview,
                        size: 34,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Accéder à Noyau',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Connectez-vous pour accéder à votre foyer et préparer vos imports.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        key: const Key('auth-email-field'),
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(labelText: 'E-mail'),
                        validator: (value) =>
                            value == null ||
                                value.trim().isEmpty ||
                                !value.contains('@')
                            ? 'Saisissez une adresse e-mail valide.'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        key: const Key('auth-password-field'),
                        controller: _passwordController,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(
                          labelText: 'Mot de passe',
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Saisissez votre mot de passe.'
                            : null,
                        onFieldSubmitted: (_) => _signIn(),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _errorMessage!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton(
                        key: const Key('auth-sign-in-button'),
                        onPressed: _submitting ? null : _signIn,
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Se connecter'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
