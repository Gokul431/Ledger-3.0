// lib/font_loader.dart

import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart'; // ← This import fixes debugPrint

class TamilFontLoader {
  static pw.Font? tamilRegular;
  static pw.Font? tamilBold;
  static bool _isInitialized = false;

  /// Call this once in main() — loads NotoSansTamil fonts for PDF generation
  static Future<void> initializeFonts() async {
    if (_isInitialized) return;

    try {
      final regularData = await rootBundle.load(
        "assets/fonts/NotoSansTamil-Regular.ttf",
      );
      final boldData = await rootBundle.load(
        "assets/fonts/NotoSansTamil-Bold.ttf",
      );

      tamilRegular = pw.Font.ttf(regularData);
      tamilBold = pw.Font.ttf(boldData);

      _isInitialized = true;
      debugPrint("Tamil fonts loaded successfully for PDF generation");
    } catch (e) {
      debugPrint("Failed to load Tamil fonts: $e");
      rethrow; // So main() can show a warning if needed
    }
  }

  // Easy getters (so you don't have to check for null every time)
  static pw.Font get regular => tamilRegular!;
  static pw.Font get bold => tamilBold!;
}
