import 'package:flutter/material.dart';

class AppInput extends StatefulWidget {
  const AppInput({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
    this.suffixIcon,
    this.onChanged,
    this.textInputAction,
    this.autocorrect = true,
    this.maxLength,
    this.decoration,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final bool autocorrect;
  final int? maxLength;
  final InputDecoration? decoration;

  @override
  State<AppInput> createState() => _AppInputState();
}

class _AppInputState extends State<AppInput> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  void didUpdateWidget(covariant AppInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.obscureText) {
      _obscured = false;
    } else if (!oldWidget.obscureText && widget.obscureText) {
      _obscured = true;
    }
  }

  InputDecoration _buildDecoration() {
    final base = widget.decoration ??
        InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
        );

    if (!widget.obscureText) {
      return base.copyWith(suffixIcon: widget.suffixIcon ?? base.suffixIcon);
    }

    return base.copyWith(
      suffixIcon: IconButton(
        tooltip: _obscured ? 'Show password' : 'Hide password',
        onPressed: () => setState(() => _obscured = !_obscured),
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      obscureText: _obscured,
      maxLines: widget.maxLines,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      onChanged: widget.onChanged,
      textInputAction: widget.textInputAction,
      autocorrect: widget.autocorrect,
      maxLength: widget.maxLength,
      decoration: _buildDecoration(),
    );
  }
}

/// Password field with outline border and show/hide toggle.
class AppPasswordField extends StatelessWidget {
  const AppPasswordField({
    super.key,
    required this.controller,
    this.labelText,
    this.helperText,
    this.counterText,
    this.textInputAction,
    this.maxLength,
    this.decoration,
  });

  final TextEditingController controller;
  final String? labelText;
  final String? helperText;
  final String? counterText;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    return AppInput(
      controller: controller,
      label: labelText ?? 'Password',
      obscureText: true,
      textInputAction: textInputAction,
      maxLength: maxLength,
      autocorrect: false,
      decoration: decoration ??
          InputDecoration(
            labelText: labelText,
            helperText: helperText,
            counterText: counterText,
            border: const OutlineInputBorder(),
          ),
    );
  }
}

class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    );
  }
}
