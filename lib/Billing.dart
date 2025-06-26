import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'dart:io' show Platform;
// Conditional import for web support
import 'dart:html' if (dart.library.io) 'dart:io' as platform;

class Bill {
  List<Product> products;
  String customerName;
  Bill({this.products = const [], this.customerName = ''});
}

class POSScreen extends StatefulWidget {
  final String customerName;
  final List<Map<String, dynamic>> medicines;
  final String? userId;
  final String? orderId;

  const POSScreen({
    Key? key,
    this.customerName = '',
    this.medicines = const [],
    this.userId,
    this.orderId,
  }) : super(key: key);

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  int _activeTabIndex = 0;

  // For search functionality
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Product> _searchResults = [];
  bool _showSearchResults = false;

  // For Custom Price and other input fields
  final TextEditingController _quantityController =
      TextEditingController(text: '1');
  final TextEditingController _subQuantityController =
      TextEditingController(text: '0');
  final TextEditingController _discountController =
      TextEditingController(text: '0');
  final TextEditingController _customPriceController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _gstController =
      TextEditingController(text: '16');
  final TextEditingController _paidAmountController =
      TextEditingController(text: '0');

  // List to hold products added to the bill
  final List<Product> _selectedProducts = [];

  // Currently selected product from search, before adding to bill
  Product? _currentSelectedProduct;

  List<Bill> _bills = [Bill()];

  // Map to store products for each bill tab
  final Map<int, List<Product>> _billProducts = {0: []};

  // Currently selected item index in the product table for deletion
  int? _selectedBillItemIndex;

  // Add GST switch state
  bool _isGSTEnabled = false;

  @override
  void initState() {
    super.initState();
    // Initialize first tab's products
    _billProducts[0] = [];
    _selectedProducts.clear();

    // Populate initial customer name and medicines if provided
    if (widget.customerName.isNotEmpty) {
      _customerNameController.text = widget.customerName;
      _bills[0].customerName = widget.customerName;
    }
    if (widget.medicines.isNotEmpty) {
      for (var med in widget.medicines) {
        _selectedProducts.add(Product(
          name: med['name'] ?? '',
          quantity: med['quantity'] ?? 0,
          subQuantity: 0, // Assuming subQuantity is 0 if not provided
          price: med['price'] ?? 0.0,
          discountPrice: med['price'] ??
              0.0, // Assuming discountPrice is same as price initially
          discount: 0.0, // Assuming no initial discount
        ));
      }
      _billProducts[0] = List.from(_selectedProducts);
    }

    _tabController = TabController(length: _bills.length, vsync: this);
    _tabController.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) {
      setState(() {
        // Save current tab's products and customer name before switching
        if (_activeTabIndex >= 0 && _activeTabIndex < _bills.length) {
          _billProducts[_activeTabIndex] = List.from(_selectedProducts);
          _bills[_activeTabIndex].customerName = _customerNameController.text;
        }

        // Update active index
        _activeTabIndex = _tabController.index;

        // Clear product-related input fields
        _clearInputFields();
        _searchResults.clear();
        _showSearchResults = false;
        _currentSelectedProduct = null;

        // Load products and customer name for the new tab
        _selectedProducts.clear();
        if (_billProducts.containsKey(_activeTabIndex)) {
          _selectedProducts.addAll(_billProducts[_activeTabIndex] ?? []);
        } else {
          _billProducts[_activeTabIndex] = [];
        }
        _customerNameController.text = _bills[_activeTabIndex].customerName;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _quantityController.dispose();
    _subQuantityController.dispose();
    _discountController.dispose();
    _customPriceController.dispose();
    _customerNameController.dispose();
    _gstController.dispose();
    _paidAmountController.dispose();
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  // Helper function to show a toast message (SnackBar)
  void _showToast(String message, {Color? backgroundColor, Color? textColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
              color: textColor ??
                  Colors.white), // Default to white if textColor is null
        ),
        backgroundColor: backgroundColor ??
            Theme.of(context)
                .snackBarTheme
                .backgroundColor, // Default to theme's background
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _searchMedicines(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      print('User not logged in. Cannot perform medicine search.');
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    try {
      // Get all medicines and filter locally for better search results
      final snapshot = await FirebaseFirestore.instance
          .collection('medicines')
          .doc(user.uid)
          .collection('user_medicines')
          .get();

      final searchQuery = query.toLowerCase();

      setState(() {
        _searchResults = snapshot.docs
            .map((doc) {
              final data = doc.data();
              return Product(
                name: (data['name'] ?? '').toString(),
                quantity: data['quantity'] ?? 0,
                price: (data['price'] ?? 0.0).toDouble(),
                discountPrice: (data['discountPrice'] ?? 0.0).toDouble(),
                discount: (data['discount'] ?? 0.0).toDouble(),
                subQuantity: data['subQuantity'] ?? 0,
              );
            })
            .where(
                (product) => product.name.toLowerCase().contains(searchQuery))
            .toList();

        _showSearchResults = _searchResults.isNotEmpty;
      });
    } catch (error) {
      print('Error searching medicines: $error');
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
    }
  }

  void _selectMedicine(Product product) {
    setState(() {
      _currentSelectedProduct = product;
      _searchController.text = product.name;
      // Set the custom price to the medicine's price from database
      _customPriceController.text = product.price.toStringAsFixed(2);
      // Reset other fields to default values
      _quantityController.text = '1';
      _subQuantityController.text = '0';
      _discountController.text = '0';
      _searchResults = []; // Clear search results after selection
      _showSearchResults = false;
    });
    // Unfocus the search field after the current frame is built to ensure text update is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.unfocus();
    });
  }

  void _addItemToBill() async {
    if (_currentSelectedProduct != null) {
      final quantity = int.tryParse(_quantityController.text) ?? 1;
      final subQuantity = int.tryParse(_subQuantityController.text) ?? 0;
      final discount = double.tryParse(_discountController.text) ?? 0.0;
      final customPrice = double.tryParse(_customPriceController.text) ??
          _currentSelectedProduct!.price;

      // Check if currentSelectedProduct is not null before proceeding
      if (_currentSelectedProduct == null) {
        _showToast('Please select a product first.');
        return;
      }

      // Attempt to update stock in Firebase. Await this call.
      bool stockUpdated = await _updateMedicineStockInFirebase(
          _currentSelectedProduct!, quantity);

      if (stockUpdated) {
        // Only add to bill if stock update was successful
        setState(() {
          final itemToAdd = Product(
            name: _currentSelectedProduct!.name,
            quantity: quantity,
            subQuantity: subQuantity,
            price: _currentSelectedProduct!.price, // Original price
            discountPrice:
                customPrice, // Using custom price as discounted price
            discount: discount,
          );
          _selectedProducts.add(itemToAdd);
          _clearInputFields();
        });
      }
      // If not updated, do not add to bill (toast already shown)
    }
  }

  void _deleteItemFromBill(int index) {
    setState(() {
      if (_selectedBillItemIndex != null &&
          _selectedBillItemIndex! < _selectedProducts.length) {
        _selectedProducts.removeAt(_selectedBillItemIndex!);
        _selectedBillItemIndex = null; // Clear selection after deletion
        _showToast('Item deleted successfully!');
      } else {
        _showToast('Please select an item to delete.',
            backgroundColor: Colors.red);
      }
    });
  }

  void _clearInputFields() {
    _searchController.clear();
    _quantityController.text = '1';
    _subQuantityController.text = '0';
    _discountController.text = '0';
    _customPriceController.clear();
    _gstController.text = '16';
    _paidAmountController.text = '0';
    _currentSelectedProduct = null;
  }

  double get _subTotal {
    return _selectedProducts.fold(
        0.0, (sum, item) => sum + (item.quantity * item.discountPrice));
  }

  double get _gstAmount {
    if (!_isGSTEnabled) return 0.0;
    final gstPercentage = double.tryParse(_gstController.text) ?? 16.0;
    return _subTotal * (gstPercentage / 100);
  }

  double get _grandTotal {
    return _subTotal + _gstAmount;
  }

  double get _dueAmount {
    final paidAmount = double.tryParse(_paidAmountController.text) ?? 0.0;
    return _grandTotal - paidAmount;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: const Color(0xFF353A5A),
              labelColor: const Color(0xFF353A5A),
              tabs: List.generate(
                  _bills.length,
                  (index) => Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Bill ${index + 1}',
                                style: TextStyle(fontSize: 14)),
                            IconButton(
                              icon: Icon(Icons.close, size: 16),
                              onPressed: () => _closeBillTab(index),
                              padding: EdgeInsets.only(left: 8),
                              constraints: BoxConstraints(),
                            ),
                          ],
                        ),
                      )),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: List.generate(
                  _bills.length, (index) => _buildBillingSession(index)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingSession(int billIndex) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInputSection(),
            const SizedBox(height: 12),
            _buildProductTable(),
            const SizedBox(height: 12),
            _buildPaymentSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search product
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF353A5A)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF353A5A),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(3),
                          topRight: Radius.circular(3),
                        ),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.search, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('Search product',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    Container(
                      color: Colors.white,
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        decoration: const InputDecoration(
                          hintText: 'Type medicine name to search',
                          contentPadding: EdgeInsets.all(12),
                          border: InputBorder.none,
                        ),
                        onChanged: (value) {
                          _searchMedicines(value);
                        },
                      ),
                    ),
                    if (_showSearchResults)
                      Container(
                        color: Colors.white,
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: _searchResults.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Text('No medicines found'),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final product = _searchResults[index];
                                  return ListTile(
                                    title: Text(product.name),
                                    subtitle: Text(
                                      'Price: ${product.price.toStringAsFixed(2)} | Stock: ${product.quantity}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    onTap: () => _selectMedicine(product),
                                  );
                                },
                              ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Customer Name
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF353A5A)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF353A5A),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(3),
                          topRight: Radius.circular(3),
                        ),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.person, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('Customer Name',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    Container(
                      color: Colors.white,
                      child: TextField(
                        controller: _customerNameController,
                        decoration: const InputDecoration(
                          hintText: 'Enter customer name',
                          contentPadding: EdgeInsets.all(12),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        // Quantity fields
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInputField('Quantity', controller: _quantityController),
            const SizedBox(width: 12),
            _buildInputField('SubQuantity', controller: _subQuantityController),
            const SizedBox(width: 12),
            _buildInputField('Discount', controller: _discountController),
            const SizedBox(width: 12),
            _buildInputField('Custom Price',
                controller: _customPriceController),
          ],
        ),

        // Price and buttons
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _buildActionButton('Add Item', const Color(0xFF353A5A),
                onPressed: _addItemToBill),
            const SizedBox(width: 12),
            _buildActionButton('Delete Item', Colors.red,
                onPressed: () => _deleteItemFromBill(_selectedProducts.length -
                    1)), // Deletes the last item for now
          ],
        ),
      ],
    );
  }

  Widget _buildInputField(String label, {TextEditingController? controller}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.black87)),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType
                  .number, // Set keyboard type for numerical inputs
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String text, Color color,
      {VoidCallback? onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 120,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _buildProductTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF353A5A)),
        borderRadius: BorderRadius.circular(4),
      ),
      height: 300,
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF353A5A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(3),
                topRight: Radius.circular(3),
              ),
            ),
            child: Row(
              children: const [
                Expanded(
                    flex: 3,
                    child: Text('Product',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 13))),
                Expanded(
                    child: Center(
                        child: Text('Qty',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13)))),
                Expanded(
                    child: Center(
                        child: Text('Sub Qty',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13)))),
                Expanded(
                    child: Center(
                        child: Text('Price',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13)))),
                Expanded(
                    child: Center(
                        child: Text('Disc. Price',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13)))),
                Expanded(
                    child: Center(
                        child: Text('Disc. Amount',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13)))),
                Expanded(
                    child: Center(
                        child: Text('Line Total',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13)))),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              child: ListView.builder(
                itemCount: _selectedProducts.length,
                itemBuilder: (context, index) {
                  final product = _selectedProducts[index];
                  final lineTotal = product.quantity * product.discountPrice;
                  final discountAmount = product.processDiscount();
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedBillItemIndex = index;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 8),
                      decoration: BoxDecoration(
                        color: _selectedBillItemIndex == index
                            ? Colors.blue.withOpacity(0.2)
                            : (index.isEven ? Colors.white : Colors.grey[100]),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                              flex: 3,
                              child: Text(product.name,
                                  style: const TextStyle(fontSize: 13))),
                          Expanded(
                              child: Center(
                                  child: Text(product.quantity.toString(),
                                      style: const TextStyle(fontSize: 13)))),
                          Expanded(
                              child: Center(
                                  child: Text(product.subQuantity.toString(),
                                      style: const TextStyle(fontSize: 13)))),
                          Expanded(
                              child: Center(
                                  child: Text(product.price.toStringAsFixed(2),
                                      style: const TextStyle(fontSize: 13)))),
                          Expanded(
                              child: Center(
                                  child: Text(
                                      product.discountPrice.toStringAsFixed(2),
                                      style: const TextStyle(fontSize: 13)))),
                          Expanded(
                              child: Center(
                                  child: Text(
                                      discountAmount == 0.0
                                          ? '-0.00'
                                          : discountAmount.toStringAsFixed(2),
                                      style: const TextStyle(fontSize: 13)))),
                          Expanded(
                              child: Center(
                                  child: Text(lineTotal.toStringAsFixed(2),
                                      style: const TextStyle(fontSize: 13)))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSection() {
    double subtotal = _selectedProducts.fold(
        0, (sum, item) => sum + (item.discountPrice * item.quantity));
    double gstAmount = _isGSTEnabled ? subtotal * 0.16 : 0;
    double grandTotal = subtotal + gstAmount;
    double paidAmount = double.tryParse(_paidAmountController.text) ?? 0;
    double dueAmount = grandTotal - paidAmount;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF353A5A),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Text('Enable GST (16%)',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    const SizedBox(width: 8),
                    Switch(
                      value: _isGSTEnabled,
                      onChanged: (value) {
                        setState(() {
                          _isGSTEnabled = value;
                        });
                      },
                      activeColor: Colors.green,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildPaymentField('Sub Total', subtotal.toStringAsFixed(2)),
              const SizedBox(width: 6),
              _buildPaymentField('GST Amount', gstAmount.toStringAsFixed(2)),
              const SizedBox(width: 8),
              _buildPaymentField('Grand Total', grandTotal.toStringAsFixed(2)),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: _buildPaymentField(
                  'Paid Amount',
                  _paidAmountController.text,
                  isInput: true,
                  onChanged: (value) {
                    setState(() {});
                  },
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              _buildPaymentField('Due Amount', dueAmount.toStringAsFixed(2)),
              const SizedBox(width: 12),
              _buildFunctionButton('F5', 'PAY', Colors.blueGrey.shade400,
                  onPressed: _showPaymentConfirmationDialog),
              const SizedBox(width: 6),
              _buildFunctionButton('F2', 'NEW', Colors.blueGrey.shade300,
                  onPressed: _addNewBillTab),
              const SizedBox(width: 6),
              _buildFunctionButton('F6', 'SAVE', Colors.blueGrey.shade300,
                  onPressed: _saveBillAsPDF),
              const SizedBox(width: 6),
              _buildFunctionButton('F7', 'RETURN', Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentField(String label, String value,
      {bool isInput = false,
      bool isRedInput = false,
      Function(String)? onChanged,
      TextAlign textAlign = TextAlign.start}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
          const SizedBox(height: 2),
          Container(
            height: 36, // Fixed height for consistent box size
            decoration: BoxDecoration(
              color: isRedInput ? Colors.red : Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            child: isInput && onChanged != null
                ? TextField(
                    controller: _paidAmountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      color: isRedInput ? Colors.white : Colors.black,
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.zero, // Remove internal TextField padding
                      isDense: true, // Make the input field dense
                    ),
                    onChanged: onChanged,
                  )
                : Center(
                    // Center the text within the fixed height container
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                      ),
                      textAlign: textAlign,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFunctionButton(String function, String label, Color color,
      {VoidCallback? onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 50,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 4),
            Text(function,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
            const SizedBox(height: 2),
            Icon(
              label == 'PAY'
                  ? Icons.credit_card
                  : label == 'NEW'
                      ? Icons.add
                      : label == 'SAVE'
                          ? Icons.save
                          : Icons.refresh,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 10)),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _addNewBillTab() {
    setState(() {
      // Save current bill's products
      if (_activeTabIndex >= 0) {
        _billProducts[_activeTabIndex] = List.from(_selectedProducts);
      }

      // Add new bill
      final newIndex = _bills.length;
      _bills.add(Bill());
      _billProducts[newIndex] = [];

      // Update tab controller
      _tabController.dispose();
      _tabController = TabController(length: _bills.length, vsync: this);
      _tabController.addListener(_handleTabChange);

      // Switch to new tab
      _activeTabIndex = newIndex;
      _selectedProducts.clear();

      // Clear input fields for the new bill, including customer name
      _clearInputFields();
      _customerNameController
          .clear(); // Explicitly clear customer name for the new bill
      _searchResults.clear();
      _showSearchResults = false;
      _currentSelectedProduct = null;

      _tabController.animateTo(newIndex);
    });
  }

  void _showPaymentConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Payment Confirmation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sub Total: Rs ${_subTotal.toStringAsFixed(2)}'),
              if (_isGSTEnabled) // Only show GST if enabled
                Text('GST Amount: Rs ${_gstAmount.toStringAsFixed(2)}'),
              Text('Grand Total: Rs ${_grandTotal.toStringAsFixed(2)}'),
              const Divider(),
              Text('Paid Amount: Rs ${_paidAmountController.text}'),
              Text('Due Amount: Rs ${_dueAmount.toStringAsFixed(2)}'),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close the dialog
                await _saveBillAsPDF(); // Generate and save the PDF
              },
              child: const Text('Generate Bill & Print Slip'),
            ),
          ],
        );
      },
    );
  }

  void _closeBillTab(int index) {
    if (_bills.length <= 1) {
      _showToast('Cannot close the last bill tab');
      return;
    }

    setState(() {
      // Remove the bill's products
      _billProducts.remove(index);

      // Shift remaining bill products
      final newBillProducts = <int, List<Product>>{};
      for (var i = 0; i < _bills.length; i++) {
        if (i < index) {
          newBillProducts[i] = _billProducts[i] ?? [];
        } else if (i > index) {
          newBillProducts[i - 1] = _billProducts[i] ?? [];
        }
      }
      _billProducts.clear();
      _billProducts.addAll(newBillProducts);

      _bills.removeAt(index);

      // Update tab controller
      _tabController.dispose();
      _tabController = TabController(length: _bills.length, vsync: this);
      _tabController.addListener(_handleTabChange);

      // Set the new active index
      if (_activeTabIndex >= _bills.length) {
        _activeTabIndex = _bills.length - 1;
      }

      // Load products for the new active tab
      _selectedProducts.clear();
      if (_billProducts.containsKey(_activeTabIndex)) {
        _selectedProducts.addAll(_billProducts[_activeTabIndex] ?? []);
      }

      _tabController.animateTo(_activeTabIndex);
    });
  }

  Future<void> _saveBillAsPDF() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showToast('User not logged in. Cannot save bill.');
        return;
      }

      // Prepare bill data for Firestore
      final billData = {
        'billId':
            'BILL_ 2${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}_${DateTime.now().millisecondsSinceEpoch}',
        'customerName': _customerNameController.text.trim().isEmpty
            ? 'N/A'
            : _customerNameController.text.trim(),
        'billDate': FieldValue.serverTimestamp(),
        'items': _selectedProducts
            .map((product) => {
                  'name': product.name,
                  'quantity': product.quantity,
                  'subQuantity': product.subQuantity,
                  'price': product.price,
                  'discountPrice': product.discountPrice,
                  'discount': product.discount,
                  'lineTotal': product.quantity * product.discountPrice,
                  'discountAmount': product.processDiscount(),
                })
            .toList(),
        'subTotal': _subTotal,
        'gstEnabled': _isGSTEnabled,
        'gstPercentage': _isGSTEnabled
            ? (double.tryParse(_gstController.text) ?? 16.0)
            : 0.0,
        'gstAmount': _gstAmount,
        'grandTotal': _grandTotal,
        'paidAmount': double.tryParse(_paidAmountController.text) ?? 0.0,
        'dueAmount': _dueAmount,
        'paymentStatus': _dueAmount <= 0 ? 'Paid' : 'Partial',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Store bill in Firestore under Revenue -> user.uid -> sales
      final salesRef = FirebaseFirestore.instance
          .collection('Revenue')
          .doc(user.uid)
          .collection('sales');

      // Add the bill document
      final billDocRef = await salesRef.add(billData);
      print('Bill saved to Firestore with ID: ${billDocRef.id}');

      // Update daily revenue
      final dailyMetricsRef = FirebaseFirestore.instance
          .collection('Revenue')
          .doc(user.uid)
          .collection('daily_metrics')
          .doc('revenue_summary');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(dailyMetricsRef);
        double currentRevenue = 0.0;
        int totalSales = 0;
        Timestamp? lastUpdated;

        if (snapshot.exists) {
          final data = snapshot.data();
          currentRevenue = (data?['dailyRevenue'] as num?)?.toDouble() ?? 0.0;
          totalSales = (data?['totalSales'] as int?) ?? 0;
          lastUpdated = data?['lastUpdated'] as Timestamp?;
        }

        // Check if 24 hours have passed since last update for reset logic
        if (lastUpdated != null &&
            DateTime.now().difference(lastUpdated.toDate()).inHours >= 24) {
          currentRevenue = double.tryParse(_paidAmountController.text) ?? 0.0;
          totalSales = 1; // Reset to 1 for the current bill
        } else {
          currentRevenue += double.tryParse(_paidAmountController.text) ?? 0.0;
          totalSales += 1; // Increment sales count
        }

        transaction.set(dailyMetricsRef, {
          'dailyRevenue': currentRevenue,
          'totalSales': totalSales,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      });

      // Add recent activity
      final recentActivitiesRef = FirebaseFirestore.instance
          .collection('Revenue')
          .doc(user.uid)
          .collection('recent_activities');

      await recentActivitiesRef.add({
        'type': 'Bill Generated',
        'title': 'Bill Generated',
        'subtitle':
            '''Customer: ${_customerNameController.text.isEmpty ? 'N/A' : _customerNameController.text}
Total: Rs ${_grandTotal.toStringAsFixed(2)}''',
        'billId': billData['billId'],
        'amount': _grandTotal,
        'time': FieldValue.serverTimestamp(),
        'color': Colors.purple.value,
      });

      print('DEBUG: Customer Name for PDF: ${_customerNameController.text}');
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Text('Bill Receipt',
                      style: pw.TextStyle(fontSize: 24)),
                ),
                pw.SizedBox(height: 10),
                pw.Text('Bill ID: ${billData['billId']}',
                    style: pw.TextStyle(fontSize: 12)),
                pw.Text(
                    'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                    style: pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 20),
                pw.Text('Customer: ${_customerNameController.text}'),
                pw.SizedBox(height: 20),
                pw.Table.fromTextArray(
                  headers: [
                    'Product',
                    'Qty',
                    'Sub Qty',
                    'Price',
                    'Disc. Price',
                    'Line Total'
                  ],
                  data: _selectedProducts
                      .map((product) => [
                            product.name,
                            product.quantity.toString(),
                            product.subQuantity.toString(),
                            product.price.toStringAsFixed(2),
                            product.discountPrice.toStringAsFixed(2),
                            (product.quantity * product.discountPrice)
                                .toStringAsFixed(2),
                          ])
                      .toList(),
                ),
                pw.SizedBox(height: 20),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Sub Total: Rs ${_subTotal.toStringAsFixed(2)}'),
                    if (_isGSTEnabled)
                      pw.Text(
                          'GST (${_gstController.text}%): Rs ${_gstAmount.toStringAsFixed(2)}'),
                    pw.Divider(),
                    pw.Text('Grand Total: Rs ${_grandTotal.toStringAsFixed(2)}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 10),
                    pw.Text('Paid Amount: Rs ${_paidAmountController.text}'),
                    pw.Text('Due Amount: Rs ${_dueAmount.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          color:
                              _dueAmount > 0 ? PdfColors.red : PdfColors.green,
                          fontWeight: pw.FontWeight.bold,
                        )),
                    pw.SizedBox(height: 10),
                    pw.Text(
                        'Payment Status: ${_dueAmount <= 0 ? 'PAID' : 'PARTIAL PAYMENT'}',
                        style: pw.TextStyle(
                          color: _dueAmount <= 0
                              ? PdfColors.green
                              : PdfColors.orange,
                          fontWeight: pw.FontWeight.bold,
                        )),
                  ],
                ),
                pw.SizedBox(height: 30),
                pw.Center(
                  child: pw.Text('Thank you for your business!',
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                ),
              ],
            );
          },
        ),
      );

      // Sanitize customer name for file name
      String customerName = _customerNameController.text
          .trim()
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      if (customerName.isEmpty) customerName = 'Customer';
      final String defaultFileName =
          'Bill_${customerName}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final pdfBytes = await pdf.save();

      if (kIsWeb) {
        // Web: Use dart:html to download
        final blob = platform.Blob([
          pdfBytes.buffer
              .asUint8List(pdfBytes.offsetInBytes, pdfBytes.lengthInBytes)
        ], 'application/pdf');
        final url = platform.Url.createObjectUrlFromBlob(blob);
        final anchor = platform.AnchorElement(href: url)
          ..setAttribute('download', defaultFileName)
          ..setAttribute('type', 'application/pdf')
          ..click();
        platform.Url.revokeObjectUrl(url);
        _showToast('Bill saved successfully!');
        await _completeOrderAndCleanup();
        return;
      }

      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // Desktop: Use FilePicker
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Please select an output file:',
          fileName: defaultFileName,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (outputFile == null) {
          _showToast('Save cancelled.');
          return;
        }
        final file = File(outputFile);
        await file.writeAsBytes(pdfBytes, flush: true);
        _showToast('Bill saved successfully!');
        await _completeOrderAndCleanup();
        await Share.shareXFiles([XFile(outputFile)], text: 'Bill Receipt');
        return;
      }

      // Mobile: Use path_provider
      final directory = await getApplicationDocumentsDirectory();
      final String filePath = '${directory.path}/$defaultFileName';
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes, flush: true);
      _showToast('Bill saved successfully!');
      await _completeOrderAndCleanup();
      await Share.shareXFiles([XFile(filePath)], text: 'Bill Receipt');
    } catch (e) {
      print('Error generating PDF and saving bill: $e');
      _showToast('Error saving bill: $e', backgroundColor: Colors.red);
    }
  }

  Future<void> _completeOrderAndCleanup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.userId == null || widget.orderId == null) {
      print(
          'Cannot complete order: User not logged in or order details missing.');
      return;
    }

    try {
      // 1. Update Inventory for each product in the bill
      for (var productInBill in _selectedProducts) {
        try {
          final searchName = productInBill.name.trim(); // Remove .toLowerCase()
          print('Updating inventory for: $searchName');
          final querySnapshot = await FirebaseFirestore.instance
              .collection('medicines')
              .doc(user.uid)
              .collection('user_medicines')
              .where('name', isEqualTo: searchName)
              .get();

          if (querySnapshot.docs.isNotEmpty) {
            final doc = querySnapshot.docs.first;
            final currentStock =
                (doc.data() as Map<String, dynamic>)['quantity'] ?? 0;
            final newStock = currentStock - productInBill.quantity;

            if (newStock >= 0) {
              await doc.reference.update({'quantity': newStock});
              print('Inventory updated for $searchName. New stock: $newStock');
            } else {
              print(
                  'Not enough stock for $searchName. Current: $currentStock, Ordered: ${productInBill.quantity}');
              _showToast('Not enough stock for $searchName.',
                  backgroundColor: Colors.red);
            }
          } else {
            print('Medicine $searchName not found in inventory.');
            _showToast('Medicine $searchName not found in inventory.',
                backgroundColor: Colors.red);
          }
        } catch (e) {
          print('Error updating inventory for ${productInBill.name}: $e');
          _showToast('Error updating inventory for ${productInBill.name}: $e',
              backgroundColor: Colors.red);
        }
      }

      // 2. Delete the order document
      await FirebaseFirestore.instance
          .collection('medicines order')
          .doc(widget.userId!)
          .collection('Orders')
          .doc(widget.orderId!)
          .delete();
      print('Order ${widget.orderId} deleted successfully from active orders.');

      // 3. Update total deliveries
      final totalDeliveriesRef = FirebaseFirestore.instance
          .collection(
              'Pharmacy Driver') // Assuming this is where total deliveries might be stored, or create a new collection
          .doc(user.uid)
          .collection('metrics') // Create a subcollection for metrics
          .doc('delivery_summary');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(totalDeliveriesRef);
        int currentTotalDeliveries = 0;

        if (snapshot.exists) {
          currentTotalDeliveries =
              (snapshot.data()?['totalDeliveries'] as int?) ?? 0;
        }

        transaction.set(totalDeliveriesRef, {
          'totalDeliveries': currentTotalDeliveries + 1,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      });
      print('Total deliveries incremented.');

      // You might want to navigate back to the OrderScreen or show a success message
      if (mounted) {
        // After completing the order, it's a good idea to clear the billing tab
        // or navigate back to a fresh state in the OrderScreen.
        // For now, let's clear the current billing tab
        _selectedProducts.clear();
        _clearInputFields();
        _customerNameController.clear();
        _billProducts[_activeTabIndex] = [];
        _showToast('Order completed and details updated!');

        // If you want to automatically switch back to the Order screen, you'd need a callback
        // from MediCheckDashboard to signal this. For now, just a toast.
      }
    } catch (e) {
      print('Error during order completion and cleanup: $e');
      if (mounted) {
        _showToast('Error completing order: $e', backgroundColor: Colors.red);
      }
    }
  }

  Future<bool> _updateMedicineStockInFirebase(
      Product product, int quantitySold) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      print('User not logged in. Cannot update medicine stock.');
      _showToast('User not logged in. Please log in to update stock.');
      return false;
    }

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('medicines')
          .doc(user.uid)
          .collection('user_medicines')
          .where('name', isEqualTo: product.name.trim().toLowerCase())
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final currentStock =
            (doc.data() as Map<String, dynamic>)['quantity'] ?? 0;
        final newStock = currentStock - quantitySold;

        if (newStock >= 0) {
          await doc.reference.update({'quantity': newStock});
          print(
              'Stock updated successfully for ${product.name}. New stock: $newStock');
          _showToast('${product.name} added to bill. Stock updated.');
          return true;
        } else {
          final message =
              'Cannot add ${product.name} - Not enough stock. Available: $currentStock';
          print(message);
          _showToast(message,
              backgroundColor: Colors.red, textColor: Colors.white);
          return false;
        }
      } else {
        final message = 'Medicine ${product.name} not found in database.';
        print(message);
        _showToast(message);
        return false;
      }
    } catch (e) {
      final message = 'Error updating stock: $e';
      print(message);
      _showToast(message);
      return false;
    }
  }
}

class Product {
  final String name;
  final int quantity;
  final int subQuantity;
  final double price;
  final double discountPrice;
  final double discount;

  Product({
    required this.name,
    required this.quantity,
    required this.subQuantity,
    required this.price,
    required this.discountPrice,
    required this.discount,
  });

  // Method to process discount, assuming 'discount' is an absolute value or percentage
  // For now, it returns the stored discount value.
  double processDiscount() {
    // Implement actual discount calculation if 'discount' is a percentage
    // For example, if discount is 5 for 5%:
    // return (price * discount / 100);
    return discount;
  }

  factory Product.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Product(
      name: (data['name'] ?? '').toString().trim().toLowerCase(),
      quantity: data['quantity'] ?? 0,
      price: (data['price'] ?? 0.0).toDouble(),
      discountPrice: (data['discountPrice'] ?? 0.0).toDouble(),
      discount: (data['discount'] ?? 0.0).toDouble(),
      subQuantity: data['subQuantity'] ?? 0,
    );
  }
}
