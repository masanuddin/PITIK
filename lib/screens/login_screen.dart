import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../services/auth_service.dart';
import '../widgets/auth_widgets.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  late final TapGestureRecognizer _termsRecognizer1;
  late final TapGestureRecognizer _termsRecognizer2;

  @override
  void initState() {
    super.initState();
    _termsRecognizer1 = TapGestureRecognizer()..onTap = () {};
    _termsRecognizer2 = TapGestureRecognizer()..onTap = () {};
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _termsRecognizer1.dispose();
    _termsRecognizer2.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  bool _validatePhone() {
    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      setState(() => _errorText = 'Nomor telepon tidak boleh kosong');
      return false;
    }

    if (phone.length < 9) {
      setState(() => _errorText = 'Nomor telepon minimal 9 digit');
      return false;
    }

    return true;
  }

  Future<void> _sendOTP() async {
    if (!_validatePhone()) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final phoneNumber = AuthService.formatPhoneNumber(_phoneController.text);

    await AuthService.sendOTP(
      phoneNumber: phoneNumber,
      onCodeSent: (verificationId) {
        setState(() => _isLoading = false);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OTPScreen(
              phoneNumber: phoneNumber,
              verificationId: verificationId,
            ),
          ),
        );
      },
      onError: (error) {
        setState(() {
          _isLoading = false;
          _errorText = error;
        });
      },
    );
  }

  Future<void> _continueAsGuest() async {
    setState(() => _isLoading = true);

    final result = await AuthService.signInAnonymously();

    setState(() => _isLoading = false);

    if (!result['success']) {
      setState(() => _errorText = result['error']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppleColors.systemBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),

              const PitikLogo(size: 80),

              const SizedBox(height: 48),

              const Text(
                'Masuk ke Akun',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppleColors.label,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Masukkan nomor telepon untuk menerima kode OTP',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: AppleColors.secondaryLabel,
                  letterSpacing: -0.2,
                ),
              ),

              const SizedBox(height: 40),

              ApplePhoneInput(
                controller: _phoneController,
                errorText: _errorText,
                onChanged: (_) => _clearError(),
              ),

              const SizedBox(height: 24),

              ApplePrimaryButton(
                text: 'Kirim Kode OTP',
                isLoading: _isLoading,
                onPressed: _sendOTP,
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  const Expanded(child: Divider(color: AppleColors.separator)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'atau',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppleColors.secondaryLabel,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: AppleColors.separator)),
                ],
              ),

              const SizedBox(height: 16),

              AppleSecondaryButton(
                text: 'Lanjut sebagai Tamu',
                isLoading: _isLoading,
                onPressed: _continueAsGuest,
              ),

              const SizedBox(height: 32),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppleColors.secondaryLabel,
                      height: 1.4,
                    ),
                    children: [
                      const TextSpan(
                        text: 'Dengan melanjutkan, Anda menyetujui ',
                      ),
                      TextSpan(
                        text: 'Ketentuan Layanan',
                        style: TextStyle(
                          color: AppleColors.systemBlue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: _termsRecognizer1,
                      ),
                      const TextSpan(text: ' dan '),
                      TextSpan(
                        text: 'Kebijakan Privasi',
                        style: TextStyle(
                          color: AppleColors.systemBlue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: _termsRecognizer2,
                      ),
                      const TextSpan(text: ' kami.'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
