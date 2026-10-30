import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/environment.dart';
import '../../../core/widgets/common.dart';
import '../state/session.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.recovery = false});
  final bool recovery;
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool register = false, busy = false;
  String? notice;
  Future<void> continueAnonymously() async {
    setState(() => busy = true);
    try {
      await ref.read(clientProvider).auth.signInAnonymously();
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit({bool reset = false}) async {
    if (!reset && !form.currentState!.validate()) {
      return;
    }
    if (reset && !email.text.contains('@')) {
      setState(() => notice = 'Enter your email address first.');
      return;
    }
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final auth = ref.read(clientProvider).auth;
      if (reset) {
        await auth.resetPasswordForEmail(
          email.text.trim(),
          redirectTo: Environment.redirect,
        );
        notice = 'If an account exists, a reset link has been sent.';
      } else if (widget.recovery) {
        await auth.updateUser(UserAttributes(password: password.text));
        await auth.signOut();
        notice = 'Password updated. Sign in with your new password.';
      } else if (register) {
        await auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: Environment.redirect,
        );
        notice = 'Check your email to verify your account, then sign in.';
      } else {
        await auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.hub_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Your campus.\nYour community.',
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Meet people, share ideas and make things happen with ChitChat.',
                ),
                const SizedBox(height: 32),
                Text(
                  widget.recovery
                      ? 'Choose a new password'
                      : register
                      ? 'Create your account'
                      : 'Welcome back',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                if (!widget.recovery) ...[
                  TextFormField(
                    controller: email,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) => v != null && v.contains('@')
                        ? null
                        : 'Enter a valid email',
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: password,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  autofillHints: [
                    register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  validator: (v) => (v?.length ?? 0) >= 12
                      ? null
                      : 'Use at least 12 characters',
                ),
                const SizedBox(height: 20),
                if (notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(notice!, semanticsLabel: notice),
                  ),
                FilledButton(
                  onPressed: busy ? null : () => submit(),
                  child: Text(
                    busy
                        ? 'Please wait…'
                        : widget.recovery
                        ? 'Update password'
                        : register
                        ? 'Create account'
                        : 'Sign in',
                  ),
                ),
                if (!widget.recovery) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : continueAnonymously,
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Continue anonymously'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Chat without sharing your identity. Guest access stays on this device until you sign out.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            register = !register;
                            notice = null;
                          }),
                    child: Text(
                      register
                          ? 'Already a member? Sign in'
                          : 'New here? Create an account',
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => submit(reset: true),
                    child: const Text('Forgot password?'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
