import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'login_page.dart';
import 'map_picker_screen.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isLocationLoading = false;
  String _errorMessage = '';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Controller for branch address field
  final TextEditingController _branchAddressController =
      TextEditingController();

  Map<String, String> _errors = {};
  Map<String, dynamic> _formData = {
    'fullName': '',
    'email': '',
    'phone': '',
    'password': '',
    'role': 'Staff',
    'branchName': '',
    'branchAddress': '',
    'openingTime': '',
    'closingTime': '',
    'deliveryStatus': false,
    'termsAccepted': false,
  };

  TimeOfDay? _openingTime;
  TimeOfDay? _closingTime;

  @override
  void initState() {
    super.initState();
    _branchAddressController.text = _formData['branchAddress'];
  }

  @override
  void dispose() {
    _branchAddressController.dispose();
    super.dispose();
  }

  void _handleInputChange(String field, dynamic value) {
    setState(() {
      _formData[field] = value;
      if (field == 'branchAddress') {
        _branchAddressController.text = value;
      }
      if (_errors.containsKey(field)) {
        _errors.remove(field);
      }
    });
  }

  // Function to check location permissions
  Future<bool> _handleLocationPermission() async {
    print('Checking if location services are enabled...');
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services are disabled.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Location services are disabled. Please enable the services'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    print('Checking location permission...');
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      print('Permission denied, requesting permission...');
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Permission denied again.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are denied'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('Permission denied forever.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Location permissions are permanently denied, we cannot request permissions.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    print('Location permission granted.');
    return true;
  }

  // Function to get current location and convert to address
  Future<void> _getCurrentLocationWithTimeout() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    setState(() {
      _isLocationLoading = true;
    });

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      if (kIsWeb) {
        // On web, placemarkFromCoordinates is not supported.
        // You can use a web API here, or just show the lat/lng.
        String address = '${position.latitude}, ${position.longitude}';
        _handleInputChange('branchAddress', address);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location obtained: $address'),
            backgroundColor: Colors.green,
          ),
        );
        print('Reported accuracy: ${position.accuracy} meters');
        return;
      }

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        String address = _buildAddressString(place);

        // Store coordinates
        _formData['latitude'] = position.latitude;
        _formData['longitude'] = position.longitude;

        _handleInputChange('branchAddress', address);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Location obtained: ${address.length > 50 ? address.substring(0, 50) + '...' : address}'),
            backgroundColor: Colors.green,
          ),
        );
        print('Reported accuracy: ${position.accuracy} meters');
      } else {
        _showLocationError('No address information found for this location');
      }
    } on TimeoutException {
      _showLocationError('Location request timed out. Please try again.');
    } on LocationServiceDisabledException {
      _showLocationError('Location services are disabled. Please enable them.');
    } on PermissionDeniedException {
      _showLocationError('Location permission denied.');
    } on PlatformException catch (e) {
      if (e.code == 'ERROR_GEOCODING_ADDRESSNOTFOUND') {
        _showLocationError('Could not find address for coordinates');
      } else {
        _showLocationError('Geocoding error: \'${e.message}\'');
      }
    } catch (e) {
      _showLocationError('Failed to get location: ${e.toString()}');
    } finally {
      setState(() {
        _isLocationLoading = false;
      });
    }
  }

  // Helper method to build address string (fully null-safe)
  String _buildAddressString(Placemark place) {
    List<String> addressParts = [];

    void addPart(String? part) {
      if (part != null && part.trim().isNotEmpty) {
        addressParts.add(part.trim());
      }
    }

    addPart(place.street);
    addPart(place.subLocality);
    addPart(place.locality);
    addPart(place.administrativeArea);
    addPart(place.postalCode);
    addPart(place.country);

    return addressParts.isNotEmpty
        ? addressParts.join(', ')
        : 'Unknown Location';
  }

  // Helper method for error handling
  void _showLocationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Retry',
          onPressed: _getCurrentLocationWithTimeout,
        ),
      ),
    );
  }

  // Alternative: Get location with lower accuracy for faster results
  Future<void> _getQuickLocation() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    setState(() {
      _isLocationLoading = true;
    });

    try {
      // Use lower accuracy for faster results
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 5),
      );

      // Simple address format for quick location
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String quickAddress =
            '\\${place.locality ?? ''}, \\${place.administrativeArea ?? ''}, \\${place.country ?? ''}';

        _handleInputChange('branchAddress', quickAddress);

        // Show option to get more precise location
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quick location obtained. Get precise location?'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'Precise',
              textColor: Colors.white,
              onPressed: _getCurrentLocationWithTimeout,
            ),
          ),
        );
      }
    } catch (e) {
      _showLocationError('Quick location failed: \\${e.toString()}');
    } finally {
      setState(() {
        _isLocationLoading = false;
      });
    }
  }

  // Location settings check and redirect
  Future<void> _checkLocationSettings() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      // Show dialog to open location settings
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Location Services Disabled'),
            content: Text(
                'Please enable location services to use GPS functionality.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Geolocator.openLocationSettings();
                },
                child: Text('Settings'),
              ),
            ],
          );
        },
      );
    }
  }

  bool _validateForm() {
    final newErrors = <String, String>{};

    if (_formData['fullName']!.trim().isEmpty) {
      newErrors['fullName'] = 'Please enter your full name';
    }

    if (_formData['email']!.trim().isEmpty) {
      newErrors['email'] = 'Please enter your email';
    } else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
        .hasMatch(_formData['email'])) {
      newErrors['email'] = 'Please enter a valid email';
    }

    if (_formData['phone']!.trim().isEmpty) {
      newErrors['phone'] = 'Please enter your phone number';
    } else if (!RegExp(r'^[0-9]+$').hasMatch(_formData['phone'])) {
      newErrors['phone'] = 'Please enter a valid phone number';
    }

    if (_formData['password']!.trim().isEmpty) {
      newErrors['password'] = 'Please enter a password';
    } else if (_formData['password']!.length < 6) {
      newErrors['password'] = 'Password must be at least 6 characters';
    }

    if (_formData['branchName']!.trim().isEmpty) {
      newErrors['branchName'] = 'Please enter branch name';
    }

    if (_formData['branchAddress']!.trim().isEmpty) {
      newErrors['branchAddress'] = 'Please enter branch address';
    }

    if (_formData['openingTime']!.isEmpty) {
      newErrors['openingTime'] = 'Please select opening time';
    }

    if (_formData['closingTime']!.isEmpty) {
      newErrors['closingTime'] = 'Please select closing time';
    }

    setState(() {
      _errors = newErrors;
    });

    return newErrors.isEmpty;
  }

  Future<void> _handleSubmit() async {
    if (!_validateForm()) return;

    if (!_formData['termsAccepted']) {
      setState(() {
        _errorMessage = 'Please accept the Terms of Service and Privacy Policy';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: _formData['email'],
        password: _formData['password'],
      );

      if (userCredential.user != null) {
        // Store additional user data in Firestore
        final String userUid = userCredential.user!.uid;
        await _firestore.collection('Users').doc(userUid).set({
          'fullName': _formData['fullName'],
          'email': _formData['email'],
          'phone': _formData['phone'],
          'role': _formData['role'],
          'branchName': _formData['branchName'],
          'branchAddress': _formData['branchAddress'],
          'openingTime': _formData['openingTime'],
          'closingTime': _formData['closingTime'],
          'deliveryStatus': _formData['deliveryStatus'],
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Send email verification
        await userCredential.user!.sendEmailVerification();

        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Verify Your Email'),
            content: const Text(
                'A verification link has been sent to your email address.\n\nPlease verify your email before signing in.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                  );
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred during registration';

      if (e.code == 'weak-password') {
        message = 'The password provided is too weak';
      } else if (e.code == 'email-already-in-use') {
        message = 'An account already exists for that email';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is not valid';
      } else if (e.code == 'operation-not-allowed') {
        message =
            'Email/password accounts are not enabled. Enable it in the Firebase console.';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An unexpected error occurred'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectTime(BuildContext context, bool isOpeningTime) async {
    final initialTime = isOpeningTime
        ? _openingTime ?? TimeOfDay.now()
        : _closingTime ?? TimeOfDay.now();

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (pickedTime != null) {
      _handleInputChange(isOpeningTime ? 'openingTime' : 'closingTime',
          pickedTime.format(context));
      setState(() {
        if (isOpeningTime) {
          _openingTime = pickedTime;
        } else {
          _closingTime = pickedTime;
        }
      });
    }
  }

  Widget _featureItem(String text, {bool compact = false}) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(compact ? 4 : 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child:
              Icon(Icons.check, color: Colors.white, size: compact ? 12 : 16),
        ),
        SizedBox(width: compact ? 8 : 12),
        Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 14 : 16,
          ),
        ),
      ],
    );
  }

  Widget _formField({
    required String label,
    required IconData icon,
    required String field,
    String? placeholder,
    String? errorText,
    bool isPassword = false,
    bool isDropdown = false,
    List<String>? options,
    Widget? additionalButton,
    TextInputType? keyboardType,
    TextEditingController? controller,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: isDropdown
                  ? DropdownButtonFormField<String>(
                      value: _formData[field],
                      decoration: InputDecoration(
                        prefixIcon:
                            Icon(icon, size: 20, color: Colors.grey[600]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      items: options!
                          .map((option) => DropdownMenuItem(
                                value: option,
                                child: Text(option),
                              ))
                          .toList(),
                      onChanged: (value) => _handleInputChange(field, value),
                      validator: (value) => _errors[field],
                    )
                  : TextFormField(
                      controller: controller,
                      obscureText: isPassword,
                      keyboardType: keyboardType,
                      readOnly: readOnly,
                      onTap: onTap,
                      decoration: InputDecoration(
                        prefixIcon:
                            Icon(icon, size: 20, color: Colors.grey[600]),
                        hintText: placeholder,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        suffixIcon:
                            field == 'branchAddress' && additionalButton != null
                                ? additionalButton
                                : null,
                      ),
                      onChanged: (value) => _handleInputChange(field, value),
                      validator: (value) => _errors[field],
                    ),
            ),
            if (additionalButton != null && field != 'branchAddress')
              Positioned(
                right: 8,
                top: 8,
                child: additionalButton,
              ),
          ],
        ),
        if (_errors.containsKey(field))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _errors[field]!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _desktopLayout() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(40),
            color: const Color(0xFF173E7C),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome to Medicheck',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Create your account and start managing your business efficiently',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 40),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _featureItem('Manage multiple branches effortlessly'),
                    const SizedBox(height: 20),
                    _featureItem('Real-time business analytics'),
                    const SizedBox(height: 20),
                    _featureItem('Secure data management'),
                    const SizedBox(height: 20),
                    _featureItem('Dedicated support team'),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: _formContent(),
        ),
      ],
    );
  }

  Widget _mobileLayout() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          color: const Color(0xFF173E7C),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome to Medicheck',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Create your account and start managing your business efficiently',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _featureItem('Manage multiple branches', compact: true),
                  _featureItem('Real-time analytics', compact: true),
                  _featureItem('Secure data', compact: true),
                  _featureItem('Dedicated support', compact: true),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: _formContent()),
      ],
    );
  }

  Widget _formContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Create New Account',
                      style: TextStyle(
                        color: Color(0xFF333333),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Fill in the details to register your account',
                      style: TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.language,
                      size: 18, color: Color(0xFF666666)),
                  label: const Text(
                    'English',
                    style: TextStyle(fontSize: 16, color: Color(0xFF666666)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Error Message
            if (_errorMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  border: Border.all(color: Colors.red[200]!),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                  ],
                ),
              ),
            if (_errorMessage.isNotEmpty) const SizedBox(height: 24),

            // Personal Information
            const Text(
              'Personal Information',
              style: TextStyle(
                color: Color(0xFF333333),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _formField(
                    label: 'Full Name',
                    icon: Icons.person_outline,
                    placeholder: 'Enter your full name',
                    field: 'fullName',
                    keyboardType: TextInputType.name,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _formField(
                    label: 'Role',
                    icon: Icons.work_outline,
                    placeholder: 'Select your role',
                    field: 'role',
                    isDropdown: true,
                    options: const ['Admin', 'Staff'],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Contact Details
            const Text(
              'Contact Details',
              style: TextStyle(
                color: Color(0xFF333333),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _formField(
                    label: 'Email Address',
                    icon: Icons.email_outlined,
                    placeholder: 'Enter your email',
                    field: 'email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _formField(
                    label: 'Phone Number',
                    icon: Icons.phone_outlined,
                    placeholder: 'Enter your phone number',
                    field: 'phone',
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Security
            const Text(
              'Security',
              style: TextStyle(
                color: Color(0xFF333333),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _formField(
              label: 'Password',
              icon: Icons.lock_outline,
              placeholder: 'Enter a strong password',
              field: 'password',
              isPassword: true,
            ),
            const SizedBox(height: 24),

            // Branch Information
            const Text(
              'Branch Information',
              style: TextStyle(
                color: Color(0xFF333333),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Delivery Status
            Row(
              children: [
                const Text(
                  'Delivery Status',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () {
                    _handleInputChange(
                        'deliveryStatus', !_formData['deliveryStatus']);
                  },
                  child: Container(
                    width: 48,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: _formData['deliveryStatus']
                          ? const Color(0xFF2C3E66)
                          : Colors.grey[300],
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: _formData['deliveryStatus']
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formData['deliveryStatus'] ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _formData['deliveryStatus']
                        ? const Color(0xFF2C3E66)
                        : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Timing
            Row(
              children: [
                Expanded(
                  child: _formField(
                    label: 'Opening Time',
                    icon: Icons.access_time_outlined,
                    placeholder: 'Select opening time',
                    field: 'openingTime',
                    readOnly: true,
                    onTap: () => _selectTime(context, true),
                    controller: TextEditingController(
                        text: _openingTime != null
                            ? _openingTime!.format(context)
                            : ''),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _formField(
                    label: 'Closing Time',
                    icon: Icons.access_time_outlined,
                    placeholder: 'Select closing time',
                    field: 'closingTime',
                    readOnly: true,
                    onTap: () => _selectTime(context, false),
                    controller: TextEditingController(
                        text: _closingTime != null
                            ? _closingTime!.format(context)
                            : ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Branch Details
            _formField(
              label: 'Branch Name',
              icon: Icons.business_outlined,
              placeholder: 'Enter branch name',
              field: 'branchName',
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 16),
            _formField(
              label: 'Branch Address',
              icon: Icons.location_on_outlined,
              placeholder: 'Tap to get current location or enter manually',
              field: 'branchAddress',
              keyboardType: TextInputType.streetAddress,
              controller: _branchAddressController,
              onTap:
                  _getCurrentLocationWithTimeout, // Get location when field is tapped
              additionalButton: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLocationLoading)
                    const Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF666666),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.my_location,
                        size: 20, color: Color(0xFF666666)),
                    onPressed: _isLocationLoading
                        ? null
                        : _getCurrentLocationWithTimeout,
                    tooltip: 'Get current location',
                  ),
                  IconButton(
                    icon: const Icon(Icons.map,
                        size: 20, color: Color(0xFF666666)),
                    onPressed: () async {
                      final selectedAddress = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => MapPickerScreen()),
                      );
                      if (selectedAddress != null) {
                        _handleInputChange('branchAddress', selectedAddress);
                      }
                    },
                    tooltip: 'Select from map',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Terms and Submit
            Row(
              children: [
                Checkbox(
                  value: _formData['termsAccepted'],
                  onChanged: (value) =>
                      _handleInputChange('termsAccepted', value),
                  activeColor: const Color(0xFF2C3E66),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleInputChange(
                        'termsAccepted', !_formData['termsAccepted']),
                    child: const Text(
                      'I agree to the Terms of Service and Privacy Policy',
                      style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
                    ),
                  ),
                ),
              ],
            ),
            if (_errors.containsKey('termsAccepted'))
              Padding(
                padding: const EdgeInsets.only(left: 48.0, top: 4),
                child: Text(
                  _errors['termsAccepted']!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2C3E66),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Create Account',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                  );
                },
                child: const Text(
                  'Already have an account? Sign In',
                  style: TextStyle(
                    color: Color(0xFF173E7C),
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 768) {
            return _desktopLayout();
          } else {
            return _mobileLayout();
          }
        },
      ),
    );
  }
}
