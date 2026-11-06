import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'providers/pos_provider.dart';
import 'screens/main_wrapper_screen.dart';
import 'theme/app_theme.dart';
import 'services/app_release_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    // Configure persistence before either POS sync or release checks use Firestore.
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  } catch (e) {
    debugPrint('Firebase initialization notice: $e');
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  await initializeDateFormatting('id_ID', null);

  runApp(const KasirSuperApp());
}

class KasirSuperApp extends StatelessWidget {
  const KasirSuperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PosProvider()),
        ChangeNotifierProvider(create: (_) => AppReleaseService()..initialize(), lazy: false),
      ],
      child: MaterialApp(
        title: 'Warloc',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, child) => DisplayFeatureSubScreen(child: child!),
        home: const MainWrapperScreen(),
      ),
    );
  }
}
