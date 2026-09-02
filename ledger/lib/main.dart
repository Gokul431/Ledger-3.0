import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'ledgerlist.dart';
import 'splashscreen.dart';
import 'firebase_options.dart';
import 'font_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style globally
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
    // Optionally handle initialization failure (e.g., show error screen)
  }

  runApp(const MyApp());

  // Tamil fonts are only needed when exporting a PDF, so parsing them is
  // deferred until after the first frame instead of blocking startup. The PDF
  // service awaits TamilFontLoader.ensureLoaded() before it builds a document,
  // so an export that happens before this finishes still gets the fonts.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    TamilFontLoader.ensureLoaded().catchError((Object e) {
      debugPrint('Warning: Failed to load Tamil fonts for PDF: $e');
      // Continue running even if fonts fail to load.
    });
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ledger App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF455A64),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1A1A2E),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF455A64),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF455A64),
          foregroundColor: Colors.white,
        ),
        // Caps every AlertDialog/Dialog in the app to a comfortable width
        // instead of growing with screen size — on tablets, dialogs with a
        // Row of Expanded buttons would otherwise stretch almost edge to
        // edge. A no-op for dialogs already narrower than this on phones.
        dialogTheme: const DialogThemeData(
          constraints: BoxConstraints(maxWidth: 440),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF455A64),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
