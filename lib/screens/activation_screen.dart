import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../main.dart';
import '../services/background.dart';
import '../services/license.dart';
import '../widgets/brand.dart';

/// Shown until this device carries a valid key. The device id is displayed so
/// the person can send it over; a key issued for any other device is rejected.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _ctl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await License.activate(_ctl.text);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.message;
      });
      return;
    }

    // Bring the app up right here. Doing this from the splash screen's context
    // did nothing, because that widget was already gone by then — which is why
    // it only opened after a restart.
    setState(() => _error = null);
    await store.load();
    if (store.backgroundEnabled) await Background.enable();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const Shell()),
    );
  }

  Future<void> _copyRequest() async {
    await Clipboard.setData(ClipboardData(text: License.requestCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Request code copied - send it to get your key'),
        margin: EdgeInsets.all(14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
            child: Column(
              children: [
                const BrandMark(size: 130, showTagline: true, light: true),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Activate this device',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text(
                        'Copy the request code below and send it over. You will get back a key '
                        'that works only on this phone and allows an agreed number of seller '
                        'accounts.',
                        style: TextStyle(fontSize: 13, color: AppColors.ink2, height: 1.45),
                      ),
                      const SizedBox(height: 18),
                      const Text('Step 1 — send this request code',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.ink2)),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: AppColors.sky,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              License.requestCode,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12.5,
                                height: 1.45,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Device: ${License.deviceId}',
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.ink2),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _copyRequest,
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.blueDeep,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(Icons.copy_rounded, size: 16),
                                  label: const Text('Copy',
                                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Step 2 — paste the key you get back',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.ink2)),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _ctl,
                        maxLines: 4,
                        minLines: 3,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                        decoration: const InputDecoration(
                          hintText: 'Paste your license key here',
                          alignLabelWithHint: true,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: AppColors.danger, fontSize: 12.7, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.otpGradient,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: TextButton(
                            onPressed: _busy ? null : _activate,
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                              foregroundColor: Colors.white,
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                : const Text('Activate',
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
