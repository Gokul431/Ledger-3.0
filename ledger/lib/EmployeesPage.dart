import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class ShopsPage extends StatefulWidget {
  const ShopsPage({super.key});

  @override
  State<ShopsPage> createState() => _ShopsPageState();
}

class _ShopsPageState extends State<ShopsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _shops = [];

  @override
  void initState() {
    super.initState();
    _fetchShops();
  }

  Future<void> _fetchShops() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('shop_list')
          .get();

      List<Map<String, dynamic>> shopsList = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        shopsList.add({
          'docId': doc.id,
          'collectionName': data['collectionName'] ?? '',
          'shopName': data['shopName'] ?? 'Unknown Shop',
          'location': data['location'] ?? 'N/A',
          'phone': data['phone'] ?? 'N/A',
          'employeeUsername': data['username'] ?? 'N/A',
          'createdAt': data['createdAt'],
          'status': data['status'] ?? 'active',
        });
      }

      setState(() {
        _shops = shopsList;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching shops: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteShop(
    String docId,
    String collectionName,
    String shopName,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('shop_list')
          .doc(docId)
          .delete();

      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc('Credentials')
          .delete();

      _showSnackBar('Shop deleted successfully');
      _fetchShops();
    } catch (e) {
      debugPrint('Error deleting shop: $e');
      _showSnackBar('Error deleting shop: $e', isError: true);
    }
  }

  Widget _buildShopItem(Map<String, dynamic> shop) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.store,
                    color: Color(0xFF4285F4),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop['shopName'],
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            shop['location'],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.phone, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            shop['phone'],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4285F4).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'User: ${shop['employeeUsername']}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4285F4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Color(0xFF4285F4),
                    size: 20,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditShopPage(
                          shopData: shop,
                          onShopUpdated: _fetchShops,
                        ),
                      ),
                    );
                  },
                  splashRadius: 24,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[50]!,
      period: const Duration(milliseconds: 1200),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: 6,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 120, height: 14, color: Colors.white),
                      const SizedBox(height: 8),
                      Container(width: 180, height: 12, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: const Text(
          'Shops',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 26),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      CreateShopPage(onShopCreated: _fetchShops),
                ),
              );
            },
            tooltip: 'Add Shop',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? _buildShimmerLoading()
          : _shops.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.store_mall_directory,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No shops yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first shop to get started',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : Container(
              color: Colors.white,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _shops.length,
                itemBuilder: (context, index) {
                  return _buildShopItem(_shops[index]);
                },
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// CREATE SHOP PAGE
// ─────────────────────────────────────────────────────────────────────

class CreateShopPage extends StatefulWidget {
  final VoidCallback onShopCreated;

  const CreateShopPage({super.key, required this.onShopCreated});

  @override
  State<CreateShopPage> createState() => _CreateShopPageState();
}

class _CreateShopPageState extends State<CreateShopPage> {
  final shopNameController = TextEditingController();
  final shopLocationController = TextEditingController();
  final shopPhoneController = TextEditingController();
  final empUsernameController = TextEditingController();
  final empPasswordController = TextEditingController();
  final empConfirmPasswordController = TextEditingController();
  bool _isLoading = false;

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  Future<void> _createShop() async {
    final shopName = shopNameController.text.trim();
    final location = shopLocationController.text.trim();
    final phone = shopPhoneController.text.trim();
    final empUsername = empUsernameController.text.trim();
    final empPassword = empPasswordController.text.trim();
    final empConfirmPassword = empConfirmPasswordController.text.trim();

    if (shopName.isEmpty) {
      _showSnackBar('Please enter shop name', isError: true);
      return;
    }
    if (phone.isEmpty || phone.length != 10) {
      _showSnackBar('Please enter valid 10-digit phone', isError: true);
      return;
    }
    if (empUsername.isEmpty) {
      _showSnackBar('Please enter username', isError: true);
      return;
    }
    if (empPassword.isEmpty || empPassword.length < 6) {
      _showSnackBar('Password must be at least 6 characters', isError: true);
      return;
    }
    if (empPassword != empConfirmPassword) {
      _showSnackBar('Passwords do not match', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      String collectionName = shopName.replaceAll(' ', '_').toLowerCase();

      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc('Credentials')
          .set({
            'shopName': shopName,
            'location': location.isEmpty ? 'N/A' : location,
            'phone': phone,
            'username': empUsername,
            'password': _hashPassword(empPassword),
            'createdAt': Timestamp.now(),
            'status': 'active',
          });

      await FirebaseFirestore.instance.collection('shop_list').add({
        'collectionName': collectionName,
        'shopName': shopName,
        'location': location.isEmpty ? 'N/A' : location,
        'phone': phone,
        'username': empUsername,
        'createdAt': Timestamp.now(),
        'status': 'active',
      });

      _showSnackBar('Shop "$shopName" created successfully');
      widget.onShopCreated();
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Error creating shop: $e');
      _showSnackBar('Error creating shop: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    shopNameController.dispose();
    shopLocationController.dispose();
    shopPhoneController.dispose();
    empUsernameController.dispose();
    empPasswordController.dispose();
    empConfirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: const Text('Create Shop'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF4285F4), Color(0xFF2E7FE8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.store_mall_directory,
                        color: Colors.white,
                        size: 40,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Add New Shop',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Create a new shop and set employee credentials',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                // Form
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Shop Details', Icons.store),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: shopNameController,
                        label: 'Shop Name',
                        hint: 'Enter shop name',
                        icon: Icons.store,
                        isRequired: true,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: shopLocationController,
                        label: 'Location',
                        hint: 'Enter location',
                        icon: Icons.location_on,
                        isRequired: false,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: shopPhoneController,
                        label: 'Phone Number',
                        hint: 'Enter 10-digit phone',
                        icon: Icons.phone,
                        isRequired: true,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                      ),

                      const SizedBox(height: 28),

                      _buildSectionHeader(
                        'Employee Credentials',
                        Icons.security,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: empUsernameController,
                        label: 'Username',
                        hint: 'Login username',
                        icon: Icons.account_circle,
                        isRequired: true,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: empPasswordController,
                        label: 'Password',
                        hint: 'Min 6 characters',
                        icon: Icons.lock,
                        isRequired: true,
                        obscureText: true,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: empConfirmPasswordController,
                        label: 'Confirm Password',
                        hint: 'Re-enter password',
                        icon: Icons.lock_outline,
                        isRequired: true,
                        obscureText: true,
                      ),

                      // <<< EXTRA SPACE SO LAST FIELD IS ALWAYS VISIBLE >>>
                      SizedBox(height: bottomInset + 80),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // FIXED BUTTON – NEVER CUT BY NAVIGATION BAR
          Positioned(
            left: 0,
            right: 0,
            bottom: 0, // <-- stays at the very bottom of the screen
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!, width: 1),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createShop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              strokeWidth: 2,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Create Shop',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF4285F4), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4285F4),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isRequired = false,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        labelStyle: const TextStyle(
          color: Color(0xFF4285F4),
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.grey[400],
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF4285F4), size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4285F4), width: 2),
        ),
        counterText: '',
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 12,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// EDIT SHOP PAGE
// ─────────────────────────────────────────────────────────────────────

class EditShopPage extends StatefulWidget {
  final Map<String, dynamic> shopData;
  final VoidCallback onShopUpdated;

  const EditShopPage({
    super.key,
    required this.shopData,
    required this.onShopUpdated,
  });

  @override
  State<EditShopPage> createState() => _EditShopPageState();
}

class _EditShopPageState extends State<EditShopPage> {
  late TextEditingController shopNameController;
  late TextEditingController shopLocationController;
  late TextEditingController shopPhoneController;
  late TextEditingController empUsernameController;
  final empPasswordController = TextEditingController();
  final empConfirmPasswordController = TextEditingController();
  bool _isLoading = false;

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  @override
  void initState() {
    super.initState();
    shopNameController = TextEditingController(
      text: widget.shopData['shopName'],
    );
    shopLocationController = TextEditingController(
      text: widget.shopData['location'],
    );
    shopPhoneController = TextEditingController(text: widget.shopData['phone']);
    empUsernameController = TextEditingController(
      text: widget.shopData['employeeUsername'],
    );
  }

  Future<void> _updateShop() async {
    final shopName = shopNameController.text.trim();
    final location = shopLocationController.text.trim();
    final phone = shopPhoneController.text.trim();
    final empUsername = empUsernameController.text.trim();
    final empPassword = empPasswordController.text.trim();
    final empConfirmPassword = empConfirmPasswordController.text.trim();

    if (shopName.isEmpty) {
      _showSnackBar('Please enter shop name', isError: true);
      return;
    }
    if (phone.isEmpty || phone.length != 10) {
      _showSnackBar('Please enter valid 10-digit phone', isError: true);
      return;
    }
    if (empUsername.isEmpty) {
      _showSnackBar('Please enter username', isError: true);
      return;
    }
    if (empPassword.isNotEmpty) {
      if (empPassword.length < 6) {
        _showSnackBar('Password must be at least 6 characters', isError: true);
        return;
      }
      if (empPassword != empConfirmPassword) {
        _showSnackBar('Passwords do not match', isError: true);
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final updateData = {
        'shopName': shopName,
        'location': location.isEmpty ? 'N/A' : location,
        'phone': phone,
        'username': empUsername,
        'updatedAt': Timestamp.now(),
      };

      if (empPassword.isNotEmpty) {
        updateData['password'] = _hashPassword(empPassword);
      }

      await FirebaseFirestore.instance
          .collection('shop_list')
          .doc(widget.shopData['docId'])
          .update(updateData);

      await FirebaseFirestore.instance
          .collection(widget.shopData['collectionName'])
          .doc('Credentials')
          .update(updateData);

      _showSnackBar('Shop updated successfully');
      widget.onShopUpdated();
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Error updating shop: $e');
      _showSnackBar('Error updating shop: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    shopNameController.dispose();
    shopLocationController.dispose();
    shopPhoneController.dispose();
    empUsernameController.dispose();
    empPasswordController.dispose();
    empConfirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: const Text('Edit Shop'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF4285F4), Color(0xFF2E7FE8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.edit, color: Colors.white, size: 40),
                      SizedBox(height: 12),
                      Text(
                        'Edit Shop',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Update shop details and employee credentials',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                // Form
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Shop Details', Icons.store),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: shopNameController,
                        label: 'Shop Name',
                        hint: 'Enter shop name',
                        icon: Icons.store,
                        isRequired: true,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: shopLocationController,
                        label: 'Location',
                        hint: 'Enter location',
                        icon: Icons.location_on,
                        isRequired: false,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: shopPhoneController,
                        label: 'Phone Number',
                        hint: 'Enter 10-digit phone',
                        icon: Icons.phone,
                        isRequired: true,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                      ),

                      const SizedBox(height: 28),

                      _buildSectionHeader(
                        'Employee Credentials',
                        Icons.security,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: empUsernameController,
                        label: 'Username',
                        hint: 'Login username',
                        icon: Icons.account_circle,
                        isRequired: true,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: empPasswordController,
                        label: 'Password',
                        hint: 'Leave blank to keep current',
                        icon: Icons.lock,
                        isRequired: false,
                        obscureText: true,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: empConfirmPasswordController,
                        label: 'Confirm Password',
                        hint: 'Leave blank to keep current',
                        icon: Icons.lock_outline,
                        isRequired: false,
                        obscureText: true,
                      ),

                      // <<< EXTRA SPACE SO LAST FIELD IS ALWAYS VISIBLE >>>
                      SizedBox(height: bottomInset + 80),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // FIXED BUTTON – NEVER CUT BY NAVIGATION BAR
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!, width: 1),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updateShop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              strokeWidth: 2,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.update, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Update Shop',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isRequired = false,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        labelStyle: const TextStyle(
          color: Color(0xFF4285F4),
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.grey[400],
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF4285F4), size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4285F4), width: 2),
        ),
        counterText: '',
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 12,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF4285F4), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4285F4),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
