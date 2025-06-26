import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_page.dart';

class SettingsScreen extends StatefulWidget {
  final String fullName;
  final String email;

  const SettingsScreen({Key? key, required this.fullName, required this.email})
      : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _pharmacyNameController;
  late TextEditingController _pharmacyAddressController;
  late TextEditingController _currentPasswordController;
  late TextEditingController _newPasswordController;
  late TextEditingController _confirmPasswordController;
  bool _deliveryStatus = true;
  TimeOfDay _openingTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _closingTime = const TimeOfDay(hour: 17, minute: 0);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _pharmacyNameController = TextEditingController();
    _pharmacyAddressController = TextEditingController();
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _fetchUserInfo();
  }

  Future<void> _fetchUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();
      final data = userDoc.data() ?? {};
      setState(() {
        _nameController.text = data['fullName'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _pharmacyNameController.text = data['branchName'] ?? '';
        _pharmacyAddressController.text = data['branchAddress'] ?? '';
        _deliveryStatus = data['deliveryStatus'] ?? false;
        _openingTime = _parseTimeOfDay(data['openingTime']) ??
            const TimeOfDay(hour: 9, minute: 0);
        _closingTime = _parseTimeOfDay(data['closingTime']) ??
            const TimeOfDay(hour: 17, minute: 0);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching user info: $e')),
      );
    }
  }

  TimeOfDay? _parseTimeOfDay(dynamic value) {
    if (value is String && value.contains(':')) {
      final parts = value.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts[1]) ?? 0;
        return TimeOfDay(hour: hour, minute: minute);
      }
    }
    return null;
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final currentPassword = _currentPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (currentPassword.isEmpty ||
        newPassword.isEmpty ||
        confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all password fields.')),
      );
      return;
    }
    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match.')),
      );
      return;
    }
    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Password must be at least 6 characters.')),
      );
      return;
    }
    try {
      // Re-authenticate
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(cred);
      // Update password
      await user.updatePassword(newPassword);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully.')),
      );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error changing password: $e')),
      );
    }
  }

  Future<void> _saveUserInfo() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
        'fullName': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'branchName': _pharmacyNameController.text.trim(),
        'branchAddress': _pharmacyAddressController.text.trim(),
        'deliveryStatus': _deliveryStatus,
        'openingTime': _openingTime.format(context),
        'closingTime': _closingTime.format(context),
      }, SetOptions(merge: true));
      // Change password if fields are filled
      if (_currentPasswordController.text.isNotEmpty ||
          _newPasswordController.text.isNotEmpty ||
          _confirmPasswordController.text.isNotEmpty) {
        await _changePassword();
      }
      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    } catch (e) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating profile: $e')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _pharmacyNameController.dispose();
    _pharmacyAddressController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _selectTime(bool isOpening) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpening ? _openingTime : _closingTime,
    );
    if (picked != null) {
      setState(() {
        if (isOpening) {
          _openingTime = picked;
        } else {
          _closingTime = picked;
        }
      });
    }
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
            'Are you sure you want to delete your account? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _deleteAccount();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user is currently signed in.')),
      );
      return;
    }
    try {
      // Delete all orders in 'medicines order' where pharmacyId matches current user
      final medicinesOrderCollection =
          FirebaseFirestore.instance.collection('medicines order');
      final medicinesOrderSnapshot = await medicinesOrderCollection.get();
      for (final userDoc in medicinesOrderSnapshot.docs) {
        final ordersQuery = await medicinesOrderCollection
            .doc(userDoc.id)
            .collection('Orders')
            .where('pharmacyId', isEqualTo: user.uid)
            .get();
        for (final orderDoc in ordersQuery.docs) {
          await orderDoc.reference.delete();
        }
      }
      // Delete all medicine documents for this user
      final medicinesCollection = FirebaseFirestore.instance
          .collection('medicines')
          .doc(user.uid)
          .collection('user_medicines');
      final medicinesSnapshot = await medicinesCollection.get();
      for (final doc in medicinesSnapshot.docs) {
        await doc.reference.delete();
      }
      // Delete the parent medicines user document (optional, if you want to clean up)
      await FirebaseFirestore.instance
          .collection('medicines')
          .doc(user.uid)
          .delete();
      // Delete user document from Firestore
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .delete();
      // Delete user from Firebase Auth
      await user.delete();
      setState(() => _isSaving = false);
      if (!mounted) return;
      // Navigate to LoginScreen and remove all previous routes
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted successfully.')),
      );
    } catch (e) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting account: $e')),
      );
    }
  }

  Future<void> _reauthenticateAndDelete(String password) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);
      await user.delete();
      // ... (navigate to login, show success, etc.)
    } catch (e) {
      // Show error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: const Color(0xFF2A3467),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              onPressed:
                  _isLoading ? null : () => setState(() => _isEditing = true),
            ),
          if (_isEditing)
            IconButton(
              icon: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.save, color: Colors.white),
              onPressed: _isSaving ? null : _saveUserInfo,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              color: const Color(0xFFEAEAEA),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: Container(
                      width: 700,
                      padding: const EdgeInsets.all(32.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
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
                            'Profile Information',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2A3467),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _nameController,
                                  enabled: _isEditing,
                                  decoration: const InputDecoration(
                                    labelText: 'Full Name',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Required'
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _phoneController,
                                  enabled: _isEditing,
                                  decoration: const InputDecoration(
                                    labelText: 'Phone Number',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Required'
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _pharmacyNameController,
                                  enabled: _isEditing,
                                  decoration: const InputDecoration(
                                    labelText: 'Pharmacy Name',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Required'
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _pharmacyAddressController,
                                  enabled: _isEditing,
                                  decoration: const InputDecoration(
                                    labelText: 'Pharmacy Address',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Required'
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Delivery Status',
                                  style: TextStyle(fontSize: 16),
                                ),
                                Row(
                                  children: [
                                    Switch(
                                      value: _deliveryStatus,
                                      onChanged: _isEditing
                                          ? (value) => setState(
                                              () => _deliveryStatus = value)
                                          : null,
                                      activeColor: const Color(0xFF2A3467),
                                      activeTrackColor: const Color(0xFF2A3467)
                                          .withOpacity(0.5),
                                      inactiveThumbColor: Colors.grey[400],
                                      inactiveTrackColor: Colors.grey[300],
                                    ),
                                    Text(
                                      _deliveryStatus ? 'ON' : 'OFF',
                                      style: TextStyle(
                                        color: _deliveryStatus
                                            ? const Color(0xFF2A3467)
                                            : Colors.grey[600],
                                        fontWeight: _deliveryStatus
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Business Hours',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: _isEditing
                                            ? () => _selectTime(true)
                                            : null,
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Colors.grey[300]!),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.access_time,
                                                  size: 20),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Opening Time',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Text(
                                                _openingTime.format(context),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: InkWell(
                                        onTap: _isEditing
                                            ? () => _selectTime(false)
                                            : null,
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Colors.grey[300]!),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.access_time,
                                                  size: 20),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Closing Time',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Text(
                                                _closingTime.format(context),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          const Divider(),
                          const SizedBox(height: 24),
                          const Text(
                            'Change Password',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2A3467),
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _currentPasswordController,
                            enabled: _isEditing,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Current Password',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _newPasswordController,
                            enabled: _isEditing,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'New Password',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (_isEditing &&
                                  (_newPasswordController.text.isNotEmpty ||
                                      _confirmPasswordController
                                          .text.isNotEmpty)) {
                                if (v == null || v.isEmpty) return 'Required';
                                if (v.length < 6) return 'Min 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmPasswordController,
                            enabled: _isEditing,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Confirm New Password',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (_isEditing &&
                                  (_newPasswordController.text.isNotEmpty ||
                                      _confirmPasswordController
                                          .text.isNotEmpty)) {
                                if (v == null || v.isEmpty) return 'Required';
                                if (v != _newPasswordController.text)
                                  return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 32),
                          Center(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32, vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.delete_forever),
                              label: const Text('Delete Account'),
                              onPressed: _isLoading || _isSaving
                                  ? null
                                  : _showDeleteAccountDialog,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
