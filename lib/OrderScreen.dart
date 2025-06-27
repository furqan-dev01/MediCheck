import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../Billing.dart';
import 'settings_screen.dart';

class OrderScreen extends StatefulWidget {
  final Function(String customerName, List<Map<String, dynamic>> medicines,
      String userId, String orderId) onProceedToBilling;

  const OrderScreen({Key? key, required this.onProceedToBilling})
      : super(key: key);

  @override
  _OrderScreenState createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  List<Map<String, dynamic>> _activeDrivers = [];
  List<Map<String, dynamic>> _activeOrders = [];
  bool _isLoadingDrivers = true;
  bool _isLoadingOrders = true;
  bool _isLoadingDeliveryStatus = true;
  bool _deliveryStatus = true;
  String _userFullName = 'User';
  String _userEmail = 'user@example.com';
  Timer? _orderRefreshTimer;
  int _totalDeliveries = 0;
  int _activeDriversCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchUserInfo();
    _fetchDeliveryStatus();
    _fetchActiveDrivers();
    _fetchActiveOrdersFromFirestore();
    _startOrderRefreshTimer();
    _fetchTotalDeliveries();
    _fetchActiveDriversCount();
  }

  @override
  void dispose() {
    _orderRefreshTimer?.cancel();
    super.dispose();
  }

  void _startOrderRefreshTimer() {
    _orderRefreshTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _fetchActiveOrdersFromFirestore();
      _fetchTotalDeliveries();
      _fetchActiveDriversCount();
      _fetchDeliveryStatus();
    });
  }

  Future<void> _fetchDeliveryStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoadingDeliveryStatus = false;
        _deliveryStatus = false;
      });
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        setState(() {
          _deliveryStatus = data['deliveryStatus'] ?? false;
          _isLoadingDeliveryStatus = false;
        });
      } else {
        setState(() {
          _deliveryStatus = false;
          _isLoadingDeliveryStatus = false;
        });
      }
    } catch (e) {
      print('Error fetching delivery status: $e');
      setState(() {
        _deliveryStatus = false;
        _isLoadingDeliveryStatus = false;
      });
    }
  }

  Future<void> _fetchTotalDeliveries() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('Pharmacy Driver')
          .doc(user.uid)
          .collection('metrics')
          .doc('delivery_summary')
          .get();

      if (docSnapshot.exists && docSnapshot.data() != null) {
        setState(() {
          _totalDeliveries =
              (docSnapshot.data()!['totalDeliveries'] as int?) ?? 0;
        });
      } else {
        setState(() {
          _totalDeliveries = 0;
        });
      }
    } catch (e) {
      print('Error fetching total deliveries: $e');
      setState(() {
        _totalDeliveries = 0;
      });
    }
  }

  Future<void> _fetchActiveDriversCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Pharmacy Driver')
          .doc(user.uid)
          .collection('drivers')
          .where('status', isEqualTo: 'Active')
          .get();

      setState(() {
        _activeDriversCount = snapshot.size;
      });
    } catch (e) {
      print('Error fetching active drivers count: $e');
      setState(() {
        _activeDriversCount = 0;
      });
    }
  }

  Future<void> _fetchActiveDrivers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoadingDrivers = false;
      });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Pharmacy Driver')
          .doc(user.uid)
          .collection('drivers')
          .get();

      setState(() {
        _activeDrivers = snapshot.docs
            .map((doc) => {
                  ...doc.data(),
                  'id': doc.id,
                })
            .toList();
        _isLoadingDrivers = false;
      });

      print('Fetched ${_activeDrivers.length} drivers');
    } catch (e) {
      print('Error fetching active drivers: $e');
      setState(() {
        _isLoadingDrivers = false;
      });
    }
  }

  Future<String> _getCustomerName(String customerId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('AppUser')
          .doc(customerId)
          .get();

      if (userDoc.exists) {
        return userDoc.data()?['fullName'] ?? 'Unknown Customer';
      } else {
        return 'Unknown Customer';
      }
    } catch (e) {
      print('Error fetching customer name for $customerId: $e');
      return 'Unknown Customer';
    }
  }

  Future<String> _getPharmacyName(String pharmacyId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(pharmacyId)
          .get();
      if (userDoc.exists) {
        return userDoc.data()?['fullName'] ?? 'Unknown Pharmacy';
      } else {
        return 'Unknown Pharmacy';
      }
    } catch (e) {
      print('Error fetching pharmacy name for $pharmacyId: $e');
      return 'Unknown Pharmacy';
    }
  }

  Future<void> _fetchActiveOrdersFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoadingOrders = false;
      });
      return;
    }

    try {
      List<Map<String, dynamic>> allOrders = [];

      final medicinesSnapshot =
          await FirebaseFirestore.instance.collection('medicines order').get();

      for (var userDoc in medicinesSnapshot.docs) {
        try {
          final ordersSnapshot = await FirebaseFirestore.instance
              .collection('medicines order')
              .doc(userDoc.id)
              .collection('Orders')
              .where('pharmacyId', isEqualTo: user.uid)
              .get();

          for (var orderDoc in ordersSnapshot.docs) {
            Map<String, dynamic> orderData = {
              ...orderDoc.data(),
              'id': orderDoc.id,
              'userId': userDoc.id,
            };

            String customerName = await _getCustomerName(userDoc.id);
            orderData['customerName'] = customerName;

            // Calculate total price for the order
            double totalPrice = 0.0;
            List<dynamic> medicines = orderData['medicines'] ?? [];
            for (var med in medicines) {
              if (med is Map<String, dynamic>) {
                String medName = (med['name'] ?? '').toString().toLowerCase().trim();
                int quantity = 0;
                if (med['quantity'] is int) {
                  quantity = med['quantity'];
                } else if (med['quantity'] is String) {
                  quantity = int.tryParse(med['quantity']) ?? 0;
                } else if (med['quantity'] is double) {
                  quantity = (med['quantity'] as double).round();
                }
                double price = (med['price'] as num?)?.toDouble() ?? 0.0;
                // If price is not present, fetch from user_medicines
                if (price == 0.0 && medName.isNotEmpty) {
                  final medDoc = await FirebaseFirestore.instance
                      .collection('medicines')
                      .doc(user.uid)
                      .collection('user_medicines')
                      .doc(medName)
                      .get();
                  if (medDoc.exists) {
                    price = (medDoc.data()?['price'] as num?)?.toDouble() ?? 0.0;
                  }
                }
                totalPrice += price * quantity;
              }
            }
            orderData['totalPrice'] = totalPrice;

            allOrders.add(orderData);
          }
        } catch (e) {
          print('Error fetching orders for user ${userDoc.id}: $e');
        }
      }

      setState(() {
        _activeOrders = allOrders;
        _isLoadingOrders = false;
      });

      print('Fetched ${_activeOrders.length} orders for pharmacy ${user.uid}');
    } catch (e) {
      print('Error fetching active orders: $e');
      setState(() {
        _isLoadingOrders = false;
      });
    }
  }

  Future<void> _addDriver(String name, String phone, double rating) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final driverData = {
        'name': name,
        'phone': phone,
        'rating': rating,
        'status': 'Active',
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('Pharmacy Driver')
          .doc(user.uid)
          .collection('drivers')
          .add(driverData);

      _fetchActiveDrivers();
      _fetchActiveDriversCount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver added successfully!')),
        );
      }
    } catch (e) {
      print('Error adding driver: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding driver: $e')),
        );
      }
    }
  }

  Future<void> _deleteDriver(String driverId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('Pharmacy Driver')
          .doc(user.uid)
          .collection('drivers')
          .doc(driverId)
          .delete();

      _fetchActiveDrivers();
      _fetchActiveDriversCount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver deleted successfully!')),
        );
      }
    } catch (e) {
      print('Error deleting driver: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting driver: $e')),
        );
      }
    }
  }

  Future<void> _editDriverRating(String driverId, double newRating) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('Pharmacy Driver')
          .doc(user.uid)
          .collection('drivers')
          .doc(driverId)
          .update({
        'rating': newRating,
      });

      _fetchActiveDrivers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver rating updated successfully!')),
        );
      }
    } catch (e) {
      print('Error updating driver rating: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating driver rating: $e')),
        );
      }
    }
  }

  Future<void> _fetchUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _userEmail = user.email ?? 'user@example.com';
    });

    // Try to get display name from FirebaseAuth first
    if (user.displayName != null && user.displayName!.isNotEmpty) {
      setState(() {
        _userFullName = user.displayName!;
      });
    } else {
      // If display name is not available, try to fetch from Firestore
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(user.uid)
            .get();

        if (userDoc.exists && userDoc.data() != null && userDoc.data()!['fullName'] != null) {
          setState(() {
            _userFullName = userDoc.data()!['fullName'];
          });
        }
      } catch (e) {
        print('Error fetching user full name from Firestore: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalOrders = _activeOrders.length + _totalDeliveries;
    
    // Show loading state while fetching delivery status
    if (_isLoadingDeliveryStatus) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F3F8),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    // Show locked state when delivery is disabled
    if (!_deliveryStatus) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F3F8),
        body: Center(
          child: SingleChildScrollView(
            child: Container(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Delivery Service Disabled',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Order management is currently locked because delivery service is turned off.\n\nWhen delivery is disabled:\n• New orders cannot be processed\n• Existing orders cannot be modified\n• Driver management is restricted',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Enable delivery in Settings to unlock',
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          _fetchDeliveryStatus();
                        },
                        icon: Icon(Icons.refresh),
                        label: Text('Refresh Status'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[600],
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                      SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => SettingsScreen(
                                fullName: _userFullName,
                                email: _userEmail,
                              ),
                            ),
                          );
                          _fetchDeliveryStatus();
                        },
                        icon: Icon(Icons.settings),
                        label: Text('Go to Settings'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2A3467),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    
    // Normal order screen when delivery is enabled
    return Scaffold(
      backgroundColor: const Color(0xFFF0F3F8),
      body: Container(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Delivery Status Indicator
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Delivery Service: ENABLED',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Spacer(),
                      TextButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => SettingsScreen(
                                fullName: _userFullName,
                                email: _userEmail,
                              ),
                            ),
                          );
                          _fetchDeliveryStatus();
                        },
                        child: Text(
                          'Settings',
                          style: TextStyle(color: Colors.green[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildSummaryCard(
                          'Total Deliveries',
                          '${_totalDeliveries}',
                          Icons.local_shipping,
                          Colors.blue.shade600),
                      _buildSummaryCard(
                          'Pending Orders',
                          '${_activeOrders.length}',
                          Icons.access_time,
                          Colors.orange.shade600),
                      _buildSummaryCard(
                          'Active Drivers',
                          '${_activeDriversCount}',
                          Icons.directions_car,
                          Colors.purple.shade600),
                      _buildSummaryCard('Total Orders', '$totalOrders',
                          Icons.check_circle, Colors.green.shade600),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Column(
                      children: [
                        _buildOrdersTable(),
                        SizedBox(height: 20),
                        _buildActiveDrivers(),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
      String title, String count, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: color,
      child: Container(
        width: 180,
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 32),
            SizedBox(height: 10),
            Text(count,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            SizedBox(height: 5),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersTable() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: const Color(0xFFF5F5F5),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Active Orders',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            Divider(),
            // Table header
            Row(
              children: [
                Expanded(flex: 2, child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: Text('Order ID', style: TextStyle(fontWeight: FontWeight.bold)),
                )),
                Expanded(flex: 3, child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: Text('Customer', style: TextStyle(fontWeight: FontWeight.bold)),
                )),
                Expanded(flex: 2, child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: Text('Total Price', style: TextStyle(fontWeight: FontWeight.bold)),
                )),
                Expanded(flex: 4, child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: Text('Medicines', style: TextStyle(fontWeight: FontWeight.bold)),
                )),
                Expanded(flex: 2, child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: Align(
                    alignment: Alignment.center,
                    child: Text('Action', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                )),
              ],
            ),
            SizedBox(height: 8),
            Container(
              height: 260,
              child: _isLoadingOrders
                  ? Center(child: CircularProgressIndicator())
                  : _activeOrders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox,
                                  size: 64, color: Colors.grey[400]),
                              SizedBox(height: 10),
                              Text(
                                'No active orders found',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 16),
                              ),
                              SizedBox(height: 10),
                              ElevatedButton(
                                onPressed: _fetchActiveOrdersFromFirestore,
                                child: Text('Refresh'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: BouncingScrollPhysics(),
                          itemCount: _activeOrders.length,
                          itemBuilder: (context, index) {
                            final order = _activeOrders.reversed.toList()[index];
                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                                  child: _buildOrderRow(order),
                                ),
                                if (index < _activeOrders.length - 1)
                                  _orderRowDivider(),
                              ],
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderRow(Map<String, dynamic> order) {
    String orderId = order['id'] ?? 'N/A';
    String customerName = order['customerName'] ?? 'Unknown Customer';
    List<dynamic> medicines = order['medicines'] ?? [];
    double totalPrice = (order['totalPrice'] as double?) ?? 0.0;

    String medicinesSummary = '';
    if (medicines.isNotEmpty) {
      medicinesSummary = medicines.take(2).map((med) {
        if (med is Map<String, dynamic>) {
          return med['name'] ?? 'Unknown medicine';
        }
        return med.toString();
      }).join(', ');

      if (medicines.length > 2) {
        medicinesSummary += '... (+${medicines.length - 2} more)';
      }
    } else {
      medicinesSummary = 'No medicines';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 2, child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(orderId.length > 8 ? orderId.substring(0, 8) + '...' : orderId),
        )),
        Expanded(flex: 3, child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(customerName),
        )),
        Expanded(flex: 2, child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text('Rs ${totalPrice.toStringAsFixed(2)}'),
        )),
        Expanded(flex: 4, child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(medicinesSummary),
        )),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  _showOrderDetails(order);
                },
                child: Text('Accept'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) async {
    String pharmacyId = order['pharmacyId'] ?? 'N/A';
    String pharmacyName = await _getPharmacyName(pharmacyId);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Order Details'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Order ID: ${order['id']}'),
                SizedBox(height: 8),
                Text('Customer Name: ${order['customerName'] ?? 'Unknown Customer'}'),
                Text('Location: ${order['location'] ?? 'N/A'}'),
                Text('Phone: ${order['phone'] ?? 'N/A'}'),
                Text('Pharmacy: $pharmacyName'),
                SizedBox(height: 8),
                Text('Medicines:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...(order['medicines'] as List<dynamic>? ?? []).map((medicine) {
                  if (medicine is Map<String, dynamic>) {
                    return Text('• ${medicine['name'] ?? 'Unknown'} - Qty: ${medicine['quantity'] ?? 'N/A'}');
                  }
                  return Text('• $medicine');
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _proceedWithOrder(order);
              },
              child: const Text('Proceed'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _confirmCancelOrder(order);
              },
              child: const Text('Cancel Order', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _proceedWithOrder(Map<String, dynamic> order) {
    widget.onProceedToBilling(
      order['customerName'] ?? 'Unknown Customer',
      (order['medicines'] as List<dynamic>? ?? [])
          .map<Map<String, dynamic>>((item) {
            if (item is Map<String, dynamic>) {
              return {
                'name': (item['name'] ?? '').toString().trim().toLowerCase(),
                'price': (item['price'] as num?)?.toDouble() ?? 0.0,
                'quantity': item['quantity'] ?? 0,
              };
            }
            return {};
          })
          .where((item) => item.isNotEmpty)
          .toList(),
      order['userId'],
      order['id'],
    );
  }

  void _confirmCancelOrder(Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Cancellation'),
          content: const Text('Are you sure you want to cancel this order?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _cancelOrder(order['userId'], order['id']);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Yes, Cancel',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _cancelOrder(String userId, String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in.')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('medicines order')
          .doc(userId)
          .collection('Orders')
          .doc(orderId)
          .delete();

      _fetchActiveOrdersFromFirestore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled successfully!')),
        );
      }
    } catch (e) {
      print('Error cancelling order: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cancelling order: $e')),
        );
      }
    }
  }

  Widget _buildActiveDrivers() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: const Color(0xFFF5F5F5),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Active Drivers',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Text('Total Drivers: ${_activeDrivers.length}',
                        style: TextStyle(color: Colors.grey[600])),
                    SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () {
                        _showAddDriverDialog();
                      },
                      icon: Icon(Icons.add, color: Colors.white),
                      label: Text('Add Driver',
                          style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF2A3467),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Divider(),
            Container(
              height: 130,
              child: _isLoadingDrivers
                  ? Center(child: CircularProgressIndicator())
                  : _activeDrivers.isEmpty
                      ? Center(
                          child: Text(
                            'No active drivers found',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _activeDrivers.map((driver) {
                              return _buildDriverCard(
                                driver['name'] ?? 'Unknown',
                                driver['phone'] ?? 'No phone',
                                (driver['rating'] as num?)?.toDouble() ?? 0.0,
                                driver['status'] ?? 'Unknown',
                                driver['id'],
                              );
                            }).toList(),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverCard(String name, String phone, double rating,
      String status, String driverId) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      margin: EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white,
      child: Container(
        width: 200,
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.blue.shade700,
                    child: Icon(Icons.person, color: Colors.white)),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis),
                      Text(phone,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: () {
                    _confirmDeleteDriver(driverId);
                  },
                ),
              ],
            ),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: status == 'Active'
                    ? Colors.green.withOpacity(0.2)
                    : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(status,
                  style: TextStyle(
                      color: status == 'Active' ? Colors.green : Colors.orange,
                      fontSize: 12)),
            ),
            SizedBox(height: 5),
            GestureDetector(
              onTap: () {
                _showEditRatingDialog(driverId, rating);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.star, color: Colors.amber, size: 16),
                  Text(' ${rating.toStringAsFixed(1)}',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDriverDialog() {
    String name = '';
    String phone = '';
    double rating = 0.0;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add New Driver'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: 'Driver Name'),
                  onChanged: (value) => name = value,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                  keyboardType: TextInputType.phone,
                  onChanged: (value) => phone = value,
                ),
                TextField(
                  decoration:
                      const InputDecoration(labelText: 'Rating (0.0-5.0)'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => rating = double.tryParse(value) ?? 0.0,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (name.isNotEmpty && phone.isNotEmpty) {
                  _addDriver(name, phone, rating);
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields.')),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteDriver(String driverId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to delete this driver?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                _deleteDriver(driverId);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showEditRatingDialog(String driverId, double currentRating) {
    TextEditingController _ratingController =
        TextEditingController(text: currentRating.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Driver Rating'),
          content: TextField(
            controller: _ratingController,
            decoration:
                const InputDecoration(labelText: 'New Rating (0.0-5.0)'),
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                double newRating =
                    double.tryParse(_ratingController.text) ?? currentRating;
                if (newRating >= 0.0 && newRating <= 5.0) {
                  _editDriverRating(driverId, newRating);
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Rating must be between 0.0 and 5.0.')),
                  );
                }
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  // Helper widget for row divider
  Widget _orderRowDivider() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4),
      height: 1,
      color: Colors.grey[400],
    );
  }
}
