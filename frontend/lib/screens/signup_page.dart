import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:another_flushbar/flushbar.dart'; // Import Flushbar
import '../providers/auth_provider.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  SignUpPageState createState() => SignUpPageState();
}

class SignUpPageState extends State<SignUpPage> {
  // Controllers
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController birthdateController = TextEditingController();
  final TextEditingController patientPhoneController = TextEditingController();
  final TextEditingController companionPhoneController =
      TextEditingController();
  final TextEditingController doctorPhoneController = TextEditingController();

  // State variables
  String _selectedRole = 'Companion';
  String? _bloodPressureType;
  bool _isLoading = false;

  // Constants
  static const Color whiteBackground = Color.fromRGBO(255, 255, 255, 0.9);

  // Validate phone number format
  String? _validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional field for relationships
    }
    // Basic validation for international format (should start with +)
    if (!value.startsWith('+')) {
      return 'Phone number should start with + (e.g., +20123456789)';
    }
    return null;
  }

  // Sign up function
  Future<void> _signUp() async {
    if (_isLoading) return;

    // Validate required fields
    if (nameController.text.isEmpty ||
        emailController.text.isEmpty ||
        passwordController.text.isEmpty ||
        phoneController.text.isEmpty ||
        birthdateController.text.isEmpty ||
        (_selectedRole == 'Patient' && _bloodPressureType == null)) {
      _showErrorMessage('Please fill in all required fields');
      return;
    }

    // Validate phone number format
    if (!phoneController.text.startsWith('+')) {
      _showErrorMessage(
          'Phone number should start with + (e.g., +20123456789)');
      return;
    }

    // Validate relationship phone numbers if provided
    if (_selectedRole == 'Companion' &&
        patientPhoneController.text.isNotEmpty &&
        !patientPhoneController.text.startsWith('+')) {
      _showErrorMessage(
          'Patient phone number should start with + (e.g., +20123456789)');
      return;
    }

    if (_selectedRole == 'Patient') {
      if (companionPhoneController.text.isNotEmpty &&
          !companionPhoneController.text.startsWith('+')) {
        _showErrorMessage(
            'Companion phone number should start with + (e.g., +20123456789)');
        return;
      }

      if (doctorPhoneController.text.isNotEmpty &&
          !doctorPhoneController.text.startsWith('+')) {
        _showErrorMessage(
            'Doctor phone number should start with + (e.g., +20123456789)');
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final result = await authProvider.signUp(
      name: nameController.text,
      email: emailController.text,
      password: passwordController.text,
      phoneNumber: phoneController.text,
      birthdate: birthdateController.text,
      role: _selectedRole,
      bloodPressureType: _selectedRole == 'Patient' ? _bloodPressureType : null,
      patientPhoneNumber:
          _selectedRole == 'Companion' ? patientPhoneController.text : null,
      companionPhoneNumber:
          _selectedRole == 'Patient' ? companionPhoneController.text : null,
      doctorPhoneNumber:
          _selectedRole == 'Patient' ? doctorPhoneController.text : null,
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success']) {
      // Show success message (bottom SnackBar)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signup successful! Please log in.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      _showErrorMessage(
          result['message'] ?? 'Signup failed. Please try again.');
    }
  }

  void _showErrorMessage(String message) {
    // Show error message at the top using Flushbar
    Flushbar(
      message: message,
      messageSize: 18, // Larger font for elderly users
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 5), // Hides after 5 seconds
      flushbarPosition: FlushbarPosition.TOP, // Display at the top
      margin: const EdgeInsets.all(8),
      borderRadius: BorderRadius.circular(8),
      icon: const Icon(
        Icons.error_outline,
        size: 28,
        color: Colors.white,
      ),
      leftBarIndicatorColor: Colors.white,
      dismissDirection: FlushbarDismissDirection.HORIZONTAL, // Swipe to dismiss
    ).show(context);
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    birthdateController.dispose();
    patientPhoneController.dispose();
    companionPhoneController.dispose();
    doctorPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'HCE Sign Up',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 30),

                // Role Selection
                const Text(
                  'Select your role:',
                  style: TextStyle(fontSize: 20, color: Colors.white),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Radio<String>(
                      value: 'Companion',
                      groupValue: _selectedRole,
                      onChanged: (value) {
                        setState(() {
                          _selectedRole = value!;
                        });
                      },
                      activeColor: Colors.white,
                    ),
                    const Text(
                      'Companion',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    Radio<String>(
                      value: 'Patient',
                      groupValue: _selectedRole,
                      onChanged: (value) {
                        setState(() {
                          _selectedRole = value!;
                        });
                      },
                      activeColor: Colors.white,
                    ),
                    const Text(
                      'Patient',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Image Upload Placeholder
                Container(
                  height: 100,
                  width: 100,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: whiteBackground,
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.blue,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),

                // Name Field
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: whiteBackground,
                    hintText: 'Full Name',
                    hintStyle: TextStyle(fontSize: 18),
                    prefixIcon:
                        Icon(Icons.person, color: Colors.blue, size: 28),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 20),

                // Email Field
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: whiteBackground,
                    hintText: 'Email',
                    hintStyle: TextStyle(fontSize: 18),
                    prefixIcon: Icon(Icons.email, color: Colors.blue, size: 28),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 20),

                // Password Field
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: whiteBackground,
                    hintText: 'Password',
                    hintStyle: TextStyle(fontSize: 18),
                    prefixIcon: Icon(Icons.lock, color: Colors.blue, size: 28),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  obscureText: true,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 20),

                // Phone Field
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: whiteBackground,
                    hintText: 'Phone Number (e.g., +20123456789)',
                    hintStyle: TextStyle(fontSize: 18),
                    prefixIcon: Icon(Icons.phone, color: Colors.blue, size: 28),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 20),

                // Birthdate Field
                TextField(
                  controller: birthdateController,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: whiteBackground,
                    hintText: 'Birthdate (YYYY-MM-DD)',
                    hintStyle: TextStyle(fontSize: 18),
                    prefixIcon: Icon(Icons.calendar_today,
                        color: Colors.blue, size: 28),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  keyboardType: TextInputType.datetime,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 20),

                // Patient Phone Number Field (for Companion only)
                if (_selectedRole == 'Companion')
                  TextField(
                    controller: patientPhoneController,
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: whiteBackground,
                      hintText: 'Patient Phone Number (e.g., +20123456789)',
                      hintStyle: TextStyle(fontSize: 18),
                      prefixIcon: Icon(Icons.person_search,
                          color: Colors.blue, size: 28),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 18),
                  ),
                if (_selectedRole == 'Companion') const SizedBox(height: 20),

                // Doctor Phone Number Field (for Patient only)
                if (_selectedRole == 'Patient')
                  TextField(
                    controller: doctorPhoneController,
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: whiteBackground,
                      hintText: 'Doctor Phone Number (e.g., +20123456789)',
                      hintStyle: TextStyle(fontSize: 18),
                      prefixIcon: Icon(Icons.medical_services,
                          color: Colors.blue, size: 28),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 18),
                  ),
                if (_selectedRole == 'Patient') const SizedBox(height: 20),

                // Companion Phone Number Field (for Patient only)
                if (_selectedRole == 'Patient')
                  TextField(
                    controller: companionPhoneController,
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: whiteBackground,
                      hintText: 'Companion Phone Number (e.g., +20123456789)',
                      hintStyle: TextStyle(fontSize: 18),
                      prefixIcon:
                          Icon(Icons.person_add, color: Colors.blue, size: 28),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 18),
                  ),
                if (_selectedRole == 'Patient') const SizedBox(height: 20),

                // Blood Pressure Type (for Patient only)
                if (_selectedRole == 'Patient')
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: whiteBackground,
                      hintText: 'Blood Pressure Type',
                      hintStyle: TextStyle(fontSize: 18),
                      prefixIcon:
                          Icon(Icons.favorite, color: Colors.blue, size: 28),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    hint: const Text(
                      'Select Blood Pressure Type',
                      style: TextStyle(fontSize: 18),
                    ),
                    value: _bloodPressureType,
                    items: ['High', 'Average', 'Low']
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type,
                                  style: const TextStyle(fontSize: 18)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _bloodPressureType = value;
                      });
                    },
                  ),
                const SizedBox(height: 30),

                // Sign-Up Button
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Container(
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
                          onPressed: _signUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 50, vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                const SizedBox(height: 20),

                // Back to Login Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
