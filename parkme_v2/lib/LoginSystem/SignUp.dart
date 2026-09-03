import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../appsColor/app_theme.dart';
import '../LoginSystem/Auth_Widgets.dart';
import '../LoginSystem/Auth_Service.dart';
import 'Login.dart';
import 'otp.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  // Email form
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  // Phone form
  final _phoneNameCtrl = TextEditingController();
  final _phoneCtrl     = TextEditingController();

  bool _isLoading       = false;
  bool _socialLoad      = false;
  bool _agreeTerms      = false;
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
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _phoneNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ─── Email sign-up ────────────────────────────────────────────────────────
  Future<void> _signUpWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeTerms) {
      showAuthError(context, 'Please agree to the Terms of Service.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _auth.signUpWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        displayName: _nameCtrl.text.trim(),
      );
      if (mounted) {
        showAuthSuccess(
          context,
          'Your account has been created! Please verify your email.',
        );
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } on Exception catch (e) {
      if (mounted) showAuthError(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Phone sign-up (sends OTP) ────────────────────────────────────────────
  Future<void> _signUpWithPhone() async {
    if (_phoneNameCtrl.text.trim().isEmpty) {
      showAuthError(context, 'Please enter your username.');
      return;
    }
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 9) {
      showAuthError(context, 'Please enter your phone number.');
      return;
    }
    if (!_agreeTerms) {
      showAuthError(context, 'Please agree to the Terms of Service.');
      return;
    }
    setState(() => _isLoading = true);
    final fullPhone = '+60$phone';

    await _auth.sentOTP(
      phoneNumber: fullPhone,
      onAutoVerified: (_) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      },
      onFailed: (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          // Show the error CODE so the exact cause is clear
          // (e.g. missing-client-identifier, billing-not-enabled…).
          showAuthError(context, 'OTP failed [${e.code}]: ${e.message ?? ''}');
        }
      },
      onCodeSent: (verificationId, _) {
        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OTP(
                phoneNumber: fullPhone,
                verificationId: verificationId,
                displayName: _phoneNameCtrl.text.trim(),
              ),
            ),
          );
        }
      },
      onTimeout: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  // ─── Social sign-up ───────────────────────────────────────────────────────
  Future<void> _socialSignUp(String provider) async {
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
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFFF2F8FF), AppColors.primaryNavy, AppColors.secondaryNavy],
              ),
            ),
          ),

          // Top-right accent blob
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentBlue.withValues(alpha: 0.08),
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
                          MaterialPageRoute(builder: (_) => const Login()),
                        ),
                        child: const Text('Sign In',
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
                          const SizedBox(height: 8),

                          // Header
                          const Text(
                            'Create Account',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Join thousands finding stress-free parking',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),

                          const SizedBox(height: 28),

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
                            height: 320,
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                // ── Email Tab ──
                                Column(
                                  children: [
                                    AuthTextField(
                                      controller: _nameCtrl,
                                      hintText: 'Full name',
                                      prefixIcon: Icons.person_outline_rounded,
                                      validator: (v) => v == null || v.isEmpty
                                          ? 'Name required' : null,
                                    ),
                                    const SizedBox(height: 14),
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
                                      hintText: 'Password (min 6 characters)',
                                      prefixIcon: Icons.lock_outline_rounded,
                                      obscureText: true,
                                      showToggle: true,
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return 'Password required';
                                        if (v.length < 6) return 'Min 6 characters';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 14),
                                    AuthTextField(
                                      controller: _confirmCtrl,
                                      hintText: 'Confirm password',
                                      prefixIcon: Icons.lock_outline_rounded,
                                      obscureText: true,
                                      showToggle: true,
                                      textInputAction: TextInputAction.done,
                                      validator: (v) {
                                        if (v != _passwordCtrl.text) return 'Passwords do not match';
                                        return null;
                                      },
                                    ),
                                  ],
                                ),

                                // ── Phone Tab ──
                                Column(
                                  children: [
                                    AuthTextField(
                                      controller: _phoneNameCtrl,
                                      hintText: 'Full name',
                                      prefixIcon: Icons.person_outline_rounded,
                                    ),
                                    const SizedBox(height: 14),
                                    PhoneTextField(controller: _phoneCtrl),
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentBlue.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.accentBlue.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: const Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.shield_outlined,
                                                  color: AppColors.accentBlue, size: 16),
                                              SizedBox(width: 8),
                                              Text(
                                                'Secure OTP Verification',
                                                style: TextStyle(
                                                  color: AppColors.accentBlue,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 6),
                                          Text(
                                            'A 6-digit OTP will be sent to your phone number. ',                                            
                                            style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                              height: 1.4,
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

                          // Terms checkbox
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _agreeTerms,
                                  onChanged: (v) =>
                                      setState(() => _agreeTerms = v ?? false),
                                  activeColor: AppColors.accentBlue,
                                  checkColor: AppColors.white,
                                  side: const BorderSide(
                                    color: AppColors.inputBorder, width: 1.5),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: RichText(
                                  text: const TextSpan(
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13),
                                    children: [
                                      TextSpan(text: 'I agree to ParkMe\'s '),
                                      TextSpan(
                                        text: 'Terms of Service',
                                        style: TextStyle(
                                            color: AppColors.accentBlue,
                                            fontWeight: FontWeight.w500),
                                      ),
                                      TextSpan(text: ' and '),
                                      TextSpan(
                                        text: 'Privacy Policy',
                                        style: TextStyle(
                                            color: AppColors.accentBlue,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // CTA
                          ParkMeButton(
                            label: _tabController.index == 0
                                ? 'Create Account'
                                : 'Send OTP',
                            isLoading: _isLoading,
                            onPressed: () {
                              if (_tabController.index == 0) {
                                _signUpWithEmail();
                              } else {
                                _signUpWithPhone();
                              }
                            },
                          ),

                          const SizedBox(height: 28),
                          const LabeledDivider(label: 'or sign up with'),
                          const SizedBox(height: 24),

                          // Social buttons
                          _SocialRow(
                            onGoogle:   () => _socialSignUp('google'),
                            loadingProvider: _socialLoad ? _socialProvider : null,
                          ),

                          const SizedBox(height: 32),

                          Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Already have an account? ',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const Login()),
                                  ),
                                  child: const Text(
                                    'Sign In',
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
}

// ─── Google social sign-up button ────────────────────────────────────────────
class _SocialRow extends StatelessWidget {
  final VoidCallback onGoogle;
  final String? loadingProvider;

  const _SocialRow({
    required this.onGoogle,
    this.loadingProvider,
  });

  @override
  Widget build(BuildContext context) {
    return _IconSocialBtn(
      label: 'Continue with Google',
      icon: SvgPicture.asset('assets/icons/google.svg', width: 20, height: 20),
      loading: loadingProvider == 'google',
      onPressed: loadingProvider == null ? onGoogle : null,
    );
  }
}

class _IconSocialBtn extends StatelessWidget {
  final String label;
  final Widget icon;
  final bool loading;
  final VoidCallback? onPressed;

  const _IconSocialBtn({
    required this.label,
    required this.icon,
    required this.loading,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.cardNavy,
        side: const BorderSide(color: AppColors.inputBorder, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: loading
          ? const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppColors.textSecondary),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
    );
  }
}
