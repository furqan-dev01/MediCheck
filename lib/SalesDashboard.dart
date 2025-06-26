import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class Sales extends StatelessWidget {
  final double totalRevenue;
  final int totalOrders;

  const Sales({
    Key? key,
    required this.totalRevenue,
    required this.totalOrders,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          primarySwatch: Colors.blue,
          primaryColor: Colors.blue), // Explicitly set primaryColor
      home: SalesDashboard(
        totalRevenue: totalRevenue,
        totalOrders: totalOrders,
      ),
    );
  }
}

class SalesDashboard extends StatelessWidget {
  final double totalRevenue;
  final int totalOrders;

  const SalesDashboard({
    Key? key,
    this.totalRevenue = 0.0,
    this.totalOrders = 0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F3F8),
      body: Container(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Cards
              FutureBuilder<double>(
                future: fetchTotalRevenue(),
                builder: (context, revenueSnapshot) {
                  double totalRevenue = revenueSnapshot.data ?? 0.0;
                  return FutureBuilder<int>(
                    future: fetchTotalOrders(),
                    builder: (context, ordersSnapshot) {
                      int totalOrders = ordersSnapshot.data ?? 0;
                      return SummaryCards(
                        totalRevenue: totalRevenue,
                        totalOrders: totalOrders,
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 20),

              // Charts Row
              ChartsSection(),
              const SizedBox(height: 20),

              // Sales Performance Table
              SalesPerformanceTable(),
            ],
          ),
        ),
      ),
    );
  }
}

class SummaryCards extends StatelessWidget {
  final double totalRevenue;
  final int totalOrders;

  const SummaryCards({
    Key? key,
    required this.totalRevenue,
    required this.totalOrders,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SummaryCard(
            title: 'Total Revenue',
            value: 'Rs ${totalRevenue.toStringAsFixed(2)}',
          ),
        ),
        Expanded(
          child: SummaryCard(
            title: 'Total Orders',
            value: totalOrders.toString(),
          ),
        ),
        Expanded(
          child: FutureBuilder<double>(
            future: fetchAverageOrderValue(),
            builder: (context, snapshot) {
              double avg = snapshot.data ?? 0.0;
              return SummaryCard(
                title: 'Average Order Value',
                value: 'Rs ${avg.toStringAsFixed(2)}',
              );
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: fetchSalesPerformance(),
            builder: (context, snapshot) {
              int count = 0;
              if (snapshot.hasData) {
                count = snapshot.data!.length;
              }
              return SummaryCard(
                title: 'Top Selling Products',
                value: count.toString(),
              );
            },
          ),
        ),
      ],
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String title;
  final String value;

  const SummaryCard({
    Key? key,
    required this.title,
    required this.value,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: Colors.grey[200],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChartsSection extends StatelessWidget {
  const ChartsSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Revenue Trends Chart
        Expanded(
          child: ChartCard(
            title: 'Revenue Trends',
            chart: FutureBuilder<List<double>>(
              future: fetchLast7DaysRevenue(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                return RevenueBarChart(revenues: snapshot.data!);
              },
            ),
          ),
        ),

        // Stock Movement Chart
        Expanded(
          child: ChartCard(
            title: 'Stock Movement',
            chart: FutureBuilder<List<Map<String, dynamic>>>(
              future: fetchInventoryQuantities(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                return StockMovementChart(inventory: snapshot.data!);
              },
            ),
          ),
        ),

        // Top Selling Products Chart
        Expanded(
          child: ChartCard(
            title: 'Top Selling Products',
            chart: FutureBuilder<List<Map<String, dynamic>>>(
              future: fetchTop5SellingMedicines(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                return TopSellingMedicinesChart(topMedicines: snapshot.data!);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class ChartCard extends StatelessWidget {
  final String title;
  final Widget chart;

  const ChartCard({
    Key? key,
    required this.title,
    required this.chart,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: Colors.grey[200],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: chart,
            ),
          ],
        ),
      ),
    );
  }
}

class RevenueBarChart extends StatelessWidget {
  final List<double> revenues;

  const RevenueBarChart({Key? key, required this.revenues}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double maxY = revenues.isNotEmpty
        ? revenues.reduce((a, b) => a > b ? a : b) * 1.2
        : 100;
    if (maxY < 100) maxY = 100;

    // All bars blue
    final barColor = Colors.blue;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceEvenly,
        gridData: FlGridData(show: false),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Colors.black, width: 1),
            bottom: BorderSide(color: Colors.black, width: 1),
            right: BorderSide(color: Colors.transparent),
            top: BorderSide(color: Colors.transparent),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) => Text(
                'Rs${value.toInt()}',
                style: const TextStyle(fontSize: 12),
              ),
              interval: (maxY / 4).ceilToDouble(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final now = DateTime.now();
                final date = now.subtract(Duration(days: 6 - value.toInt()));
                return Text(DateFormat('E').format(date),
                    style: const TextStyle(fontSize: 12));
              },
              reservedSize: 28,
              interval: 1,
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: List.generate(revenues.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: revenues[i],
                color: barColor,
                width: 28,
                borderRadius: BorderRadius.zero,
                borderSide: const BorderSide(color: Colors.black, width: 3),
                rodStackItems: [],
              ),
            ],
          );
        }),
        minY: 0,
        maxY: maxY,
      ),
    );
  }
}

class BarChartSample1 extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceEvenly,
        barTouchData: BarTouchData(
          enabled: false,
        ),
        titlesData: FlTitlesData(show: true),
        borderData: FlBorderData(show: false),
        barGroups: [
          BarChartGroupData(
            x: 0,
            barRods: [
              BarChartRodData(toY: 8, color: Colors.blue),
              BarChartRodData(toY: 6.5, color: Colors.green),
            ],
          ),
          BarChartGroupData(
            x: 1,
            barRods: [
              BarChartRodData(toY: 7, color: Colors.blue),
              BarChartRodData(toY: 5, color: Colors.green),
            ],
          ),
          BarChartGroupData(
            x: 2,
            barRods: [
              BarChartRodData(toY: 6, color: Colors.blue),
              BarChartRodData(toY: 15, color: Colors.green),
            ],
          ),
          BarChartGroupData(
            x: 3,
            barRods: [
              BarChartRodData(toY: 7, color: Colors.blue),
              BarChartRodData(toY: 8, color: Colors.green),
            ],
          ),
          BarChartGroupData(
            x: 4,
            barRods: [
              BarChartRodData(toY: 6, color: Colors.blue),
              BarChartRodData(toY: 9, color: Colors.green),
            ],
          ),
        ],
      ),
    );
  }
}

class TopSellingMedicinesChart extends StatelessWidget {
  final List<Map<String, dynamic>> topMedicines;

  const TopSellingMedicinesChart({Key? key, required this.topMedicines})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (topMedicines.isEmpty) {
      return Center(child: Text('No data'));
    }

    double maxY = topMedicines
            .map((e) => (e['revenue'] as double? ?? 0.0))
            .reduce((a, b) => a > b ? a : b) *
        1.2;
    if (maxY < 10) maxY = 10;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceEvenly,
        gridData: FlGridData(show: false),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Colors.black, width: 1),
            bottom: BorderSide(color: Colors.black, width: 1),
            right: BorderSide(color: Colors.transparent),
            top: BorderSide(color: Colors.transparent),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) => Text(
                'Rs${value.toInt()}',
                style: const TextStyle(fontSize: 12),
              ),
              interval: (maxY / 4).ceilToDouble(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                int idx = value.toInt();
                if (idx < 0 || idx >= topMedicines.length) return Text('');
                final name = topMedicines[idx]['productName'] ?? '';
                final qty = topMedicines[idx]['unitsSold'] ?? '';
                return Text(
                  '$name ($qty)',
                  style: const TextStyle(fontSize: 10),
                  textAlign: TextAlign.center,
                );
              },
              reservedSize: 40,
              interval: 1,
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: List.generate(topMedicines.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: (topMedicines[i]['revenue'] as double? ?? 0.0),
                color: Colors.blue,
                width: 18,
                borderRadius: BorderRadius.circular(8),
                rodStackItems: [],
              ),
            ],
            barsSpace: 4,
          );
        }),
        minY: 0,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: false,
        ),
      ),
    );
  }
}

class SalesPerformanceTable extends StatelessWidget {
  const SalesPerformanceTable({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: Colors.grey[200],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sales Performance',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: fetchSalesPerformance(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                final sales = snapshot.data!;
                return Table(
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(2),
                  },
                  border: TableBorder.symmetric(
                    inside: BorderSide(color: Colors.grey.shade300),
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                      ),
                      children: [
                        tableHeader('PRODUCT NAME'),
                        tableHeader('UNITS SOLD'),
                        tableHeader('REVENUE'),
                      ],
                    ),
                    ...sales.map((sale) => TableRow(
                          children: [
                            tableCell(sale['productName'] ?? ''),
                            tableCell(sale['unitsSold'].toString()),
                            tableCell('Rs${(sale['revenue'] ?? 0).toStringAsFixed(2)}'),
                          ],
                        )),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget tableHeader(String text) => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget tableCell(String text) => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(text),
      );
}

Future<double> fetchTotalRevenue() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 0.0;

  final snapshot = await FirebaseFirestore.instance
      .collection('Revenue')
      .doc(user.uid)
      .collection('daily_revenue')
      .get();

  double total = 0.0;
  for (var doc in snapshot.docs) {
    total += (doc.data()['revenue'] as num?)?.toDouble() ?? 0.0;
  }
  return total;
}

Future<int> fetchTotalOrders() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 0;

  int totalOrders = 0;
  final medicinesSnapshot =
      await FirebaseFirestore.instance.collection('medicines order').get();

  for (var userDoc in medicinesSnapshot.docs) {
    final ordersSnapshot = await FirebaseFirestore.instance
        .collection('medicines order')
        .doc(userDoc.id)
        .collection('Orders')
        .where('pharmacyId', isEqualTo: user.uid)
        .get();

    totalOrders += ordersSnapshot.docs.length;
  }
  return totalOrders;
}

Stream<List<FlSpot>> revenueTrendStream() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('Revenue')
      .doc(user.uid)
      .collection('daily_revenue')
      .orderBy('date')
      .snapshots()
      .map((snapshot) {
    List<FlSpot> spots = [];
    int index = 0;
    for (var doc in snapshot.docs) {
      double revenue = (doc.data()['revenue'] as num?)?.toDouble() ?? 0.0;
      spots.add(FlSpot(index.toDouble(), revenue));
      index++;
    }
    return spots;
  });
}

Future<List<Map<String, dynamic>>> fetchSalesPerformance() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return [];

  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('Revenue')
        .doc(user.uid)
        .collection('sales')
        .get();

    // Aggregation map: productName -> {productName, unitsSold, revenue}
    final Map<String, Map<String, dynamic>> aggregated = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final items = data['items'];
      if (items is List) {
        for (var item in items) {
          if (item is Map) {
            String productName = item['name']?.toString() ?? 'Unknown Product';
            int unitsSold = 0;
            double price = 0.0;
            double itemRevenue = 0.0;

            // Handle different possible data types for quantity
            if (item['quantity'] != null) {
              if (item['quantity'] is int) {
                unitsSold = item['quantity'];
              } else if (item['quantity'] is String) {
                unitsSold = int.tryParse(item['quantity']) ?? 0;
              } else if (item['quantity'] is double) {
                unitsSold = (item['quantity'] as double).round();
              }
            }

            // Handle different possible data types for price
            if (item['price'] != null) {
              if (item['price'] is num) {
                price = (item['price'] as num).toDouble();
              } else if (item['price'] is String) {
                price = double.tryParse(item['price']) ?? 0.0;
              }
            }

            itemRevenue = price * unitsSold;

            if (aggregated.containsKey(productName)) {
              aggregated[productName]!['unitsSold'] += unitsSold;
              aggregated[productName]!['revenue'] += itemRevenue;
            } else {
              aggregated[productName] = {
                'productName': productName,
                'unitsSold': unitsSold,
                'revenue': itemRevenue,
              };
            }
          }
        }
      }
    }

    return aggregated.values.toList();
  } catch (e) {
    print('Error fetching sales performance: $e');
    return [];
  }
}

Future<List<double>> fetchLast7DaysRevenue() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return List.filled(7, 0.0);

  List<double> revenues = [];
  final now = DateTime.now();

  for (int i = 6; i >= 0; i--) {
    final date = now.subtract(Duration(days: i));
    final formattedDate = DateFormat('yyyy-MM-dd').format(date);
    final docRef = FirebaseFirestore.instance
        .collection('Revenue')
        .doc(user.uid)
        .collection('daily_revenue')
        .doc(formattedDate);

    final doc = await docRef.get();
    double revenue = 0.0;
    if (doc.exists) {
      revenue = (doc.data()?['revenue'] as num?)?.toDouble() ?? 0.0;
    }
    revenues.add(revenue);
  }
  return revenues;
}

Future<List<Map<String, dynamic>>> fetchTop5SellingMedicines() async {
  final sales = await fetchSalesPerformance();
  sales.sort(
      (a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));
  return sales.take(5).toList();
}

Future<List<Map<String, dynamic>>> fetchInventoryQuantities() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return [];

  final snapshot = await FirebaseFirestore.instance
      .collection('medicines')
      .doc(user.uid)
      .collection('user_medicines')
      .get();

  return snapshot.docs.map((doc) {
    final data = doc.data();
    return {
      'productName': data['name'] ?? 'Unknown',
      'quantity': (data['quantity'] as num?)?.toInt() ?? 0,
    };
  }).toList();
}

class StockMovementChart extends StatefulWidget {
  final List<Map<String, dynamic>> inventory;

  const StockMovementChart({Key? key, required this.inventory})
      : super(key: key);

  @override
  _StockMovementChartState createState() => _StockMovementChartState();
}

class _StockMovementChartState extends State<StockMovementChart> {
  int? touchedIndex;

  @override
  Widget build(BuildContext context) {
    final inventory = widget.inventory;
    if (inventory.isEmpty) {
      return Center(child: Text('No inventory data'));
    }

    double maxY = inventory
            .map((e) => (e['quantity'] as int))
            .reduce((a, b) => a > b ? a : b) *
        1.2;
    if (maxY < 10) maxY = 10;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceEvenly,
        gridData: FlGridData(show: false),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Colors.black, width: 1),
            bottom: BorderSide(color: Colors.black, width: 1),
            right: BorderSide(color: Colors.transparent),
            top: BorderSide(color: Colors.transparent),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: const TextStyle(fontSize: 12),
              ),
              interval: (maxY / 4).ceilToDouble(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                int idx = value.toInt();
                if (idx < 0 || idx >= inventory.length) return Text('');
                final name = inventory[idx]['productName'] ?? '';
                return Text(
                  name,
                  style: const TextStyle(fontSize: 10),
                  textAlign: TextAlign.center,
                );
              },
              reservedSize: 40,
              interval: 1,
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: List.generate(inventory.length, (i) {
          final qty = inventory[i]['quantity'] as int;
          final isLow = qty < 10; // You can set your own threshold
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: qty.toDouble(),
                color: isLow ? Colors.red : Colors.green,
                width: 18,
                borderRadius: BorderRadius.circular(8),
                rodStackItems: [],
              ),
            ],
            barsSpace: 4,
          );
        }),
        minY: 0,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.blueAccent,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final name = inventory[group.x.toInt()]['productName'] ?? '';
              final qty = inventory[group.x.toInt()]['quantity'] ?? 0;
              return BarTooltipItem(
                '$name\nQuantity: $qty',
                const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              );
            },
          ),
          touchCallback: (event, response) {
            if (event.isInterestedForInteractions &&
                response != null &&
                response.spot != null) {
              setState(() {
                touchedIndex = response.spot!.touchedBarGroupIndex;
              });
            } else {
              setState(() {
                touchedIndex = null;
              });
            }
          },
        ),
      ),
    );
  }
}

Future<double> fetchAverageOrderValue() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 0.0;

  double totalValue = 0.0;
  int orderCount = 0;

  // Fetch all orders for this pharmacy
  final medicinesSnapshot =
      await FirebaseFirestore.instance.collection('medicines order').get();
  for (var userDoc in medicinesSnapshot.docs) {
    final ordersSnapshot = await FirebaseFirestore.instance
        .collection('medicines order')
        .doc(userDoc.id)
        .collection('Orders')
        .where('pharmacyId', isEqualTo: user.uid)
        .get();
    for (var orderDoc in ordersSnapshot.docs) {
      final orderData = orderDoc.data();
      final medicines = orderData['medicines'] as List<dynamic>? ?? [];
      double orderTotal = 0.0;
      for (var med in medicines) {
        if (med is Map<String, dynamic>) {
          final price = (med['price'] as num?)?.toDouble() ?? 0.0;
          int quantity = 0;
          if (med['quantity'] is int) {
            quantity = med['quantity'];
          } else if (med['quantity'] is String) {
            quantity = int.tryParse(med['quantity']) ?? 0;
          } else if (med['quantity'] is double) {
            quantity = (med['quantity'] as double).round();
          }
          orderTotal += price * quantity;
        }
      }
      totalValue += orderTotal;
      orderCount++;
    }
  }
  if (orderCount == 0) return 0.0;
  return totalValue / orderCount;
}
