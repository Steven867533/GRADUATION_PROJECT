import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/api_service.dart';

class UserSelectionPage extends StatefulWidget {
  final String? userType; // 'doctor', 'companion', or 'patient'
  final Function(Map<String, dynamic>)? onUserSelected;

  const UserSelectionPage({
    super.key, 
    this.userType,
    this.onUserSelected,
  });

  @override
  UserSelectionPageState createState() => UserSelectionPageState();
}

class UserSelectionPageState extends State<UserSelectionPage> {
  final TextEditingController _phoneController = TextEditingController();
  List<Map<String, dynamic>> users = [];
  bool _isLoading = false;
  String _errorMessage = '';

  Future<void> _searchUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      users = [];
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token ?? '';
      if (token.isEmpty) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final results =
          await ApiService().searchUsers(token, _phoneController.text.trim());
      
      // Filter results based on userType if specified
      if (widget.userType != null) {
        setState(() {
          users = results.where((user) => 
            user['role'] == widget.userType?.capitalize()).toList();
        });
      } else {
        setState(() {
          users = results;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String _getTitle() {
    if (widget.userType == 'doctor') {
      return 'Select Doctor';
    } else if (widget.userType == 'companion') {
      return 'Select Companion';
    } else if (widget.userType == 'patient') {
      return 'Select Patient';
    } else {
      return 'Select User to Chat';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(
          _getTitle(),
          style: const TextStyle(color: Colors.white, fontSize: 24),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: 'Enter Phone Number',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searchUsers,
                ),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_errorMessage.isNotEmpty)
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.red, fontSize: 16),
              )
            else if (users.isEmpty)
              const Text('No users found.')
            else
              Expanded(
                child: ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return ListTile(
                      leading: const Icon(Icons.person, color: Colors.blue),
                      title: Text(user['name'] ?? 'Unknown'),
                      subtitle: Text(user['phoneNumber'] ?? 'N/A'),
                      onTap: () {
                        if (widget.onUserSelected != null) {
                          widget.onUserSelected!(user);
                          Navigator.pop(context);
                        } else {
                          Navigator.pushNamed(
                            context,
                            '/messages',
                            arguments: {
                              'userId': Provider.of<AuthProvider>(context,
                                      listen: false)
                                  .userId,
                              'recipientId': user['_id'],
                              'recipientName': user['name'] ?? 'Unknown',
                            },
                          );
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Extension to capitalize first letter
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }
}
