import 'package:flutter/material.dart';

/// KitaKo App Color Constants
/// Based on Figma design specifications
class AppColors {
  AppColors._(); // Private constructor to prevent instantiation

  // Primary Colors
  static const Color primary = Color(0xFF4A90E2);
  static const Color primaryLight = Color(0xFF5BA3F5);
  static const Color primaryDark = Color(0xFF1E3A5F);

  // Background Colors
  static const Color background = Color(0xFF1A1A1A);
  static const Color backgroundDark = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF2A2A2A);
  static const Color surfaceLight = Color(0xFF3A3A3A);
  static const Color surfaceDark = Color(0xFF2A2A2A);

  // Text Colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF666666);
  static const Color textHint = Color(0xFF666666);

  // Accent Colors
  static const Color accent = Color(0xFF4A90E2);
  static const Color accentLight = Color(0xFF5BA3F5);

  // UI Element Colors
  static const Color border = Color(0xFF3A3A3A);
  static const Color divider = Color(0xFF2A2A2A);
  static const Color shadow = Colors.black;

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFE53935);
  static const Color warning = Color(0xFFFFA726);
  static const Color info = Color(0xFF29B6F6);

  // Placeholder Colors (for gallery items)
  static const List<Color> placeholderGradient = [
    Color(0xFF3A3A3A),
    Color(0xFF4A4A4A),
    Color(0xFF2A2A2A),
    Color(0xFF5A5A5A),
  ];
}

/// KitaKo App Text Styles
class AppTextStyles {
  AppTextStyles._(); // Private constructor

  // App Bar
  static const TextStyle appBarTitle = TextStyle(
    color: AppColors.primaryDark,
    fontSize: 24,
    fontWeight: FontWeight.bold,
  );

  // Headings
  static const TextStyle heading1 = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 24,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle heading2 = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle heading3 = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  // Body Text
  static const TextStyle bodyLarge = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle bodyMedium = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle bodySmall = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.normal,
  );

  // Special
  static const TextStyle hint = TextStyle(
    color: AppColors.textHint,
    fontSize: 16,
  );

  static const TextStyle button = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
}

/// KitaKo App Dimensions and Spacing
class AppDimensions {
  AppDimensions._(); // Private constructor

  // Padding
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  // Border Radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 20.0;
  static const double radiusXLarge = 30.0;

  // Icon Sizes
  static const double iconSmall = 20.0;
  static const double iconMedium = 24.0;
  static const double iconLarge = 28.0;
  static const double iconXLarge = 40.0;

  // Grid
  static const int gridColumnCount = 3;
  static const double gridSpacing = 8.0;
  static const double gridAspectRatio = 1.0;

  // Logo
  static const double logoSize = 150.0;
  static const double logoCircleSmall = 20.0;
  static const double logoCircleMedium = 35.0;
  static const double logoCircleLarge = 60.0;
}
