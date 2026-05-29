import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/palette.dart';
/// Shown once on first launch, before the EULA.
/// Requests photo library and camera access, then calls [onComplete]
/// regardless of whether the user grants or denies.
class PermissionScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const PermissionScreen({super.key, required this.onComplete});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _requesting = false;

  Future<void> _requestPermissions() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      // Gallery / photo library — photo_manager handles Android version differences
      await PhotoManager.requestPermissionExtend();
      // Camera — explicit request via permission_handler
      await Permission.camera.request();
    } finally {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('permissions_requested', true);
      if (mounted) widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg      = P.bg(isDark);
    final bgDeep  = isDark ? const Color(0xFF070A0E) : const Color(0xFFE8EEF6);
    final surface = P.surface(isDark);
    final border  = P.border(isDark);
    final hairline= isDark ? const Color(0x1F60A5FA) : const Color(0x192563EB);
    final blue    = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
    final blueSoft= isDark ? const Color(0x2E3B82F6) : const Color(0xFFDBEAFE);
    final blueGlow= isDark ? const Color(0x593B82F6) : const Color(0x2E2563EB);
    final textColor = P.text(isDark);
    final textDim = isDark ? const Color(0xC7FFFFFF) : const Color(0xFF475569);
    final textMore= P.textMore(isDark);
    final textFaint=P.textFaint(isDark);

    return Scaffold(
      backgroundColor: bgDeep,
      body: Column(
        children: [
          // -- Top brand band --------------------------------------------------
          Container(
            color: bg,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
                decoration:
                    BoxDecoration(border: Border(bottom: BorderSide(color: hairline))),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/images/logo.svg',
                      width: 40,
                      height: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('BEFORE YOU START',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: blue,
                              )),
                          const SizedBox(height: 2),
                          Text('App Permissions',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                                letterSpacing: -0.2,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // -- Body ------------------------------------------------------------
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KitaKo needs the following permissions to work. '
                    'Your photos never leave your device.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: textDim,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Photos card
                  _PermissionCard(
                    icon: Icons.photo_library_outlined,
                    title: 'Photos & Storage',
                    description:
                        'Required to index and search your photo library. '
                        'KitaKo processes all images on-device — '
                        'nothing is uploaded or shared.',
                    required: true,
                    blue: blue,
                    blueSoft: blueSoft,
                    surface: surface,
                    border: border,
                    textColor: textColor,
                    textMore: textMore,
                  ),

                  const SizedBox(height: 12),

                  // Camera card
                  _PermissionCard(
                    icon: Icons.camera_alt_outlined,
                    title: 'Camera',
                    description:
                        'Lets you search by taking a photo on the spot. '
                        'Optional — you can still use the app without it.',
                    required: false,
                    blue: blue,
                    blueSoft: blueSoft,
                    surface: surface,
                    border: border,
                    textColor: textColor,
                    textMore: textMore,
                  ),


                  const SizedBox(height: 32),

                  // Note
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: blueSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: hairline),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 15, color: blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You can update these permissions at any time in '
                            'your device Settings → Apps → KitaKo.',
                            style: TextStyle(
                                fontSize: 12, height: 1.5, color: textColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // -- Footer ----------------------------------------------------------
          Container(
            color: bg,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  children: [
                    Container(height: 1, color: hairline),
                    const SizedBox(height: 14),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: blueGlow,
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _requesting ? null : _requestPermissions,
                          style: FilledButton.styleFrom(
                            backgroundColor: blue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                          child: _requesting
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: P.onAccent(isDark),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Text('Grant Permissions'),
                                    SizedBox(width: 8),
                                    Icon(Icons.north_east, size: 16),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _requesting ? null : _requestPermissions,
                      style: TextButton.styleFrom(
                        foregroundColor: textFaint,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('Skip for now',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Permission card ------------------------------------------------------------

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool required;
  final Color blue;
  final Color blueSoft;
  final Color surface;
  final Color border;
  final Color textColor;
  final Color textMore;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.required,
    required this.blue,
    required this.blueSoft,
    required this.surface,
    required this.border,
    required this.textColor,
    required this.textMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: blueSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: required
                            ? blue.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: required
                              ? blue.withValues(alpha: 0.3)
                              : border,
                        ),
                      ),
                      child: Text(
                        required ? 'Required' : 'Optional',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: required ? blue : textMore,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(description,
                    style: TextStyle(
                      color: textMore,
                      fontSize: 12,
                      height: 1.4,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
