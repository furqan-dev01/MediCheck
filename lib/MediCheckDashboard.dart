import 'package:flutter/material.dart';
import 'package:medicheck/Billing.dart';
import 'package:medicheck/Home.dart';
import 'InventoryScreen.dart';
import 'OrderScreen.dart';
import 'SalesDashboard.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'settings_screen.dart';
import 'login_page.dart';

class MediCheckDashboard extends StatefulWidget {
  @override
  _MediCheckAppState createState() => _MediCheckAppState();
}

class _MediCheckAppState extends State<MediCheckDashboard> {
  int _selectedIndex = 0;
  String _userFullName = 'Guest'; // Default value
  String _userEmail = 'N/A'; // Default value
  String? _billingCustomerName;
  List<Map<String, dynamic>>? _billingMedicines;
  String? _billingUserId;
  String? _billingOrderId;

  // List of widget functions to call for each tab
  final List<Widget Function()> _screens = []; // Initialize as empty

  @override
  void initState() {
    super.initState();
    _fetchUserFullNameAndEmail(); // Fetch user data on init
    print('DEBUG: _fetchUserFullNameAndEmail called in initState');
    _initializeScreens(); // Call new method to initialize screens
  }

  void _initializeScreens() {
    _screens.addAll([
      () => Home(),
      () => InventoryScreen(),
      () => OrderScreen(onProceedToBilling: _navigateToBillingWithOrder),
      () => POSScreen(
            customerName: _billingCustomerName ?? '',
            medicines: _billingMedicines ?? [],
            userId: _billingUserId,
            orderId: _billingOrderId,
          ),
      () => SalesDashboard(),
    ]);
  }

  void _navigateToBillingWithOrder(String customerName,
      List<Map<String, dynamic>> medicines, String userId, String orderId) {
    setState(() {
      _billingCustomerName = customerName;
      _billingMedicines = medicines;
      _billingUserId = userId;
      _billingOrderId = orderId;
      _selectedIndex = 3; // Navigate to Billing tab
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F3F8),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Navigation Bar - Always visible
          Container(
            color: const Color(0xFFD1DCE8),
            height: 50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildNavItem('Home', index: 0),
                _buildNavItem('Inventory', index: 1),
                _buildNavItem('Order', index: 2),
                _buildNavItem('Billing', index: 3),
                _buildNavItem('Reports', index: 4),
              ],
            ),
          ),

          // Content area - Changes based on selected tab
          Expanded(
            child: _screens[_selectedIndex](),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF2A3467),
      elevation: 0,
      title: Row(
        children: [
          // MediCheck name and logo at the start
          const Icon(
            Icons.local_hospital,
            color: Colors.red,
            size: 30,
          ),
          const SizedBox(width: 8),
          const Text(
            'MediCheck',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),

          // Spacer to push the profile to the end
          const Spacer(),

          // Admin User at the end (removed notification and search bar)
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  _showProfileDialog(context);
                },
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey[300],
                      child: Text(
                        _userFullName.isNotEmpty
                            ? _userFullName[0].toUpperCase()
                            : 'A',
                        style: const TextStyle(color: Colors.black),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _userFullName,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showProfileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              Positioned(
                right: 0,
                top: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 260,
                    minWidth: 180,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // User Info
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.person, size: 24),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _userFullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Text(
                                        _userEmail,
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        // Settings
                        ListTile(
                          leading: const Icon(Icons.settings),
                          title: const Text('Settings'),
                          onTap: () async {
                            Navigator.of(context).pop();
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => SettingsScreen(
                                  fullName: _userFullName,
                                  email: _userEmail,
                                ),
                              ),
                            );
                            _fetchUserFullNameAndEmail(); // Refresh user info after returning from settings
                          },
                        ),
                        // Logout
                        ListTile(
                          leading: const Icon(Icons.logout),
                          title: const Text('Logout'),
                          onTap: () async {
                            Navigator.of(context).pop();
                            await FirebaseAuth.instance.signOut();
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                  builder: (context) => const LoginScreen()),
                              (route) => false,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavItem(String title, {required int index}) {
    final bool isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: isSelected
              ? const Border(
                  bottom: BorderSide(color: Colors.red, width: 3),
                )
              : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.red : Colors.black,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  void _fetchUserFullNameAndEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _userEmail = user.email ?? 'N/A';
      });
      print('DEBUG (MediCheckDashboard): User email: $_userEmail');

      // First, try to use FirebaseAuth's display name
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        setState(() {
          _userFullName = user.displayName!;
        });
        print(
            'DEBUG (MediCheckDashboard): User full name from FirebaseAuth: $_userFullName');
      } else {
        // If display name is not available, try to fetch from Firestore
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(user.uid)
              .get();

          if (userDoc.exists &&
              userDoc.data() != null &&
              userDoc.data()!['fullName'] != null) {
            setState(() {
              _userFullName = userDoc.data()!['fullName'];
            });
            print(
                'DEBUG (MediCheckDashboard): User full name from Firestore: $_userFullName');
          } else {
            setState(() {
              _userFullName = 'Guest';
            });
            print(
                'DEBUG (MediCheckDashboard): User full name not found in Firestore or FirebaseAuth display name empty. Defaulting to Guest.');
          }
        } catch (e) {
          print('Error fetching user full name from Firestore: $e');
          setState(() {
            _userFullName = 'Guest'; // Fallback in case of error
          });
          print(
              'DEBUG (MediCheckDashboard): User full name after error (fallback to Guest): $_userFullName');
        }
      }
    } else {
      setState(() {
        _userFullName = 'Guest'; // No user logged in
        _userEmail = 'N/A';
      });
      print(
          'DEBUG (MediCheckDashboard): No user logged in. Setting _userFullName to Guest.');
    }
  }
}
