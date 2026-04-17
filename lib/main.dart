import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'service_repository.dart';
import 'service_detail_screen.dart';
import 'service_edit_screen.dart';
import 'settings_screen.dart';
import 'home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  runApp(const HomelabHelper());
}

//Centralne boje aplikacije
class AppColors {
  static const primary = Color(0xFF1565C0);
  static const primaryDark = Color(0xFF0D47A1);
  static const accent = Color(0xFF42A5F5);

  static const lightBackground = Color(0xFFE3F2FD);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightInputFill = Color(0xFFEBF5FE);

  static const darkBackground = Color(0xFF0A1929);
  static const darkSurface = Color(0xFF132F4C);
  static const darkInputFill = Color(0xFF173A5E);
}

class HomelabHelper extends StatefulWidget {
  const HomelabHelper({super.key});

  @override
  State<HomelabHelper> createState() => _HomelabHelperState();
}

class _HomelabHelperState extends State<HomelabHelper> {
  ThemeMode _themeMode = ThemeMode.system;
  final ServiceRepository _repository = ServiceRepository();

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  //Zajednička dekoracija za input polja
  static InputDecorationTheme _inputTheme(Color fill, Color border) {
    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border.withOpacity(0.4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border.withOpacity(0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Homelab Helper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(primary: AppColors.primary, surface: AppColors.lightSurface),
        scaffoldBackgroundColor: AppColors.lightBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        cardTheme: CardThemeData(
          color: AppColors.lightSurface,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        inputDecorationTheme: _inputTheme(
          AppColors.lightInputFill,
          AppColors.primary,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: AppColors.primary.withOpacity(0.15),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ).copyWith(primary: AppColors.accent, surface: AppColors.darkSurface),
        scaffoldBackgroundColor: AppColors.darkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkSurface,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        cardTheme: CardThemeData(
          color: AppColors.darkSurface,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        inputDecorationTheme: _inputTheme(
          AppColors.darkInputFill,
          AppColors.accent,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: AppColors.accent.withOpacity(0.15),
        ),
      ),
      themeMode: _themeMode,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => _SplashScreen(repository: _repository),
        '/': (context) => HomeScreen(repository: _repository),
      },
      onGenerateRoute: (settings) {
        if (settings.name == ServiceDetailScreen.routeName) {
          final args = settings.arguments as ServiceDetailArgs;
          return MaterialPageRoute(
            builder: (_) => ServiceDetailScreen(
              repository: _repository,
              serviceId: args.serviceId,
            ),
          );
        } else if (settings.name == ServiceEditScreen.routeName) {
          final args = settings.arguments as ServiceEditArgs;
          return MaterialPageRoute(
            builder: (_) => ServiceEditScreen(
              repository: _repository,
              existingService: args.existingService,
            ),
          );
        } else if (settings.name == SettingsScreen.routeName) {
          return MaterialPageRoute(
            builder: (_) => SettingsScreen(
              currentThemeMode: _themeMode,
              onThemeModeChanged: _setThemeMode,
              repository: _repository,
            ),
          );
        }
        return null;
      },
    );
  }
}

//Splash screen koji se prikazuje pri pokretanju aplikacije
class _SplashScreen extends StatefulWidget {
  final ServiceRepository repository;
  const _SplashScreen({required this.repository});

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted)
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Image.asset(
                      'logo.png',
                      width: 108,
                      height: 108,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Homelab Helper',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 56),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white.withOpacity(0.6),
                    ),
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
