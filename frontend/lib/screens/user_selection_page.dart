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

class UserSelectionPageState extends State<UserSelectionPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> unseenMessageSenders = [];
  bool _isLoading = false;
  bool _isLoadingUnseen = false;
  String _errorMessage = '';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Initialize tab controller with 2 tabs
    _tabController = TabController(length: 2, vsync: this);

    // Load unseen message senders when the page loads
    _loadUnseenMessageSenders();
  }

  Future<void> _loadUnseenMessageSenders() async {
    setState(() {
      _isLoadingUnseen = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token ?? '';
      if (token.isEmpty) {
        print('No authentication token available, redirecting to login');
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      print(
          'Fetching unseen message senders, user role: ${authProvider.userRole}');
      final senders = await ApiService().getUnseenMessageSenders(token);

      // Debug output - verify we're getting senders correctly
      print('Loaded ${senders.length} unseen message senders');

      if (senders.isEmpty) {
        print(
            'No unseen messages found - this could be expected or could indicate an issue with the backend query');
      }

      setState(() {
        unseenMessageSenders = senders;
        _isLoadingUnseen = false;
      });
    } catch (e) {
      print('Error loading unseen message senders: $e');
      setState(() {
        unseenMessageSenders = []; // Ensure this is empty on error
        _isLoadingUnseen = false;
      });
    }
  }

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
          users = results
              .where((user) => user['role'] == widget.userType?.capitalize())
              .toList();
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
    _tabController.dispose();
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
      return 'Messages';
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.chat),
                  const SizedBox(width: 8),
                  const Text('Messages'),
                  if (unseenMessageSenders.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${unseenMessageSenders.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search),
                  SizedBox(width: 8),
                  Text('Search'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Messages Tab
          _buildMessagesTab(),

          // Search Tab
          _buildSearchTab(),
        ],
      ),
    );
  }

  Widget _buildMessagesTab() {
    return RefreshIndicator(
      onRefresh: _loadUnseenMessageSenders,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Loading indicator
            if (_isLoadingUnseen)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (unseenMessageSenders.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No new messages',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Use the search tab to find contacts',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      TextButton.icon(
                        onPressed: () {
                          _tabController.animateTo(1); // Switch to search tab
                        },
                        icon: const Icon(Icons.search),
                        label: const Text('Find Contacts'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: unseenMessageSenders.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final sender = unseenMessageSenders[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: Text(
                              (sender['name'] ?? 'U')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: TextStyle(
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Text(
                                '${sender['unseenCount']}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              sender['name'] ?? 'Unknown',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            _formatMessageTime(sender['latestMessageTime']),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sender['phoneNumber'] ?? 'N/A',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sender['latestMessage'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      onTap: () async {
                        // Before navigating to chat, mark all messages from this sender as seen
                        final authProvider =
                            Provider.of<AuthProvider>(context, listen: false);
                        final token = authProvider.token ?? '';
                        if (token.isNotEmpty) {
                          try {
                            // Mark all messages from this sender as seen
                            await ApiService()
                                .markAllMessagesAsSeen(token, sender['_id']);

                            // Navigate to chat page
                            if (mounted) {
                              Navigator.pushNamed(
                                context,
                                '/messages',
                                arguments: {
                                  'userId': authProvider.userId,
                                  'recipientId': sender['_id'],
                                  'recipientName': sender['name'] ?? 'Unknown',
                                },
                              ).then((_) {
                                // Refresh unseen messages when returning from chat
                                _loadUnseenMessageSenders();
                              });
                            }
                          } catch (e) {
                            print('Error marking messages as seen: $e');
                            // Continue to chat page even if marking messages failed
                            if (mounted) {
                              Navigator.pushNamed(
                                context,
                                '/messages',
                                arguments: {
                                  'userId': authProvider.userId,
                                  'recipientId': sender['_id'],
                                  'recipientName': sender['name'] ?? 'Unknown',
                                },
                              ).then((_) {
                                // Refresh unseen messages when returning from chat
                                _loadUnseenMessageSenders();
                              });
                            }
                          }
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

  Widget _buildSearchTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: 'Enter Phone Number',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              prefixIcon: const Icon(Icons.phone),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _searchUsers,
              ),
            ),
            keyboardType: TextInputType.phone,
            onSubmitted: (_) => _searchUsers(),
          ),
          const SizedBox(height: 16),

          // Search status or results
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _errorMessage,
                style: const TextStyle(color: Colors.red, fontSize: 16),
              ),
            )
          else if (users.isEmpty)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Search by phone number',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: users.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final user = users[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade100,
                      child: Text(
                        (user['name'] ?? 'U').substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: Colors.blue.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(user['name'] ?? 'Unknown'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user['phoneNumber'] ?? 'N/A'),
                        if (user['role'] != null)
                          Text(
                            user['role'],
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
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
                        ).then((_) {
                          // Refresh unseen messages when returning from chat
                          _loadUnseenMessageSenders();
                        });
                      }
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _formatMessageTime(String? timestamp) {
    if (timestamp == null) return '';

    try {
      final messageTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(messageTime);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }
}

// Extension to capitalize first letter
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }
}
