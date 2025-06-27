import 'dart:async'; // Import for Timer
import 'dart:io'; // For File operations
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart'; // For accessing directories
import 'package:csv/csv.dart'; // For CSV conversion
import 'package:permission_handler/permission_handler.dart'; // For permission requests
import 'package:flutter/foundation.dart' show kIsWeb; // For kIsWeb
import 'dart:html' as html; // For HTML elements
import 'package:file_picker/file_picker.dart'; // For file selection
import 'dart:convert'; // For UTF8 encoding
import 'package:flutter/rendering.dart'; // For XTypeGroup
import 'package:flutter/services.dart'; // For XFile
import 'package:printing/printing.dart'; // For printing
import 'package:pdf/widgets.dart' as pw; // For PDF generation
import 'package:pdf/pdf.dart'; // For PdfPageFormat and PdfColors

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({Key? key}) : super(key: key);

  @override
  State<InventoryScreen> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryScreen> {
  List<InventoryItem> _inventoryItems = [];
  int _totalItems = 0;
  int _lowStockItems = 0;
  int _outOfStockItems = 0;
  List<RestockItem> _restockNeededItems = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  int _currentPage = 0;
  final int _itemsPerPage = 4; // Display 4 items per page

  String? _currentInventorySelectedCategory;
  RangeValues? _currentInventoryPriceRange;

  String? _restockNeededSelectedCategory; // New filter state for Restock Needed
  RangeValues? _restockNeededPriceRange; // New filter state for Restock Needed

  int _restockCurrentPage = 0;
  final int _restockItemsPerPage = 4; // Display 4 items per page for restock

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Function to delete medicine
  Future<void> _deleteMedicine(String docId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please login first to delete medicine')),
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('medicines')
          .doc(user.uid)
          .collection('user_medicines')
          .doc(docId)
          .delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medicine deleted successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting medicine: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F3F8),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('medicines')
            .doc(FirebaseAuth.instance.currentUser?.uid)
            .collection('user_medicines')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            _inventoryItems =
                []; // Ensure _inventoryItems is empty when no data
          } else {
            _inventoryItems = snapshot.data!.docs
                .map((doc) => InventoryItem.fromFirestore(doc))
                .toList();
          }

          // Calculate summary counts
          _totalItems = _inventoryItems.length;
          _lowStockItems = _inventoryItems
              .where((item) => item.status == 'Low Stock')
              .length;
          _outOfStockItems = _inventoryItems
              .where((item) => item.status == 'Out of Stock')
              .length;

          // Populate restock needed items
          _restockNeededItems = _inventoryItems
              .where((item) =>
                  item.status == 'Low Stock' || item.status == 'Out of Stock')
              .map((item) => RestockItem(
                    id: item.id,
                    name: item.name,
                    category: item.category,
                    quantity: item.quantity,
                    minQuantity:
                        50, // Assuming a default min quantity for restock check
                    status: item.status,
                    icon: item.icon,
                    iconColor: item.iconColor,
                  ))
              .toList();

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInventorySummary(),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 1,
                        child: _buildCurrentInventory(),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 1,
                        child: _buildRestockNeeded(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInventorySummary() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal, // Enable horizontal scrolling
        child: Row(
          children: [
            _buildSummaryItem(
                'Total Items', _totalItems.toString(), Colors.black),
            const SizedBox(width: 16), // Add spacing between items
            _buildSummaryItem(
                'Low Stock Items', _lowStockItems.toString(), Colors.orange),
            const SizedBox(width: 16), // Add spacing between items
            _buildSummaryItem(
                'Out of Stock', _outOfStockItems.toString(), Colors.red),
            const SizedBox(width: 16), // Add spacing between items
            _buildActionButton('Import', Icons.file_upload_outlined),
            const SizedBox(width: 8),
            _buildActionButton('Export', Icons.file_download_outlined),
            const SizedBox(width: 8),
            _buildActionButton('Print', Icons.print_outlined),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon) {
    return TextButton.icon(
      onPressed: () {
        if (label == 'Export') {
          _handleExport();
        } else if (label == 'Import') {
          _handleImport();
        } else if (label == 'Print') {
          _handlePrint();
        }
      },
      icon: Icon(icon, size: 18, color: Colors.grey[700]),
      label: Text(
        label,
        style: TextStyle(color: Colors.grey[700]),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _handleExport() async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Export Inventory'),
          content: const Text('Which inventory would you like to export?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _exportToCSV(_inventoryItems, 'current_inventory');
              },
              child: const Text('Current Inventory'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _exportToCSV(_restockNeededItems, 'restock_inventory');
              },
              child: const Text('Restock Inventory'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportToCSV(List<dynamic> items, String filename) async {
    try {
      // Prepare CSV data
      List<List<dynamic>> csvData = [];

      if (items.first is InventoryItem) {
        // Export current inventory
        csvData.add([
          'Name',
          'Category',
          'Quantity',
          'Price',
          'Status',
          'Manufacturer'
        ]); // Headers
        for (var item in items) {
          csvData.add([
            item.name,
            item.category,
            item.quantity,
            item.price,
            item.status,
            item.manufacturer
          ]);
        }
      } else {
        // Export restock needed
        csvData.add([
          'Name',
          'Category',
          'Quantity',
          'Min Quantity',
          'Status'
        ]); // Headers
        for (var item in items) {
          csvData.add([
            item.name,
            item.category,
            item.quantity,
            item.minQuantity,
            item.status
          ]);
        }
      }

      String csvString = const ListToCsvConverter().convert(csvData);
      final bytes = utf8.encode(csvString);

      if (kIsWeb) {
        // For web platform
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', '$filename.csv')
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        // For desktop/mobile platforms
        final directory = await getDownloadsDirectory();
        if (directory == null) {
          throw Exception('Could not access downloads directory');
        }

        final file = File('${directory.path}/$filename.csv');
        await file.writeAsBytes(bytes);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File exported successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleImport() async {
    try {
      if (!kIsWeb) {
        // Request storage permission only on non-web platforms
        var status = await Permission.storage.request();
        if (status.isDenied) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission denied')),
            );
          }
          return;
        }
      }

      // Show file picker
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) {
        return; // User cancelled the picker
      }

      // Show loading indicator
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
                SizedBox(width: 16),
                Text('Importing medicines...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      // Read the CSV file
      String csvString;
      if (kIsWeb) {
        // For web platform, read bytes directly
        csvString = utf8.decode(result.files.single.bytes!);
      } else {
        // For desktop/mobile, read from file path
        final file = File(result.files.single.path!);
        csvString = await file.readAsString();
      }
      final csvTable = const CsvToListConverter().convert(csvString);

      // Validate CSV format
      if (csvTable.isEmpty || csvTable.length < 2) {
        throw Exception('CSV file is empty or has no data');
      }

      // Get headers
      final headers =
          (csvTable[0] as List).map((e) => e.toString().toLowerCase()).toList();
      final requiredHeaders = [
        'name',
        'category',
        'price',
        'quantity',
        'manufacturer'
      ];

      // Validate headers
      for (var header in requiredHeaders) {
        if (!headers.contains(header)) {
          throw Exception('Missing required column: $header');
        }
      }

      // Get current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Please login first to import medicines');
      }

      // Ensure the parent user document exists and set a dummy attribute if it's the first medicine
      final userDocRef =
          FirebaseFirestore.instance.collection('medicines').doc(user.uid);
      final userDocSnapshot = await userDocRef.get();

      if (!userDocSnapshot.exists) {
        await userDocRef.set({
          'initialized': true,
          'firstMedicineAddedAt': FieldValue.serverTimestamp(),
          'lastActivity': FieldValue.serverTimestamp(),
        });
      }

      // Process each row
      int successCount = 0;
      int errorCount = 0;
      List<String> errors = [];

      for (var i = 1; i < csvTable.length; i++) {
        try {
          final row = csvTable[i] as List;
          final data = {
            'name': row[headers.indexOf('name')].toString().trim().toLowerCase(),
            'category': row[headers.indexOf('category')].toString(),
            'price': double.tryParse(row[headers.indexOf('price')].toString()) ?? 0.0,
            'quantity': int.tryParse(row[headers.indexOf('quantity')].toString()) ?? 0,
            'manufacturer': row[headers.indexOf('manufacturer')].toString(),
            'created_at': FieldValue.serverTimestamp(),
          };

          // Search for an existing medicine with the same name, category, and manufacturer
          final querySnapshot = await FirebaseFirestore.instance
              .collection('medicines')
              .doc(user.uid)
              .collection('user_medicines')
              .where('name', isEqualTo: data['name'])
              .where('category', isEqualTo: data['category'])
              .where('manufacturer', isEqualTo: data['manufacturer'])
              .get();

          if (querySnapshot.docs.isNotEmpty) {
            // Medicine exists, update quantity and price
            final doc = querySnapshot.docs.first;
            final currentQuantity = (doc.data()['quantity'] ?? 0) as int;
            final newQuantity = currentQuantity + (data['quantity'] as int);
            await doc.reference.update({
              'quantity': newQuantity,
              'price': data['price'],
              'created_at': FieldValue.serverTimestamp(),
            });
          } else {
            // Medicine does not exist, add new
            final medicineDocRef = FirebaseFirestore.instance
                .collection('medicines')
                .doc(user.uid)
                .collection('user_medicines')
                .doc(data['name'].toString().toLowerCase());
            await medicineDocRef.set(data);
          }

          successCount++;
        } catch (e) {
          errorCount++;
          errors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      // Clear loading snackbar
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }

      // Show results
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Import Results'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total records processed: ${csvTable.length - 1}'),
                    const SizedBox(height: 8),
                    Text('Successfully imported: $successCount',
                        style: const TextStyle(color: Colors.green)),
                    if (errorCount > 0) ...[
                      const SizedBox(height: 4),
                      Text('Failed to import: $errorCount',
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                      const Text('Error Details:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      ...errors
                          .map((error) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  error,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ))
                          .toList(),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      // Clear loading snackbar
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }

      // Show error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import medicines: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'DISMISS',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _handlePrint() async {
    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Print Inventory'),
          content: const Text('Which inventory would you like to print?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'current'),
              child: const Text('Current Inventory'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'restock'),
              child: const Text('Restock Inventory'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (result == 'current') {
      await _printInventory(_inventoryItems, isRestock: false);
    } else if (result == 'restock') {
      await _printInventory(_restockNeededItems, isRestock: true);
    }
  }

  Future<void> _printInventory(List items, {required bool isRestock}) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                isRestock ? 'Restock Inventory' : 'Current Inventory',
                style:
                    pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 16),
              pw.Table.fromTextArray(
                headers: isRestock
                    ? ['Name', 'Category', 'Quantity', 'Min Quantity', 'Status']
                    : [
                        'Name',
                        'Category',
                        'Quantity',
                        'Price',
                        'Status',
                        'Manufacturer'
                      ],
                data: items.map((item) {
                  if (isRestock) {
                    return [
                      item.name,
                      item.category,
                      item.quantity.toString(),
                      item.minQuantity.toString(),
                      item.status,
                    ];
                  } else {
                    return [
                      item.name,
                      item.category,
                      item.quantity.toString(),
                      'Rs ${item.price.toStringAsFixed(2)}',
                      item.status,
                      item.manufacturer,
                    ];
                  }
                }).toList(),
                cellStyle: const pw.TextStyle(fontSize: 10),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
                cellAlignment: pw.Alignment.centerLeft,
              ),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Widget _buildCurrentInventory() {
    // Add these print statements for debugging
    print('Search Query: $_searchQuery');
    print('Selected Category: $_currentInventorySelectedCategory');
    print('Price Range: $_currentInventoryPriceRange');

    // Filter items based on search query AND category/price filters
    List<InventoryItem> filteredItems = _inventoryItems.where((item) {
      bool matchesSearch = item.name
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          item.category.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.manufacturer.toLowerCase().contains(_searchQuery.toLowerCase());

      bool matchesCategory = true;
      if (_currentInventorySelectedCategory != null &&
          _currentInventorySelectedCategory != 'All Categories') {
        matchesCategory = item.category == _currentInventorySelectedCategory;
      }

      bool matchesPrice = true;
      if (_currentInventoryPriceRange != null) {
        matchesPrice = item.price >= _currentInventoryPriceRange!.start &&
            item.price <= _currentInventoryPriceRange!.end;
      }

      // --- ADD THESE PRINT STATEMENTS ---
      print('Filtering Current Inventory - Item: ${item.name}');
      print('  Matches Search: $matchesSearch (Query: "$_searchQuery")');
      print(
          '  Matches Category: $matchesCategory (Selected: "$_currentInventorySelectedCategory")');
      print(
          '  Matches Price: $matchesPrice (Range: $_currentInventoryPriceRange)');
      // ----------------------------------

      return matchesSearch && matchesCategory && matchesPrice;
    }).toList();

    // Add this print statement for debugging
    print('Filtered Items Count: ${filteredItems.length}');

    // Apply pagination
    final int totalPages = (filteredItems.length / _itemsPerPage).ceil();
    final int startIndex = _currentPage * _itemsPerPage;
    int endIndex = startIndex + _itemsPerPage;
    if (endIndex > filteredItems.length) {
      endIndex = filteredItems.length;
    }

    final List<InventoryItem> displayedItems =
        filteredItems.sublist(startIndex, endIndex);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Flexible(
                  child: Text(
                    'Current Inventory',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        const Icon(Icons.search, size: 20, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              hintText: 'Search medicines...',
                              border: InputBorder.none,
                              hintStyle: TextStyle(fontSize: 14),
                              isDense: true,
                              contentPadding: EdgeInsets.only(bottom: 8),
                            ),
                            style: const TextStyle(fontSize: 14),
                            onSubmitted: (value) {
                              setState(() {
                                _searchQuery = value;
                                _currentPage =
                                    0; // Reset to first page on search
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: ElevatedButton(
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
                                    final user = FirebaseAuth.instance.currentUser;
                                    if (user == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please login first')),
                                      );
                                      return;
                                    }
                                    if (medicineName.trim().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Medicine name is required')),
                                      );
                                      return;
                                    }
                                    final userMedicinesCollectionRef = FirebaseFirestore
                                        .instance
                                        .collection('medicines')
                                        .doc(user.uid)
                                        .collection('user_medicines');
                                    final userDocRef = FirebaseFirestore.instance
                                        .collection('medicines')
                                        .doc(user.uid);
                                    final userDocSnapshot = await userDocRef.get();
                                    if (!userDocSnapshot.exists) {
                                      await userDocRef.set({
                                        'initialized': true,
                                        'firstMedicineAddedAt': FieldValue.serverTimestamp(),
                                        'lastActivity': FieldValue.serverTimestamp(),
                                      });
                                    }
                                    final querySnapshot = await userMedicinesCollectionRef
                                        .where('name', isEqualTo: medicineName.trim().toLowerCase())
                                        .where('category', isEqualTo: category)
                                        .where('manufacturer', isEqualTo: manufacturer)
                                        .get();
                                    if (querySnapshot.docs.isNotEmpty) {
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
                                    } else {
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
                                    }
                                    await userDocRef.update({
                                      'lastActivity': FieldValue.serverTimestamp(),
                                    });
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Medicine added/updated successfully')),
                                      );
                                      Navigator.of(context).pop();
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error adding medicine: $e')),
                                      );
                                    }
                                  }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2A3467),
                                    ),
                                child: const Text('Add New Medicine', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A3467),
                    padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                      minimumSize: Size(40, 40),
                      maximumSize: Size(40, 40),
                    ),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[100],
            child: Row(
              children: const [
                Expanded(
                  flex: 2,
                  child: Text(
                    'PRODUCT',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'CATEGORY',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'QUANTITY',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'PRICE',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'STATUS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300), // Add max height
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedItems.length,
              itemBuilder: (context, index) {
                final item = displayedItems[index];
                return Container(
                  decoration: BoxDecoration(
                    color: index.isEven
                        ? Colors.grey[50]
                        : Colors.white, // Zebra striping
                    border:
                        Border(bottom: BorderSide(color: Colors.grey[200]!)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: item.iconColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  item.icon,
                                  color: item.iconColor,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            item.category,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            item.quantity.toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Rs ${item.price.toStringAsFixed(2)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: item.status == 'In Stock'
                                  ? Colors.green[50]
                                  : (item.status == 'Low Stock'
                                      ? Colors.orange[50]
                                      : Colors.red[50]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.status,
                              style: TextStyle(
                                color: item.status == 'In Stock'
                                    ? Colors.green[700]
                                    : (item.status == 'Low Stock'
                                        ? Colors.orange[700]
                                        : Colors.red[700]),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () {
                              _deleteMedicine(item.id);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'Showing ${startIndex + 1} - ${endIndex} of ${filteredItems.length}',
                    style: TextStyle(color: Colors.grey[600]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 32,
                  child: ListView(
                    shrinkWrap: true,
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildPaginationButton('Previous', _currentPage > 0, () {
                        setState(() {
                          _currentPage--;
                        });
                      }),
                      ..._buildPageNumberButtons(_currentPage, totalPages, (i) {
                        setState(() {
                          _currentPage = i;
                        });
                      }),
                      _buildPaginationButton(
                          'Next', _currentPage < totalPages - 1, () {
                        setState(() {
                          _currentPage++;
                        });
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestockNeeded() {
    List<RestockItem> filteredRestockItems = _restockNeededItems.where((item) {
      bool matchesCategory = true;
      if (_restockNeededSelectedCategory != null &&
          _restockNeededSelectedCategory != 'All Categories') {
        matchesCategory = item.category == _restockNeededSelectedCategory;
      }

      bool matchesPrice = true;
      // Note: RestockItem currently doesn't have a 'price' property.
      // If price filtering is expected, 'price' needs to be added to RestockItem
      // or fetched from the corresponding InventoryItem.
      // For now, price filtering for RestockItem will not work if RestockItem itself doesn't have price.

      // --- ADD THESE PRINT STATEMENTS ---
      print('Filtering Restock Needed - Item: [38;5;2m${item.name}[0m');
      print(
          '  Matches Category: $matchesCategory (Selected: "$_restockNeededSelectedCategory")');
      print(
          '  Matches Price: $matchesPrice (Price filtering is currently skipped for RestockItem)'); // Updated print
      // ----------------------------------

      return matchesCategory && matchesPrice;
    }).toList();

    // Pagination for restock needed
    final int restockTotalPages = (filteredRestockItems.length / _restockItemsPerPage).ceil();
    final int restockStartIndex = _restockCurrentPage * _restockItemsPerPage;
    int restockEndIndex = restockStartIndex + _restockItemsPerPage;
    if (restockEndIndex > filteredRestockItems.length) {
      restockEndIndex = filteredRestockItems.length;
    }
    final List<RestockItem> displayedRestockItems =
        filteredRestockItems.sublist(restockStartIndex, restockEndIndex);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Flexible(
                  child: Text(
                    'Restock Needed',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        const Icon(Icons.search, size: 20, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Search low stock or out of stock...',
                              border: InputBorder.none,
                              hintStyle: TextStyle(fontSize: 14),
                              isDense: true,
                              contentPadding: EdgeInsets.only(bottom: 8),
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[100],
            child: Row(
              children: const [
                Expanded(
                  flex: 2,
                  child: Text(
                    'PRODUCT',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'CATEGORY',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'QUANTITY',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'MIN QUANTITY',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'STATUS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'ACTION',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300), // Add max height
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedRestockItems.length,
              itemBuilder: (context, index) {
                final item = displayedRestockItems[index];
                return Container(
                  decoration: BoxDecoration(
                    color: index.isEven
                        ? Colors.grey[50]
                        : Colors.white, // Zebra striping
                    border:
                        Border(bottom: BorderSide(color: Colors.grey[200]!)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: item.iconColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  item.icon,
                                  color: item.iconColor,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            item.category,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            item.quantity.toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            item.minQuantity.toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: item.status == 'Out of Stock'
                                  ? Colors.red[50]
                                  : Colors.orange[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.status,
                              style: TextStyle(
                                color: item.status == 'Out of Stock'
                                    ? Colors.red[700]
                                    : Colors.orange[700],
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.refresh,
                                    color: Colors.blue[400]),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      String restockQuantity = '';
                                      return AlertDialog(
                                        title: Text('Restock ${item.name}'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Current stock: ${item.quantity}',
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey[700]),
                                            ),
                                            const SizedBox(height: 10),
                                            TextField(
                                              decoration: const InputDecoration(
                                                labelText: 'Add Quantity',
                                                hintText:
                                                    'Enter quantity to add',
                                                border: OutlineInputBorder(),
                                              ),
                                              keyboardType:
                                                  TextInputType.number,
                                              onChanged: (value) =>
                                                  restockQuantity = value,
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () async {
                                              try {
                                                final user = FirebaseAuth
                                                    .instance.currentUser;
                                                if (user == null) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                          content: Text(
                                                              'Please login first to restock medicine')),
                                                    );
                                                    Navigator.of(context).pop();
                                                  }
                                                  return;
                                                }

                                                int quantityToAdd =
                                                    int.tryParse(
                                                            restockQuantity) ??
                                                        0;
                                                if (quantityToAdd <= 0) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                          content: Text(
                                                              'Please enter a valid quantity')),
                                                    );
                                                  }
                                                  return;
                                                }

                                                // Get current medicine document
                                                DocumentReference medicineRef =
                                                    FirebaseFirestore.instance
                                                        .collection('medicines')
                                                        .doc(user.uid)
                                                        .collection(
                                                            'user_medicines')
                                                        .doc(item.id);

                                                await FirebaseFirestore.instance
                                                    .runTransaction(
                                                        (transaction) async {
                                                  DocumentSnapshot snapshot =
                                                      await transaction
                                                          .get(medicineRef);
                                                  if (!snapshot.exists) {
                                                    throw Exception(
                                                        "Medicine does not exist!");
                                                  }

                                                  int currentQuantity =
                                                      (snapshot.data() as Map<
                                                                  String,
                                                                  dynamic>)[
                                                              'quantity'] ??
                                                          0;
                                                  int newQuantity =
                                                      currentQuantity +
                                                          quantityToAdd;

                                                  transaction.update(
                                                      medicineRef, {
                                                    'quantity': newQuantity
                                                  });
                                                });

                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                        content: Text(
                                                            '${item.name} restocked by $quantityToAdd units')),
                                                  );
                                                  Navigator.of(context).pop();
                                                }
                                              } catch (e) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                        content: Text(
                                                            'Error restocking medicine: $e')),
                                                  );
                                                }
                                              }
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF2A3467),
                                            ),
                                            child: const Text('Restock',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                onPressed: () {
                                  _deleteMedicine(item.id);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'Showing ${restockStartIndex + 1} - ${restockEndIndex} of ${filteredRestockItems.length}',
                    style: TextStyle(color: Colors.grey[600]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 32,
                  child: ListView(
                    shrinkWrap: true,
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildPaginationButton('Previous', _restockCurrentPage > 0, () {
                        setState(() {
                          _restockCurrentPage--;
                        });
                      }),
                      ..._buildPageNumberButtons(_restockCurrentPage, restockTotalPages, (i) {
                        setState(() {
                          _restockCurrentPage = i;
                        });
                      }),
                      _buildPaginationButton('Next', _restockCurrentPage < restockTotalPages - 1, () {
                        setState(() {
                          _restockCurrentPage++;
                        });
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationButton(
      String label, bool isEnabled, VoidCallback onPressed) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: OutlinedButton(
        onPressed: isEnabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          backgroundColor: Colors.white,
          side: BorderSide(color: Colors.grey[300]!),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isEnabled ? Colors.black : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildPaginationNumberButton(
      String number, bool isActive, VoidCallback onPressed) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          backgroundColor: isActive ? Colors.blue : Colors.white,
          side: BorderSide(color: isActive ? Colors.blue : Colors.grey[300]!),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        child: Text(
          number,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  // Helper for pagination buttons (5 max)
  List<Widget> _buildPageNumberButtons(int currentPage, int totalPages, Function(int) onTap) {
    List<Widget> buttons = [];
    int startPage = 0;
    int endPage = totalPages - 1;
    if (totalPages > 5) {
      if (currentPage <= 2) {
        startPage = 0;
        endPage = 4;
      } else if (currentPage >= totalPages - 3) {
        startPage = totalPages - 5;
        endPage = totalPages - 1;
      } else {
        startPage = currentPage - 2;
        endPage = currentPage + 2;
      }
    }
    for (int i = startPage; i <= endPage && i < totalPages; i++) {
      buttons.add(_buildPaginationNumberButton((i + 1).toString(), i == currentPage, () => onTap(i)));
    }
    return buttons;
  }
}

class InventoryItem {
  final String id;
  final String name;
  final String category;
  final int quantity;
  final double price;
  final String status;
  final IconData icon;
  final Color iconColor;
  final String manufacturer;

  InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.price,
    required this.status,
    required this.icon,
    required this.iconColor,
    required this.manufacturer,
  });

  factory InventoryItem.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    int quantity = (data['quantity'] ?? 0) as int;
    String status;
    Color iconColor;

    if (quantity <= 0) {
      status = 'Out of Stock';
      iconColor = Colors.red;
    } else if (quantity < 50) {
      status = 'Low Stock';
      iconColor = Colors.orange;
    } else {
      status = 'In Stock';
      iconColor = Colors.green;
    }

    return InventoryItem(
      id: doc.id,
      name: (data['name'] ?? '').toString().trim().toLowerCase(),
      category: data['category'] ?? '',
      quantity: quantity,
      price: (data['price'] ?? 0.0) as double,
      status: status,
      icon: Icons.medication,
      iconColor: iconColor,
      manufacturer: data['manufacturer'] ?? '',
    );
  }
}

class RestockItem {
  final String id;
  final String name;
  final String category;
  final int quantity;
  final int minQuantity;
  final String status;
  final IconData icon;
  final Color iconColor;

  RestockItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.minQuantity,
    required this.status,
    required this.icon,
    required this.iconColor,
  });
}
