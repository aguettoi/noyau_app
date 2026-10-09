import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_design_system.dart';
import '../application/providers/supabase_client_provider.dart';

class SupabaseAuthPage extends ConsumerStatefulWidget {
  const SupabaseAuthPage({super.key});

  @override
  ConsumerState<SupabaseAuthPage> createState() => _SupabaseAuthPageState();
}

class _SupabaseAuthPageState extends ConsumerState<SupabaseAuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmationController = TextEditingController();
  var _submitting = false;
  var _creatingAccount = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmationController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      await ref
          .read(supabaseAuthGatewayProvider)
          .signInWithPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } catch (error) {
      _debugAuthFailure(error);
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

  Future<void> _signUp() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final sessionCreated = await ref
          .read(supabaseAuthGatewayProvider)
          .signUp(
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      if (!mounted) return;
      setState(() {
        _successMessage = sessionCreated
            ? 'Compte créé. Vous pouvez maintenant créer ou rejoindre votre foyer.'
            : 'Compte créé. Confirmez votre adresse e-mail puis connectez-vous.';
        if (!sessionCreated) _creatingAccount = false;
      });
    } on AuthException catch (error) {
      _debugAuthFailure(error);
      if (!mounted) return;
      setState(() {
        _errorMessage = switch (error.code) {
          'user_already_exists' => 'Cette adresse e-mail est déjà utilisée.',
          'weak_password' =>
            'Le mot de passe ne respecte pas les règles de sécurité.',
          _ =>
            'Création impossible. Vérifiez les informations et votre connexion.',
        };
      });
    } catch (error) {
      _debugAuthFailure(error);
      if (mounted) {
        setState(
          () => _errorMessage =
              'Création impossible. Vérifiez les informations et votre connexion.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(
        () => _errorMessage =
            'Saisissez votre adresse e-mail avant de demander un nouveau mot de passe.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      await ref.read(supabaseAuthGatewayProvider).sendPasswordReset(email);
      if (mounted) {
        setState(
          () => _successMessage =
              'Si cette adresse existe, un e-mail de réinitialisation a été envoyé.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Demande impossible pour le moment. Vérifiez votre connexion.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _debugAuthFailure(Object error) {
    if (!kDebugMode) return;
    if (error case AuthException authError) {
      debugPrint(
        'Supabase Auth sign-in failure: '
        'type=${authError.runtimeType}; '
        'statusCode=${authError.statusCode ?? 'none'}; '
        'code=${authError.code ?? 'none'}; '
        'message=${authError.message}',
      );
      return;
    }
    if (error is AssertionError) {
      debugPrint(
        'Supabase Auth sign-in failure: '
        'type=AssertionError; statusCode=none; code=none; '
        'message=Supabase client was not initialized before the request.',
      );
      return;
    }
    debugPrint(
      'Supabase Auth sign-in failure: '
      'type=${error.runtimeType}; statusCode=none; code=none; '
      'message=non-Auth client exception.',
    );
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
                        _creatingAccount
                            ? 'Créer un compte'
                            : 'FINANCIEL PILOTE',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _creatingAccount
                            ? 'Créez votre identité personnelle. Votre foyer sera configuré ensuite.'
                            : 'Pilotez. Planifiez. Épargnez. Prospérez.\nConnectez-vous pour accéder à votre foyer.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_creatingAccount) ...[
                        TextFormField(
                          key: const Key('auth-first-name-field'),
                          controller: _firstNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Prénom',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Saisissez votre prénom.'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          key: const Key('auth-last-name-field'),
                          controller: _lastNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nom (facultatif)',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
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
                        autofillHints: [
                          _creatingAccount
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Mot de passe',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Saisissez votre mot de passe.';
                          }
                          if (_creatingAccount && value.length < 8) {
                            return 'Utilisez au moins 8 caractères.';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) {
                          if (!_creatingAccount) _signIn();
                        },
                      ),
                      if (_creatingAccount) ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          key: const Key('auth-password-confirmation-field'),
                          controller: _passwordConfirmationController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirmer le mot de passe',
                          ),
                          validator: (value) =>
                              value != _passwordController.text
                              ? 'Les mots de passe ne correspondent pas.'
                              : null,
                          onFieldSubmitted: (_) => _signUp(),
                        ),
                      ],
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
                      if (_successMessage != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _successMessage!,
                          key: const Key('auth-success-message'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton(
                        key: const Key('auth-sign-in-button'),
                        onPressed: _submitting
                            ? null
                            : (_creatingAccount ? _signUp : _signIn),
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _creatingAccount
                                    ? 'Créer mon compte'
                                    : 'Se connecter',
                              ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextButton(
                        key: const Key('auth-switch-mode-button'),
                        onPressed: _submitting
                            ? null
                            : () => setState(() {
                                _creatingAccount = !_creatingAccount;
                                _errorMessage = null;
                                _successMessage = null;
                              }),
                        child: Text(
                          _creatingAccount
                              ? 'J’ai déjà un compte'
                              : 'Créer un compte',
                        ),
                      ),
                      if (!_creatingAccount)
                        TextButton(
                          key: const Key('auth-forgot-password-button'),
                          onPressed: _submitting ? null : _forgotPassword,
                          child: const Text('Mot de passe oublié ?'),
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
