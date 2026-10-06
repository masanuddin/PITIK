import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ==================== APPLE STYLE COLORS ====================
class AppleColors {
  static const Color systemBackground = Color(0xFFF2F2F7);
  static const Color secondaryBackground = Colors.white;
  static const Color label = Color(0xFF000000);
  static const Color secondaryLabel = Color(0xFF8E8E93);
  static const Color tertiaryLabel = Color(0xFFC7C7CC);
  static const Color systemBlue = Color(0xFF007AFF);
  static const Color systemGreen = Color(0xFF34C759);
  static const Color systemRed = Color(0xFFFF3B30);
  static const Color separator = Color(0xFFE5E5EA);
  static const Color fill = Color(0xFFE5E5EA);
}

// ==================== APPLE STYLE TEXT FIELD ====================
class AppleTextField extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final IconData? prefixIcon;
  final Widget? prefix;
  final bool obscureText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? errorText;
  final bool autofocus;
  final Function(String)? onChanged;
  final int? maxLength;

  const AppleTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.prefixIcon,
    this.prefix,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.errorText,
    this.autofocus = false,
    this.onChanged,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppleColors.secondaryBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: errorText != null ? AppleColors.systemRed : AppleColors.separator,
              width: 1,
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            autofocus: autofocus,
            onChanged: onChanged,
            maxLength: maxLength,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              color: AppleColors.label,
              letterSpacing: -0.4,
            ),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w400,
                color: AppleColors.secondaryLabel,
                letterSpacing: -0.4,
              ),
              prefixIcon: prefix ?? (prefixIcon != null
                  ? Icon(prefixIcon, color: AppleColors.secondaryLabel, size: 22)
                  : null),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              counterText: '',
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              errorText!,
              style: const TextStyle(
                fontSize: 13,
                color: AppleColors.systemRed,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ==================== APPLE STYLE PHONE INPUT ====================
class ApplePhoneInput extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final Function(String)? onChanged;

  const ApplePhoneInput({
    super.key,
    required this.controller,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppleColors.secondaryBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: errorText != null ? AppleColors.systemRed : AppleColors.separator,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Country code prefix
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: AppleColors.separator, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Indonesia flag emoji
                    const Text('🇮🇩', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    const Text(
                      '+62',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: AppleColors.label,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
              // Phone number input
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  onChanged: onChanged,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(13),
                  ],
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    color: AppleColors.label,
                    letterSpacing: 0.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: '812 3456 7890',
                    hintStyle: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                      color: AppleColors.tertiaryLabel,
                      letterSpacing: 0.5,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              errorText!,
              style: const TextStyle(
                fontSize: 13,
                color: AppleColors.systemRed,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ==================== APPLE STYLE PRIMARY BUTTON ====================
class ApplePrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? textColor;

  const ApplePrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? AppleColors.label,
          foregroundColor: textColor ?? Colors.white,
          disabledBackgroundColor: AppleColors.tertiaryLabel,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
      ),
    );
  }
}

// ==================== APPLE STYLE SECONDARY BUTTON ====================
class AppleSecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const AppleSecondaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppleColors.label,
          side: const BorderSide(color: AppleColors.separator, width: 1),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppleColors.label),
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
      ),
    );
  }
}

// ==================== APPLE STYLE TEXT BUTTON ====================
class AppleTextButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color? color;

  const AppleTextButton({
    super.key,
    required this.text,
    this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color ?? AppleColors.systemBlue,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          color: color ?? AppleColors.systemBlue,
          letterSpacing: -0.4,
        ),
      ),
    );
  }
}

// ==================== APPLE STYLE OTP INPUT ====================
class AppleOTPInput extends StatefulWidget {
  final int length;
  final Function(String) onCompleted;
  final Function(String)? onChanged;

  const AppleOTPInput({
    super.key,
    this.length = 6,
    required this.onCompleted,
    this.onChanged,
  });

  @override
  State<AppleOTPInput> createState() => _AppleOTPInputState();
}

class _AppleOTPInputState extends State<AppleOTPInput> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _onChanged(int index, String value) {
    if (value.length == 1 && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    
    widget.onChanged?.call(_otp);
    
    if (_otp.length == widget.length) {
      widget.onCompleted(_otp);
    }
  }

  // Backspace di kotak kosong → pindah ke kotak sebelumnya.
  KeyEventResult _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    return KeyEventResult.ignored; // tetap diteruskan ke TextField
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.length, (index) {
        return Container(
          width: 48,
          height: 56,
          margin: EdgeInsets.only(
            left: index == 0 ? 0 : 8,
            right: index == widget.length - 1 ? 0 : 8,
          ),
          decoration: BoxDecoration(
            color: AppleColors.secondaryBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focusNodes[index].hasFocus
                  ? AppleColors.systemBlue
                  : AppleColors.separator,
              width: _focusNodes[index].hasFocus ? 2 : 1,
            ),
          ),
          // Focus pembungkus menerima key event yang naik dari TextField,
          // tanpa memakai FocusNode yang sama dua kali.
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, event) => _onKeyEvent(index, event),
            child: TextField(
              controller: _controllers[index],
              focusNode: _focusNodes[index],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 1,
              onChanged: (value) => _onChanged(index, value),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppleColors.label,
              ),
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ==================== APPLE STYLE LOGO ====================
class PitikLogo extends StatelessWidget {
  final double size;

  const PitikLogo({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo image
        Image.asset(
          'assets/images/pitik.png',
          width: size * 2,    // dikali 2 biar lebih besar, sesuaikan sesukamu
          height: size * 2,
          fit: BoxFit.contain,
        ),

        const SizedBox(height: 8),

        // Subtitle (teks "PITIK" dihapus karena sudah ada di gambar)
        const Text(
          'IoT Climate Control',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: AppleColors.secondaryLabel,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}