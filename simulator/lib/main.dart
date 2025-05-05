import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'screens/home_page.dart';
import 'screens/login_page.dart';
import 'screens/profile_page.dart';
import 'screens/signup_page.dart';
import 'screens/device_manager_page.dart';
import 'screens/view_analysis_page.dart';
import 'screens/messages_page.dart';
import 'screens/user_selection_page.dart';
import 'dart:io' show Platform;
import 'screens/edit_profile_page.dart';

void main() {
  // Initialize WebViewPlatform for platform-specific webviews
  if (WebViewPlatform.instance == null) {
    if (Platform.isAndroid) {
      WebViewPlatform.instance = AndroidWebViewPlatform();
    } else if (Platform.isIOS) {
      WebViewPlatform.instance = WebKitWebViewPlatform();
    }
  }

  // Run the app with Provider for state management
  runApp(
    ChangeNotifierProvider(
      create: (context) => AuthProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HCE - Health Companion for Elderly',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
      ),
      initialRoute: '/home',
      routes: {
        '/home': (context) => const HomePage(),
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignUpPage(),
        '/profile': (context) => const ProfilePage(),
        '/device_manager': (context) => const DeviceManagerPage(),
        '/view_analysis': (context) => const ViewAnalysisPage(),
        '/edit_profile': (context) => EditProfilePage(),
        '/chat': (context) => MessagesPage(
              userId: Provider.of<AuthProvider>(context).userId ?? '',
              recipientId: (ModalRoute.of(context)?.settings.arguments
                      as Map<String, dynamic>?)?['recipientId'] ??
                  '',
              recipientName: (ModalRoute.of(context)?.settings.arguments
                      as Map<String, dynamic>?)?['recipientName'] ??
                  'User',
            ),
        '/user_selection': (context) => const UserSelectionPage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/profile') {
          return MaterialPageRoute(
            builder: (context) => const ProfilePage(),
          );
        }
        if (settings.name == '/messages') {
          final args = settings.arguments as Map<String, dynamic>?;
          if (args == null) {
            return MaterialPageRoute(
              builder: (context) => const Scaffold(
                body: Center(child: Text('Error: Missing message parameters')),
              ),
            );
          }
          final userId = args['userId'] as String;
          final recipientId = args['recipientId'] as String;
          final recipientName = args['recipientName'] as String;
          return MaterialPageRoute(
            builder: (context) => MessagesPage(
              userId: userId,
              recipientId: recipientId,
              recipientName: recipientName,
            ),
          );
        }
        return null;
      },
    );
  }
}

class AppConfig {
  static const String baseUrl = 'http://10.0.2.2:5000';
  static const String espUrl = 'http://10.0.2.2:5001';
}