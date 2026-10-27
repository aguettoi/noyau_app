import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../application/providers/supabase_client_provider.dart';

class SupabaseAuthPage extends ConsumerStatefulWidget {
  const SupabaseAuthPage({
    super.key,
    this.createAccount = false,
    this.invitationIntent = false,
  });

  final bool createAccount;
  final bool invitationIntent;

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
  late var _creatingAccount = widget.createAccount;
  String? _errorMessage;
  String? _successMessage;
  String _w(String key) => AppWords.of(context).text(key);

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
        _errorMessage = _signInErrorMessage(error);
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
            ? _w('auth.signup_success_session')
            : _w('auth.signup_success_confirmation');
        if (!sessionCreated) _creatingAccount = false;
      });
    } on AuthException catch (error) {
      _debugAuthFailure(error);
      if (!mounted) return;
      setState(() {
        _errorMessage = switch (error.code) {
          'user_already_exists' => _w('auth.error.email_used'),
          'weak_password' => _w('auth.error.weak_password'),
          _ => _w('auth.error.signup'),
        };
      });
    } catch (error) {
      _debugAuthFailure(error);
      if (mounted) {
        setState(() => _errorMessage = _w('auth.error.signup'));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = _w('auth.validation.reset_email'));
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
        setState(() => _successMessage = _w('auth.reset_sent'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = _w('auth.error.reset'));
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

  String _signInErrorMessage(Object error) {
    if (error is AssertionError) {
      return _w('auth.error.configuration');
    }
    if (error case AuthException authError) {
      return switch (authError.code) {
        'invalid_credentials' => _w('auth.error.credentials'),
        'email_not_confirmed' => _w('auth.error.email_unconfirmed'),
        'user_banned' => _w('auth.error.banned'),
        _ when authError.statusCode == '429' => _w('auth.error.rate_limit'),
        _ => _w('auth.error.service'),
      };
    }
    return _w('auth.error.network');
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
                        _creatingAccount ? _w('auth.create') : _w('title'),
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      if (widget.invitationIntent) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Card(
                          color: Color(0xFFEAF3FF),
                          child: Padding(
                            padding: EdgeInsets.all(AppSpacing.sm),
                            child: Text(_w('auth.invitation_help')),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _creatingAccount
                            ? _w('auth.signup_intro')
                            : _w('auth.login_intro'),
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_creatingAccount) ...[
                        TextFormField(
                          key: const Key('auth-first-name-field'),
                          controller: _firstNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: _w('auth.first_name'),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? _w('auth.validation.first_name')
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          key: const Key('auth-last-name-field'),
                          controller: _lastNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: _w('auth.last_name_optional'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      TextFormField(
                        key: const Key('auth-email-field'),
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        decoration: InputDecoration(
                          labelText: _w('common.email'),
                        ),
                        validator: (value) =>
                            value == null ||
                                value.trim().isEmpty ||
                                !value.contains('@')
                            ? _w('auth.validation.email')
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
                        decoration: InputDecoration(
                          labelText: _w('auth.password'),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return _w('auth.validation.password');
                          }
                          if (_creatingAccount && value.length < 8) {
                            return _w('auth.validation.password_length');
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
                          decoration: InputDecoration(
                            labelText: _w('auth.confirm_password'),
                          ),
                          validator: (value) =>
                              value != _passwordController.text
                              ? _w('auth.validation.password_match')
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
                                    ? _w('auth.create_mine')
                                    : _w('login'),
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
                              ? _w('auth.have_account')
                              : _w('auth.create'),
                        ),
                      ),
                      if (!_creatingAccount)
                        TextButton(
                          key: const Key('auth-forgot-password-button'),
                          onPressed: _submitting ? null : _forgotPassword,
                          child: Text(_w('auth.forgot')),
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
