import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/api_service.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  EditProfilePageState createState() => EditProfilePageState();
}

class EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _birthdateController;
  late TextEditingController _companionPhoneController;
  late TextEditingController _patientPhoneController;
  late TextEditingController _doctorPhoneController;
  DateTime? _selectedDate;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  Map<String, dynamic>? userData;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    // Controllers will be initialized in didChangeDependencies
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _birthdateController = TextEditingController();
    _companionPhoneController = TextEditingController();
    _patientPhoneController = TextEditingController();
    _doctorPhoneController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get arguments here
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && args.containsKey('userData')) {
      userData = args['userData'] as Map<String, dynamic>;

      // Initialize controllers with user data
      _nameController.text = userData?['name'] ?? '';
      _emailController.text = userData?['email'] ?? '';
      _phoneController.text = userData?['phoneNumber'] ?? '';
      _userRole = userData?['role'];

      // Initialize companion/patient/doctor phone numbers if available
      if (_userRole == 'Companion') {
        _patientPhoneController.text = userData?['patientPhoneNumber'] ?? '';
      } else if (_userRole == 'Patient') {
        _companionPhoneController.text = userData?['companionPhoneNumber'] ?? '';
        _doctorPhoneController.text = userData?['doctorPhoneNumber'] ?? '';
      }

      // Format birthdate if available
      if (userData?['birthdate'] != null) {
        try {
          _selectedDate = DateTime.parse(userData!['birthdate']);
          _birthdateController.text =
              DateFormat('yyyy-MM-dd').format(_selectedDate!);
        } catch (e) {
          // Handle parsing error
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _birthdateController.dispose();
    _companionPhoneController.dispose();
    _patientPhoneController.dispose();
    _doctorPhoneController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _birthdateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // Validate phone number format
  String? _validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional field
    }
    // Basic validation for international format (should start with +)
    if (!value.startsWith('+')) {
      return 'Phone number should start with + (e.g., +20123456789)';
    }
    return null;
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token ?? '';
      if (token.isEmpty) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final updatedData = {
        'name': _nameController.text,
        'email': _emailController.text,
        'phoneNumber': _phoneController.text,
        if (_selectedDate != null)
          'birthdate': _selectedDate!.toIso8601String(),
      };

      // Add relationship phone numbers based on user role
      if (_userRole == 'Companion' && _patientPhoneController.text.isNotEmpty) {
        updatedData['patientPhoneNumber'] = _patientPhoneController.text;
      } else if (_userRole == 'Patient') {
        if (_companionPhoneController.text.isNotEmpty) {
          updatedData['companionPhoneNumber'] = _companionPhoneController.text;
        }
        if (_doctorPhoneController.text.isNotEmpty) {
          updatedData['doctorPhoneNumber'] = _doctorPhoneController.text;
        }
      }

      final userId = authProvider.userId;
      // Use the API service to update the user profile directly
      final updatedUser = await ApiService().updateUserProfile(token, updatedData);
      
      // After successful update, refresh the user profile in AuthProvider
      await authProvider.fetchUserProfile();

      setState(() {
        _successMessage = 'Profile updated successfully!';
        // Update the local userData to reflect the changes
        userData = updatedUser;
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_successMessage!),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating profile: $_errorMessage'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_successMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Text(
                    _successMessage!,
                    style: TextStyle(color: Colors.green.shade800, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Name field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Email field
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!value.contains('@') || !value.contains('.')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Phone field
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  helperText: 'International format (e.g., +20123456789)',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your phone number';
                  }
                  return _validatePhoneNumber(value);
                },
              ),
              const SizedBox(height: 16),

              // Birthdate field
              GestureDetector(
                onTap: () => _selectDate(context),
                child: AbsorbPointer(
                  child: TextFormField(
                    controller: _birthdateController,
                    decoration: const InputDecoration(
                      labelText: 'Birthdate',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select your birthdate';
                      }
                      return null;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Companion/Patient/Doctor Phone Number fields based on role
              if (_userRole == 'Companion') ...[  
                TextFormField(
                  controller: _patientPhoneController,
                  decoration: const InputDecoration(
                    labelText: 'Patient Phone Number',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_search),
                    helperText: 'Phone number of the patient you are monitoring (e.g., +20123456789)',
                  ),
                  validator: _validatePhoneNumber,
                ),
                const SizedBox(height: 16),
              ],

              if (_userRole == 'Patient') ...[  
                TextFormField(
                  controller: _companionPhoneController,
                  decoration: const InputDecoration(
                    labelText: 'Companion Phone Number',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_add),
                    helperText: 'Phone number of your companion/caregiver (e.g., +20123456789)',
                  ),
                  validator: _validatePhoneNumber,
                ),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _doctorPhoneController,
                  decoration: const InputDecoration(
                    labelText: 'Doctor Phone Number',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.medical_services),
                    helperText: 'Phone number of your doctor (e.g., +20123456789)',
                  ),
                  validator: _validatePhoneNumber,
                ),
                const SizedBox(height: 16),
              ],

              // Submit button
              ElevatedButton(
                onPressed: _isLoading ? null : _updateProfile,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Update Profile',
                        style: TextStyle(fontSize: 16)),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade800, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
