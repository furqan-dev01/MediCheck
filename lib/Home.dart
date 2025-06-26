import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<Map<String, dynamic>> _recentActivities = [];
  String _userFullName = 'Guest'; // Default value

  @override
  void initState() {
    super.initState();
    _fetchRecentActivities();
    _fetchUserFullName(); // Call to fetch user's full name
  }

  @override
  Widget build(BuildContext context) {
    return _buildHomeContent();
  }

  Widget _buildHomeContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Section
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('Users')
                    .doc(FirebaseAuth.instance.currentUser?.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  String name = 'Guest';
                  if (snapshot.hasData && snapshot.data!.exists) {
                    name = snapshot.data!.get('fullName') ?? 'Guest';
                  }
                  return Text(
                    'Welcome back, $name',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
              Text(
                "Here's what's happening with your pharmacy today.",
                style: const TextStyle(
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Stats Cards - Wrap in SingleChildScrollView for horizontal scrolling
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FutureBuilder<int>(
                  future: _fetchPendingOrdersCount(),
                  builder: (context, snapshot) {
                    String value = '...';
                    if (snapshot.connectionState == ConnectionState.done &&
                        snapshot.hasData) {
                      value = snapshot.data.toString();
                    }
                    return _buildStatCard(
                      title: 'Pending Orders',
                      value: value,
                      color: Colors.green,
                      iconData: Icons.receipt,
                    );
                  },
                ),
                const SizedBox(width: 20),
                // Daily Revenue - using StreamBuilder for real-time updates
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('Revenue')
                      .doc(FirebaseAuth.instance.currentUser?.uid)
                      .collection('daily_metrics')
                      .doc('revenue_summary')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return _buildStatCard(
                        title: "Daily Revenue",
                        value: '...',
                        color: Colors.purple,
                        iconData: Icons.monetization_on,
                      );
                    } else if (snapshot.hasError) {
                      return _buildStatCard(
                        title: "Daily Revenue",
                        value: 'Err',
                        color: Colors.purple,
                        iconData: Icons.monetization_on,
                      );
                    } else if (!snapshot.hasData || !snapshot.data!.exists) {
                      return _buildStatCard(
                        title: "Daily Revenue",
                        value: 'Rs 0.00',
                        color: Colors.purple,
                        iconData: Icons.monetization_on,
                      );
                    } else {
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>?;
                      double currentRevenue =
                          (data?['dailyRevenue'] as num?)?.toDouble() ?? 0.0;
                      Timestamp? lastUpdatedTimestamp =
                          data?['lastUpdated'] as Timestamp?;

                      print(
                          'DEBUG (Home.dart): Received Daily Revenue snapshot. Current Revenue: $currentRevenue, Last Updated: $lastUpdatedTimestamp');

                      final now = DateTime.now();
                      DateTime lastUpdatedDate =
                          lastUpdatedTimestamp?.toDate() ?? now;

                      // Check if a new day has started or if it's the very first entry
                      if (!_isSameDay(lastUpdatedDate, now) &&
                          lastUpdatedTimestamp != null) {
                        // Log the previous day's revenue before resetting
                        final previousDay = lastUpdatedDate;
                        Future.microtask(() async {
                          await _updateDailyRevenueLogForDate(
                              previousDay, currentRevenue);
                          print(
                              'DEBUG (Home.dart): Logged previous day revenue: $currentRevenue for ${DateFormat('yyyy-MM-dd').format(previousDay)}');

                          // Reset current day's revenue in Firestore
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            await FirebaseFirestore.instance
                                .collection('Revenue')
                                .doc(user.uid)
                                .collection('daily_metrics')
                                .doc('revenue_summary')
                                .set({
                              'dailyRevenue': 0.0,
                              'lastUpdated': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                            print(
                                'DEBUG (Home.dart): Daily Revenue reset in Firestore for new day.');
                          }
                        });
                        currentRevenue = 0.0; // Reset for display immediately
                      } else if (lastUpdatedTimestamp == null) {
                        // If lastUpdated is null, it's a new entry, initialize it
                        Future.microtask(() async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            await FirebaseFirestore.instance
                                .collection('Revenue')
                                .doc(user.uid)
                                .collection('daily_metrics')
                                .doc('revenue_summary')
                                .set({
                              'dailyRevenue': currentRevenue,
                              'lastUpdated': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                            print(
                                'DEBUG (Home.dart): Initialized daily revenue with current value.');
                          }
                        });
                      }

                      // Always update the daily_revenue log for the current day with the latest cumulative revenue
                      Future.microtask(() async {
                        await _updateDailyRevenueLogForDate(
                            now, currentRevenue);
                      });

                      return _buildStatCard(
                        title: "Daily Revenue",
                        value: 'Rs ${currentRevenue.toStringAsFixed(2)}',
                        color: Colors.purple,
                        iconData: Icons.monetization_on,
                      );
                    }
                  },
                ),
                const SizedBox(width: 20),
                // Low Stock Items - fetch from Firestore
                FutureBuilder<Map<String, int>>(
                  future: _fetchStockStatusCounts(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return _buildStatCard(
                        title: 'Low Stock Items',
                        value: '...',
                        color: Colors.orange,
                        iconData: Icons.warning,
                      );
                    } else if (snapshot.hasError) {
                      return _buildStatCard(
                        title: 'Low Stock Items',
                        value: 'Err',
                        color: Colors.orange,
                        iconData: Icons.warning,
                      );
                    } else {
                      final data = snapshot.data ?? {};
                      final lowStock = data['lowStock']?.toString() ?? '0';
                      return _buildStatCard(
                        title: 'Low Stock Items',
                        value: lowStock,
                        color: Colors.orange,
                        iconData: Icons.warning,
                      );
                    }
                  },
                ),
                const SizedBox(width: 20),
                FutureBuilder<int>(
                  future: _fetchTotalMedicinesCount(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return _buildStatCard(
                        title: 'Total Medicines',
                        value: '...',
                        color: Colors.blue,
                        iconData: Icons.medication,
                      );
                    } else if (snapshot.hasError) {
                      return _buildStatCard(
                        title: 'Total Medicines',
                        value: 'Err',
                        color: Colors.blue,
                        iconData: Icons.medication,
                      );
                    } else {
                      return _buildStatCard(
                        title: 'Total Medicines',
                        value: snapshot.data?.toString() ?? '0',
                        color: Colors.blue,
                        iconData: Icons.medication,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),

          // Charts and Tables Section - Use LayoutBuilder for responsive layout
          LayoutBuilder(
            builder: (context, constraints) {
              // For smaller screens, stack widgets vertically
              if (constraints.maxWidth < 1200) {
                return Column(
                  children: [
                    _buildSalesOverviewCard(),
                    const SizedBox(height: 20),
                    _buildInventoryStatusCard(),
                    const SizedBox(height: 20),
                    _buildQuickActionsCard(),
                  ],
                );
              }
              // For larger screens, use a row layout
              else {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildSalesOverviewCard(),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 3,
                      child: _buildInventoryStatusCard(),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 2,
                      child: _buildQuickActionsCard(),
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 20),

          // Recent Orders Table - Add horizontal scroll for smaller screens
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildRecentOrdersCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required Color color,
    required IconData iconData,
    bool isNegative = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      width: 250, // Fixed width to prevent overflow
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              iconData,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 15),
          // Content - Wrap in Expanded to prevent overflow
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis, // Handle text overflow
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis, // Handle text overflow
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesOverviewCard() {
    return FutureBuilder<List<FlSpot>>(
      future: _fetchDailySalesData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingSalesOverviewCard(); // Or a loading indicator
        } else if (snapshot.hasError) {
          return _buildErrorSalesOverviewCard(); // Or an error message
        } else {
          List<FlSpot> salesData = snapshot.data ?? [];
          List<String> dates = [];
          final now = DateTime.now();
          for (int i = 6; i >= 0; i--) {
            dates.add(
                DateFormat('dd/MM').format(now.subtract(Duration(days: i))));
          }

          double maxY = salesData.isNotEmpty
              ? salesData.map((e) => e.y).reduce((a, b) => a > b ? a : b) * 1.2
              : 100;
          if (maxY < 100) maxY = 100; // Ensure a minimum maxY

          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sales Overview',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 260,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          // Line Chart with correct layout management
                          Positioned.fill(
                            child: LineChart(
                              LineChartData(
                                gridData: FlGridData(show: false),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 40,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                            'Rs ' + value.toInt().toString(),
                                            style:
                                                const TextStyle(fontSize: 12));
                                      },
                                      interval: (maxY / 5)
                                          .ceilToDouble(), // Dynamic interval
                                    ),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        return SideTitleWidget(
                                          axisSide: meta.axisSide,
                                          child: Text(dates[value.toInt()],
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                        );
                                      },
                                      reservedSize: 30,
                                      interval: 1,
                                    ),
                                  ),
                                  rightTitles: AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  topTitles: AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                ),
                                borderData: FlBorderData(
                                  show: true,
                                  border: Border.all(color: Colors.grey),
                                ),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: salesData,
                                    isCurved: true,
                                    color: Colors.blue,
                                    barWidth: 3,
                                    isStrokeCapRound: true,
                                    belowBarData: BarAreaData(show: false),
                                  ),
                                ],
                                minX: 0,
                                maxX: 6,
                                minY: 0,
                                maxY: maxY,
                              ),
                            ),
                          ),

                          // Grid Painter
                          Positioned.fill(
                            child: CustomPaint(
                              painter: GridPainter(),
                            ),
                          ),

                          // Line Chart Indicator at the Bottom
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.timeline,
                                    color: Colors.blue[400], size: 16),
                                const SizedBox(width: 4),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  // Loading card for Sales Overview
  Widget _buildLoadingSalesOverviewCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const SizedBox(
        height: 300,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  // Error card for Sales Overview
  Widget _buildErrorSalesOverviewCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const SizedBox(
        height: 300,
        child: Center(
          child: Text(
            'Error loading sales data',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  String medicineName = '';
                  String price = '';
                  String quantity = '';
                  String category = '';
                  String description = '';
                  String manufacturer = '';

                  return AlertDialog(
                    title: const Text('Add New Medicine'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'Medicine Name',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) => medicineName = value,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'Price',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) => price = value,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) => quantity = value,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) => category = value,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                            onChanged: (value) => description = value,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'Manufacturer',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) => manufacturer = value,
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
                        onPressed: () async {
                          try {
                            // Get current user email
                            final user = FirebaseAuth.instance.currentUser;
                            if (user == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Please login first')),
                              );
                              return;
                            }

                            // Validate medicine name
                            if (medicineName.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Medicine name is required')),
                              );
                              return;
                            }

                            final userMedicinesCollectionRef = FirebaseFirestore
                                .instance
                                .collection('medicines')
                                .doc(user.uid)
                                .collection('user_medicines');

                            // Ensure the parent user document exists and set a dummy attribute if it's the first medicine
                            final userDocRef = FirebaseFirestore.instance
                                .collection('medicines')
                                .doc(user.uid);
                            final userDocSnapshot = await userDocRef.get();

                            if (!userDocSnapshot.exists) {
                              await userDocRef.set({
                                'initialized': true,
                                'firstMedicineAddedAt':
                                    FieldValue.serverTimestamp(),
                                'lastActivity': FieldValue
                                    .serverTimestamp(),
                              });
                              print(
                                  'DEBUG (Home.dart): Created dummy attribute for new user medicine collection.');
                            }

                            // Search for an existing medicine with the same name, category, and manufacturer
                            final querySnapshot = await userMedicinesCollectionRef
                                .where('name', isEqualTo: medicineName.trim().toLowerCase())
                                .where('category', isEqualTo: category)
                                .where('manufacturer', isEqualTo: manufacturer)
                                .get();

                            String activityTitle;
                            String activitySubtitle;
                            if (querySnapshot.docs.isNotEmpty) {
                              // Medicine exists, update quantity and price
                              final doc = querySnapshot.docs.first;
                              final currentQuantity = (doc.data()['quantity'] ?? 0) as int;
                              final newQuantity = currentQuantity + (int.tryParse(quantity) ?? 0);
                              await doc.reference.update({
                                'quantity': newQuantity,
                                'price': double.tryParse(price) ?? 0.0,
                                'description': description,
                                'createdAt': FieldValue.serverTimestamp(),
                                'createdBy': user.email,
                              });
                              activityTitle = 'Updated Medicine';
                              activitySubtitle = 'Updated "$medicineName" in inventory';
                            } else {
                              // Medicine does not exist, add new
                              final medicineData = {
                                'name': medicineName.trim().toLowerCase(),
                                'price': double.tryParse(price) ?? 0.0,
                                'quantity': int.tryParse(quantity) ?? 0,
                                'category': category,
                                'description': description,
                                'manufacturer': manufacturer,
                                'createdAt': FieldValue.serverTimestamp(),
                                'createdBy': user.email,
                              };
                              await userMedicinesCollectionRef
                                  .doc(medicineName.trim())
                                  .set(medicineData);
                              activityTitle = 'Added New Medicine';
                              activitySubtitle = 'Added "$medicineName" to inventory';
                            }

                            // Also update the last activity timestamp on the parent document for any medicine addition
                            await userDocRef.update({
                              'lastActivity': FieldValue.serverTimestamp(),
                            });

                            // Add to recent activities
                            await FirebaseFirestore.instance
                                .collection('Revenue')
                                .doc(user.uid)
                                .collection('recent_activities')
                                .add({
                              'title': activityTitle,
                              'subtitle': activitySubtitle,
                              'time': FieldValue.serverTimestamp(),
                              'color': Colors.blue.value,
                            });

                            // Show success message
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Medicine added/updated successfully')),
                              );
                              Navigator.of(context).pop();
                              _fetchRecentActivities();
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Error adding medicine: $e')),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2A3467),
                        ),
                        child: const Text('Add Medicine',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  );
                },
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A3467),
              padding: const EdgeInsets.symmetric(vertical: 12),
              minimumSize: const Size(double.infinity, 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Add New Medicine',
                style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Activities',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  _fetchRecentActivities();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: SingleChildScrollView(
              child: Column(
                children: _recentActivities.map((activity) {
                  // Format the timestamp if available
                  String timeAgo = '';
                  if (activity['time'] != null &&
                      activity['time'] is Timestamp) {
                    final timestamp = activity['time'] as Timestamp;
                    final dateTime = timestamp.toDate();
                    final difference = DateTime.now().difference(dateTime);

                    if (difference.inDays > 0) {
                      timeAgo = '${difference.inDays} days ago';
                    } else if (difference.inHours > 0) {
                      timeAgo = '${difference.inHours} hours ago';
                    } else if (difference.inMinutes > 0) {
                      timeAgo = '${difference.inMinutes} mins ago';
                    } else {
                      timeAgo = 'Just now';
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(
                        bottom: 10), // Spacing between items
                    child: _buildActivityItem(
                      title: activity['title'] ?? 'N/A',
                      subtitle: activity['subtitle'] ?? 'N/A',
                      time: timeAgo,
                      color: Color(activity['color'] ??
                          Colors.grey.value), // Use stored color or default
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem({
    required String title,
    required String subtitle,
    required String time,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis, // Handle text overflow
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
                overflow: TextOverflow.ellipsis, // Handle text overflow
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentOrdersCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Orders',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>> (
            future: _fetchRecentOrders(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return const Text('Error loading orders');
              } else {
                final orders = snapshot.data ?? [];
                return Table(
                  border: TableBorder.all(color: Colors.grey.shade200),
                  columnWidths: const {
                    0: FixedColumnWidth(100),
                    1: FixedColumnWidth(150),
                    2: FixedColumnWidth(100),
                    3: FixedColumnWidth(100),
                  },
                  children: [
                    _buildTableRow(['Order ID', 'Customer', 'Amount', 'Status'],
                        isHeader: true),
                    ...orders
                        .map((order) => _buildTableRow([
                              order['orderId'] ?? '',
                              order['customerName'] ?? '',
                              'Rs ${order['amount'].toString()}',
                              order['status'] ?? '',
                            ]))
                        .toList(),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  TableRow _buildTableRow(List<String> values, {bool isHeader = false}) {
    return TableRow(
      children: values.map((value) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Text(
            value,
            style: TextStyle(
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis, // Handle text overflow
          ),
        );
      }).toList(),
    );
  }

  Future<int> _fetchTotalMedicinesCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;
    final snapshot = await FirebaseFirestore.instance
        .collection('medicines')
        .doc(user.uid)
        .collection('user_medicines')
        .get();
    return snapshot.docs.length;
  }

  Future<Map<String, int>> _fetchStockStatusCounts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {'inStock': 0, 'lowStock': 0, 'outOfStock': 0};
    final snapshot = await FirebaseFirestore.instance
        .collection('medicines')
        .doc(user.uid)
        .collection('user_medicines')
        .get();
    int inStock = 0;
    int lowStock = 0;
    int outOfStock = 0;
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final quantity = data['quantity'];
      if (quantity is int || quantity is double) {
        final q = quantity is int ? quantity : (quantity as double).toInt();
        if (q <= 0) {
          outOfStock++;
        } else if (q < 50) {
          lowStock++;
        } else {
          inStock++;
        }
      }
    }
    return {'inStock': inStock, 'lowStock': lowStock, 'outOfStock': outOfStock};
  }

  Future<int> _fetchInventoryStock() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;
    final snapshot = await FirebaseFirestore.instance
        .collection('medicines')
        .doc(user.email)
        .collection('user_medicines')
        .get();
    int totalStock = 0;
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final quantity = data['quantity'];
      if (quantity is int || quantity is double) {
        final q = quantity is int ? quantity : (quantity as double).toInt();
        totalStock += q;
      }
    }
    return totalStock;
  }

  Widget _buildLegendItem(String text, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildInventoryStatusCard() {
    return FutureBuilder<Map<String, int>>(
      future: _fetchStockStatusCounts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingInventoryCard();
        } else if (snapshot.hasError) {
          return _buildErrorInventoryCard();
        } else {
          final data = snapshot.data ?? {};
          final inStock = data['inStock'] ?? 0;
          final lowStock = data['lowStock'] ?? 0;
          final outOfStock = data['outOfStock'] ?? 0;
          final totalItems = inStock + lowStock + outOfStock;

          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Inventory Status',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: SizedBox(
                    height: 230,
                    width: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 0,
                            centerSpaceRadius: 50,
                            sections: [
                              PieChartSectionData(
                                value: inStock.toDouble(),
                                color: Colors.blue,
                                title: '',
                                radius: 50,
                                titleStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              PieChartSectionData(
                                value: lowStock.toDouble(),
                                color: Colors.orange,
                                title: '',
                                radius: 50,
                                titleStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              PieChartSectionData(
                                value: outOfStock.toDouble(),
                                color: Colors.red,
                                title: '',
                                radius: 50,
                                titleStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              totalItems.toString(),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const Text(
                              'Total Items',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Wrap in SingleChildScrollView for smaller screens
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLegendItem(
                          'In Stock (' + inStock.toString() + ')', Colors.blue),
                      const SizedBox(width: 16),
                      _buildLegendItem(
                          'Low Stock (' + lowStock.toString() + ')',
                          Colors.orange),
                      const SizedBox(width: 16),
                      _buildLegendItem(
                          'Out of Stock (' + outOfStock.toString() + ')',
                          Colors.red),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildLoadingInventoryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Inventory Status',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              height: 230,
              width: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 0,
                      centerSpaceRadius: 50,
                      sections: [
                        PieChartSectionData(
                          value: 0,
                          color: Colors.grey,
                          title: 'Loading...',
                          radius: 50,
                          titleStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorInventoryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Inventory Status',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              height: 230,
              width: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 0,
                      centerSpaceRadius: 50,
                      sections: [
                        PieChartSectionData(
                          value: 0,
                          color: Colors.red,
                          title: 'Error',
                          radius: 50,
                          titleStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchRecentActivities() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final recentActivitiesRef = FirebaseFirestore.instance
        .collection('Revenue')
        .doc(user.uid)
        .collection('recent_activities')
        .orderBy('time', descending: true) // Order by timestamp
        .limit(5); // Limit to recent 5 activities

    try {
      final snapshot = await recentActivitiesRef.get();
      setState(() {
        _recentActivities = snapshot.docs.map((doc) => doc.data()).toList();
      });
    } catch (e) {
      print('Error fetching recent activities: $e');
      setState(() {
        _recentActivities = [
          {
            'title': 'Error loading activities',
            'subtitle': 'Please try again',
            'time': '',
            'color': Colors.red.value
          }
        ];
      });
    }
  }

  // New method to log daily revenue for a specific date
  Future<void> _updateDailyRevenueLogForDate(
      DateTime date, double revenue) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final formattedDate = DateFormat('yyyy-MM-dd').format(date);
    final docRef = FirebaseFirestore.instance
        .collection('Revenue')
        .doc(user.uid)
        .collection('daily_revenue')
        .doc(formattedDate);

    try {
      // Only update if revenue is different or if it's the first log for the day
      final existingDoc = await docRef.get();
      double existingRevenue =
          (existingDoc.data()?['revenue'] as num?)?.toDouble() ??
              -1.0; // Use -1.0 to ensure a write if doc doesn't exist

      if (!existingDoc.exists || existingRevenue != revenue) {
        await docRef.set(
            {
              'revenue': revenue,
              'timestamp': FieldValue.serverTimestamp(),
            },
            SetOptions(
                merge:
                    true)); // Use merge to update without overwriting other fields
        print(
            'DEBUG (Home.dart): Updated daily revenue log for $formattedDate: $revenue');
      }
    } catch (e) {
      print('Error updating daily revenue log: $e');
    }
  }

  // Helper to check if two DateTimes are on the same day
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // New method to fetch daily sales data for the last 7 days
  Future<List<FlSpot>> _fetchDailySalesData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    List<FlSpot> salesData = [];
    final now = DateTime.now();

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final formattedDate = DateFormat('yyyy-MM-dd').format(date);
      final docRef = FirebaseFirestore.instance
          .collection('Revenue')
          .doc(user.uid)
          .collection(
              'daily_revenue') // Assuming a new collection for daily revenue
          .doc(formattedDate);

      final doc = await docRef.get();
      double revenue = 0.0;
      if (doc.exists) {
        revenue = (doc.data()?['revenue'] as num?)?.toDouble() ?? 0.0;
      }
      salesData.add(FlSpot((6 - i).toDouble(), revenue));
    }
    return salesData;
  }

  // New method to fetch the user's full name
  Future<void> _fetchUserFullName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        setState(() {
          _userFullName = userDoc.data()?['fullName'] ?? user.email ?? 'User';
        });
      } else {
        setState(() {
          _userFullName = user.email ??
              'User'; // Fallback to email if document doesn't exist
        });
      }
    } catch (e) {
      print('Error fetching user full name: $e');
      setState(() {
        _userFullName = user?.email ?? 'Error'; // Fallback on error
      });
    }
  }

  Future<int> _fetchPendingOrdersCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    int pendingCount = 0;
    final medicinesSnapshot =
        await FirebaseFirestore.instance.collection('medicines order').get();

    for (var userDoc in medicinesSnapshot.docs) {
      final ordersSnapshot = await FirebaseFirestore.instance
          .collection('medicines order')
          .doc(userDoc.id)
          .collection('Orders')
          .where('pharmacyId', isEqualTo: user.uid)
          // Uncomment the next line if you want to filter by status
          // .where('status', isEqualTo: 'pending')
          .get();

      pendingCount += ordersSnapshot.docs.length;
    }
    return pendingCount;
  }

  Future<List<Map<String, dynamic>>> _fetchRecentOrders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    List<Map<String, dynamic>> allOrders = [];
    Map<String, double> activeOrderPrices = {};

    // Fetch active orders and their total prices (same logic as OrderScreen.dart)
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
            'orderId': orderDoc.id,
            'userId': userDoc.id,
          };

          String customerName = await _getCustomerName(userDoc.id);
          orderData['customerName'] = customerName;

          // Calculate total price for the order (same as OrderScreen.dart)
          double totalPrice = 0.0;
          List<dynamic> medicines = orderData['medicines'] ?? [];
          for (var med in medicines) {
            if (med is Map<String, dynamic>) {
              String medName =
                  (med['name'] ?? '').toString().toLowerCase().trim();
              int quantity = 0;
              if (med['quantity'] is int) {
                quantity = med['quantity'];
              } else if (med['quantity'] is String) {
                quantity = int.tryParse(med['quantity']) ?? 0;
              } else if (med['quantity'] is double) {
                quantity = (med['quantity'] as double).round();
              }
              double price = (med['price'] as num?)?.toDouble() ?? 0.0;
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
          orderData['amount'] = totalPrice;
          activeOrderPrices[orderDoc.id] = totalPrice;

          allOrders.add(orderData);
        }
      } catch (e) {
        print('Error fetching orders for user  ̄${userDoc.id}: $e');
      }
    }

    // Sort by createdAt descending and take top 5
    allOrders.sort((a, b) {
      final aTime = a['createdAt'] is Timestamp
          ? (a['createdAt'] as Timestamp).toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b['createdAt'] is Timestamp
          ? (b['createdAt'] as Timestamp).toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    final top5 = allOrders
        .take(5)
        .map((order) => {
              'orderId': order['orderId'] ?? '',
              'customerName': order['customerName'] ?? 'Unknown',
              // Use the totalPrice from activeOrderPrices if orderId matches
              'amount': activeOrderPrices[order['orderId']] ?? order['amount'] ?? 0,
              'status': order['status'] ?? 'Pending',
            })
        .toList();

    return top5;
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
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;

    // Draw horizontal grid lines
    for (double i = 0; i <= size.height; i += size.height / 5) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }

    // Draw vertical grid lines
    for (double i = 0; i <= size.width; i += size.width / 5) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
