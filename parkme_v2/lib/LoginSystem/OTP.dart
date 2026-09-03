import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../appsColor/app_theme.dart';
import '../LoginSystem/Auth_Widgets.dart';
import '../LoginSystem/Auth_Service.dart';

class OTP extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final String? displayName;

  const OTP({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.displayName,
  });

  @override
  State<OTP> createState() => _OTPState();
}

class _OTPState extends State<OTP> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  bool _isLoading   = false;
  bool _canResend   = false;
  int  _resendTimer = 60;
  Timer? _timer;

  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    setState(() { _canResend = false; _resendTimer = 60; });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendTimer == 0) {
        t.cancel();
        setState(() => _canResend = true);
      } else {
        setState(() => _resendTimer--);
      }
    });
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _verifyOTPForSignIn() async {
    if (_otp.length < 6) {
      showAuthError(context, 'Please enter the complete 6-digit OTP.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _auth.verifyOTPForSignIn(
        verificationId: widget.verificationId,
        otp: _otp,
        );
      if (mounted) {
        showAuthSuccess(context, 'Phone verified successfully!');
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } on Exception catch (e) {
      if (mounted) showAuthError(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onDigitChanged(String val, int index) {
    if (val.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (val.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    if (_otp.length == 6) _verifyOTPForSignIn();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final maskedPhone = widget.phoneNumber.replaceRange(
      4, widget.phoneNumber.length - 3, '•••• ••',
    );

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF2F8FF), AppColors.primaryNavy, AppColors.secondaryNavy],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: AppColors.textPrimary, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),

                        // Icon
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.accentBlue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppColors.accentBlue.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.sms_outlined,
                            color: AppColors.accentBlue,
                            size: 32,
                          ),
                        ),

                        const SizedBox(height: 24),

                        const Text(
                          'Verify Phone',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                            children: [
                              const TextSpan(text: 'Enter the 6-digit code sent to\n'),
                              TextSpan(
                                text: maskedPhone,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        // OTP boxes
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(6, (i) => _OTPBox(
                            controller: _controllers[i],
                            focusNode:  _focusNodes[i],
                            onChanged:  (v) => _onDigitChanged(v, i),
                            isFilled: _controllers[i].text.isNotEmpty,
                          )),
                        ),

                        const SizedBox(height: 36),

                        ParkMeButton(
                          label: 'Verify OTP',
                          isLoading: _isLoading,
                          onPressed: _verifyOTPForSignIn,
                        ),

                        const SizedBox(height: 28),

                        Center(
                          child: _canResend
                              ? TextButton(
                                  onPressed: () {
                                    // In production: call sendOtp again with resend token
                                    _startResendTimer();
                                    showAuthSuccess(context, 'OTP resent!');
                                  },
                                  child: const Text(
                                    'Resend OTP',
                                    style: TextStyle(
                                      color: AppColors.accentBlue,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      color: AppColors.textHint,
                                      fontSize: 13,
                                    ),
                                    children: [
                                      const TextSpan(text: 'Resend code in '),
                                      TextSpan(
                                        text: '${_resendTimer}s',
                                        style: const TextStyle(
                                          color: AppColors.accentBlue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),

                        const Spacer(),

                        // Security note
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.cardNavy,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.inputBorder),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.security_rounded,
                                  color: AppColors.accentBlue, size: 18),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Never share your OTP with anyone. '
                                  'ParkMe will never ask for it.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    height: 1.4,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OTPBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool isFilled;

  const _OTPBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.isFilled,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 56,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: onChanged,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: isFilled
              ? AppColors.accentBlue.withValues(alpha: 0.15)
              : AppColors.inputFill,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isFilled
                  ? AppColors.accentBlue
                  : AppColors.inputBorder,
              width: 1.5,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isFilled
                  ? AppColors.accentBlue
                  : AppColors.inputBorder,
              width: isFilled ? 1.8 : 1.2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.accentBlue, width: 2,
            ),
          ),
        ),
      ),
    );
  }
}
