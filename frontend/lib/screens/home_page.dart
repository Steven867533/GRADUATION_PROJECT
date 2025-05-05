import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Access the AuthProvider to check authentication state
    final authProvider = Provider.of<AuthProvider>(context);

    // If the user is logged in, redirect to ProfilePage
    if (authProvider.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/profile');
      });
      return const SizedBox.shrink(); // Temporary widget while redirecting
    }

    // If not logged in, show the landing page
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue, Colors.lightBlueAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Card(
              elevation: 10,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              color: Colors.white.withAlpha((0.2 * 255).round()), // Updated glassmorphism effect
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App Title
                    const Text(
                      'HCE - Health Companion for Elderly',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            offset: Offset(2, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    )
                        .animate()
                        .fadeIn(duration: 1000.ms)
                        .slideY(begin: Offset(0, -0.2).dy),
                    const SizedBox(height: 10),
                    const Text(
                      'Monitor heart rate and blood pressure with ESP hardware',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    )
                        .animate()
                        .fadeIn(duration: 1000.ms)
                        .slideY(begin: Offset(0, 0.2).dy, delay: 200.ms),
                    const SizedBox(height: 40),

                    // Animated Icons Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Chart Analysis Icon
                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [Colors.white24, Colors.transparent],
                                  center: Alignment.center,
                                  radius: 0.8,
                                ),
                              ),
                              child: const Icon(
                                Icons.insert_chart,
                                size: 60,
                                color: Colors.white,
                              ).animate(
                                onPlay: (controller) => controller.repeat(),
                              ).scale(
                                duration: 800.ms,
                                begin: const Offset(1.0,1.0),
                                end: const Offset(1.2,1.2),
                                curve: Curves.easeInOut,
                              ).then().scale(
                                duration: 400.ms,
                                begin: const Offset(1.2,1.2),
                                end: const Offset(1.0,1.0),
                                curve: Curves.easeInOut,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Chart Analysis',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        // Companion Icon
                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [Colors.white24, Colors.transparent],
                                  center: Alignment.center,
                                  radius: 0.8,
                                ),
                              ),
                              child: const Icon(
                                Icons.people,
                                size: 60,
                                color: Colors.white,
                              ).animate(
                                onPlay: (controller) => controller.repeat(),
                              ).scale(
                                duration: 800.ms,
                                begin: const Offset(1.0,1.0),
                                end: const Offset(1.2,1.2),
                                curve: Curves.easeInOut,
                              ).then().scale(
                                duration: 400.ms,
                                begin: const Offset(1.2,1.2),
                                end: const Offset(1.0,1.0),
                                curve: Curves.easeInOut,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Companions',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        // Patients Icon
                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [Colors.white24, Colors.transparent],
                                  center: Alignment.center,
                                  radius: 0.8,
                                ),
                              ),
                              child: const Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.white,
                              ).animate(
                                onPlay: (controller) => controller.repeat(),
                              ).scale(
                                duration: 800.ms,
                                begin: const Offset(1.0,1.0),
                                end: const Offset(1.2,1.2),
                                curve: Curves.easeInOut,
                              ).then().scale(
                                duration: 400.ms,
                                begin: const Offset(1.2,1.2),
                                end: const Offset(1.0,1.0),
                                curve: Curves.easeInOut,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Patients',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 60),

                    // Login Button
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.blue, Colors.blueAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            offset: Offset(0, 4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/login');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          'Login to Continue',
                          style: TextStyle(
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ).animate().fadeIn(duration: 1000.ms).scale(delay: 800.ms),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}