import 'package:flutter/material.dart';

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade900,
        title: Row(
          children: [
            Icon(Icons.local_hospital, color: Colors.white),
            SizedBox(width: 10),
            Text("MediCheck", style: TextStyle(color: Colors.white)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(50.0),
          child: Container(
            color: Colors.blueGrey.shade100,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.red,
              unselectedLabelColor: Colors.black,
              indicatorColor: Colors.red,
              tabs: [
                Tab(text: "Home"),
                Tab(text: "Inventory"),
                Tab(text: "Order"),
                Tab(text: "Billing"),
                Tab(text: "Reports"),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          //HomeScreen(),
          //InventoryScreen(),
          //OrderScreen(),
          //BillingScreen(),
          //ReportScreen(),
        ],
      ),
    );
  }
}
