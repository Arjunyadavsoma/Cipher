import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mimir_ai/app/features/auth/data/auth_repository.dart';

import '../widgets/auth_button.dart';
import '../widgets/auth_divider.dart';
import '../widgets/auth_footer.dart';
import '../widgets/auth_logo.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/auth_title.dart';
import '../widgets/google_signin_button.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    try {
      await ref.read(authRepositoryProvider).signInWithEmailAndPassword(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _googleSignIn() async {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 12,
              ),
              // ConstrainedBox + IntrinsicHeight is what makes this
              // "fit without scrolling on normal screens, but scroll
              // instead of overflow on the rare short/large-font
              // screen" — minHeight reserves the full viewport so
              // content still centers vertically like before, but
              // nothing is FORCED into that height the way the last
              // version's SizedBox(height: constraints.maxHeight) did.
              // That forcing is what produced the 30px overflow.
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight -
                      24, // vertical padding above
                ),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const AuthLogo(),

                          const SizedBox(height: 20),

                          const AuthTitle(
                            title: "Welcome back",
                            subtitle: "Continue to your Cipher workspace",
                          ),

                          const SizedBox(height: 28),

                          AuthTextField(
                            controller: _emailController,
                            labelText: "Email",
                            keyboardType: TextInputType.emailAddress,
                          ),

                          const SizedBox(height: 14),

                          AuthTextField(
                            controller: _passwordController,
                            labelText: "Password",
                            obscureText: true,
                          ),

                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 32),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                context.push("/forgot-password");
                              },
                              child: const Text("Forgot password?"),
                            ),
                          ),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Don't have an account?"),
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () {
                                  context.go("/signup");
                                },
                                child: const Text("Create account"),
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          AuthButton(
                            text: "Continue",
                            onPressed: _login,
                            isLoading: _isLoading,
                          ),

                          const SizedBox(height: 20),

                          const AuthDivider(),

                          const SizedBox(height: 20),

                          GoogleSignInButton(
                            onPressed: _googleSignIn,
                          ),

                          const SizedBox(height: 16),

                          const AuthFooter(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}