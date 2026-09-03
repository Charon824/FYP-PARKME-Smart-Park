import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../appsColor/app_theme.dart';
import '../widgets/app_logo.dart';
import '../LoginSystem/Auth_Widgets.dart';
import '../LoginSystem/Auth_Service.dart';
import 'signup.dart';
import 'otp.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  // Email controllers
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();

  // Phone controller
  final _phoneCtrl = TextEditingController();

  bool _isLoading   = false;
  bool _socialLoad  = false;
  String? _socialProvider;

  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ─── Email login ──────────────────────────────────────────────────────────
  Future<void> _loginWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _auth.signInWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on Exception catch (e) {
      if (mounted) showAuthError(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── User using phone to login (send OTP) ───────────────────────────────────────────────
  Future<void> _loginWithPhone() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 9) {
      showAuthError(context, 'Please enter a valid phone number.');
      return;
    }
    setState(() => _isLoading = true);
    final fullPhone = '+60$phone';

    await _auth.sentOTP(
      phoneNumber: fullPhone,
      onAutoVerified: (cred) async {
        _auth.currentUser; // already signed in
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      },
      onFailed: (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          showAuthError(context, 'OTP failed [${e.code}]: ${e.message ?? ''}');
        }
      },
      onCodeSent: (verificationId, resendToken) {
        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OTP(
                phoneNumber: fullPhone,
                verificationId: verificationId,
              ),
            ),
          );
        }
      },
      onTimeout: (verificationId) {
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  // ─── Social logins ────────────────────────────────────────────────────────
  Future<void> _socialLogin(String provider) async {
    setState(() { _socialLoad = true; _socialProvider = provider; });
    try {
      if (provider == 'google') {
        await _auth.signInWithGoogle();
      }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on Exception catch (e) {
      if (mounted) showAuthError(context, e.toString());
    } finally {
      if (mounted) setState(() { _socialLoad = false; _socialProvider = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF2F8FF), AppColors.primaryNavy, AppColors.secondaryNavy],
              ),
            ),
          ),

          // Top accent blob
          Positioned(
            top: -100,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentBlue.withValues(alpha: 0.07),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // App bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: AppColors.textPrimary, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const SignUp()),
                        ),
                        child: const Text('Sign Up',
                          style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),

                          // Header
                          const Row(
                            children: [
                              AppLogo(height: 44),
                            ],
                          ),

                          const SizedBox(height: 28),

                          const Text(
                            'Welcome back',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Please register to easily access our apps and find parking spots',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Tab selector
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.cardNavy,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.inputBorder),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              indicator: BoxDecoration(
                                color: AppColors.accentBlue,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              indicatorSize: TabBarIndicatorSize.tab,
                              labelColor: AppColors.white,
                              unselectedLabelColor: AppColors.textHint,
                              labelStyle: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                              dividerColor: Colors.transparent,
                              padding: const EdgeInsets.all(4),
                              tabs: const [
                                Tab(text: '  Email  '),
                                Tab(text: '  Phone  '),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          SizedBox(
                            height: 220,
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                // ── Email Tab ──
                                Column(
                                  children: [
                                    AuthTextField(
                                      controller: _emailCtrl,
                                      hintText: 'Email address',
                                      prefixIcon: Icons.email_outlined,
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return 'Email required';
                                        if (!v.contains('@')) return 'Enter a valid email';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 14),
                                    AuthTextField(
                                      controller: _passwordCtrl,
                                      hintText: 'Password',
                                      prefixIcon: Icons.lock_outline_rounded,
                                      obscureText: true,
                                      showToggle: true,
                                      textInputAction: TextInputAction.done,
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return 'Password required';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _showForgotPassword,
                                        child: const Text('Forgot Password?',
                                          style: TextStyle(
                                            color: AppColors.accentBlue,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // ── Phone Tab ──
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    PhoneTextField(
                                      controller: _phoneCtrl,
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return 'Phone required';
                                        if (v.length < 9) return 'Please enter valid phone number';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentBlue.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppColors.accentBlue.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.info_outline_rounded,
                                              color: AppColors.accentBlue, size: 16),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'An OTP will be sent to your number via SMS.',
                                              style: TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Primary action button
                          ParkMeButton(
                            label: _tabController.index == 0
                                ? 'Sign In'
                                : 'Send OTP',
                            isLoading: _isLoading,
                            onPressed: () {
                              if (_tabController.index == 0) {
                                _loginWithEmail();
                              } else {
                                _loginWithPhone();
                              }
                            },
                          ),

                          const SizedBox(height: 28),
                          const LabeledDivider(),
                          const SizedBox(height: 24),

                          // Social buttons
                          _SocialSection(
                            onGoogle:   () => _socialLogin('google'),
                            loadingProvider: _socialLoad ? _socialProvider : null,
                          ),

                          const SizedBox(height: 32),

                          // Sign up link
                          Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "Don't have an account? ",
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const SignUp()),
                                  ),
                                  child: const Text(
                                    'Sign Up',
                                    style: TextStyle(
                                      color: AppColors.accentBlue,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showForgotPassword() {
    final emailCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardNavy,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24, right: 24, top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Reset Password',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textHint),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your email and we\'ll send you a reset link.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            AuthTextField(
              controller: emailCtrl,
              hintText: 'Email address',
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 20),
            ParkMeButton(
              label: 'Send Reset Link',
              onPressed: () async {
                try {
                  await _auth.sendPasswordReset(emailCtrl.text.trim());
                  if (mounted) {
                    Navigator.pop(ctx);
                    showAuthSuccess(context, 'Reset link sent! Check your email.');
                  }
                } on Exception catch (e) {
                  if (mounted) showAuthError(context, e.toString());
                }
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─── Social sign-in button (Google) ──────────────────────────────────────────
class _SocialSection extends StatelessWidget {
  final VoidCallback onGoogle;
  final String? loadingProvider;

  const _SocialSection({
    required this.onGoogle,
    this.loadingProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Google
        SocialAuthButton(
          label: 'Continue with Google',
          onPressed: loadingProvider == null ? onGoogle : null,
          icon: loadingProvider == 'google'
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.textSecondary)),
                )
              : SvgPicture.asset('assets/icons/google.svg',
                  width: 20, height: 20),
        ),
      ],
    );
  }
}
