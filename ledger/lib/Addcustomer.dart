import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddCustomer extends StatefulWidget {
  const AddCustomer({super.key});

  @override
  State<AddCustomer> createState() => _AddCustomerState();
}

class _AddCustomerState extends State<AddCustomer> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // User & Shop related
  String? _userRole;
  String? _userShop;
  String? _userShopCollection;
  List<Map<String, dynamic>> _shops = [];
  String? _selectedShopCollection;
  String? _selectedShopName;
  bool _isLoadingShops = true;

  String? customerType;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController dateController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeUserAndShops();
  }

  Future<void> _initializeUserAndShops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loginType = prefs.getString('loginType');
      final shopName = prefs.getString('shopName');
      final shopCollection = prefs.getString('shopCollection');

      setState(() {
        _userRole = loginType;
        _userShop = shopName;
        _userShopCollection = shopCollection;
      });

      if (loginType == 'client') {
        await _fetchAllShops();
      } else if (loginType == 'employee') {
        setState(() {
          _selectedShopCollection = shopCollection;
          _selectedShopName = shopName;
          _isLoadingShops = false;
        });
      }
    } catch (e) {
      debugPrint('Error initializing: $e');
      setState(() => _isLoadingShops = false);
    }
  }

  Future<void> _fetchAllShops() async {
    try {
      final snapshot = await _firestore.collection('shop_list').get();

      List<Map<String, dynamic>> shopsList = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        shopsList.add({
          'collectionName': data['collectionName'] ?? '',
          'shopName': data['shopName'] ?? 'Unknown Shop',
        });
      }

      setState(() {
        _shops = shopsList;
        if (shopsList.isNotEmpty) {
          _selectedShopCollection = shopsList[0]['collectionName'];
          _selectedShopName = shopsList[0]['shopName'];
        }
        _isLoadingShops = false;
      });
    } catch (e) {
      debugPrint('Error fetching shops: $e');
      setState(() => _isLoadingShops = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF455A64),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _getCreatedByValue() {
    if (_userRole == 'client') {
      return 'Admin';
    } else if (_userRole == 'employee') {
      return 'Employee';
    }
    return 'Unknown';
  }

  Future<void> _saveCustomer() async {
    if (_userRole == 'client' &&
        (_selectedShopCollection == null || _selectedShopCollection!.isEmpty)) {
      _showError('Please select a shop');
      return;
    }

    if (nameController.text.trim().isEmpty) {
      _showError('Please enter customer name');
      return;
    }

    if (customerType == null) {
      _showError('Please select customer type');
      return;
    }

    if (mobileController.text.isEmpty || mobileController.text.length != 10) {
      _showError('Please enter valid 10-digit mobile number');
      return;
    }

    if (dateController.text.isEmpty) {
      _showError('Please select opening balance date');
      return;
    }

    if (amountController.text.trim().isEmpty) {
      _showError('Please enter opening balance amount');
      return;
    }

    if (double.tryParse(amountController.text.trim()) == null) {
      _showError('Please enter valid amount');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final customerData = {
        "customerName": nameController.text.trim(),
        "customerType": customerType,
        "mobile": mobileController.text.trim(),
        "openingDate": dateController.text.trim(),
        "openingAmount": double.tryParse(amountController.text.trim()) ?? 0.0,
        "createdAt": Timestamp.now(),
        "createdBy": _getCreatedByValue(),
        "status": "Active",
      };

      await _firestore
          .collection(_selectedShopCollection!)
          .doc('customers')
          .collection('list')
          .add(customerData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                const Text(
                  "Customer added successfully!",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 3),
          ),
        );

        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Error: $e",
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    mobileController.dispose();
    amountController.dispose();
    dateController.dispose();
    super.dispose();
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildLargeTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    IconData icon = Icons.edit_outlined,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    VoidCallback? onTap,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          onTap: onTap,
          inputFormatters: inputFormatters,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[50],
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 16),
            prefixIcon: Icon(icon, color: const Color(0xFF455A64), size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF455A64), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    Color color = const Color(0xFF455A64),
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 22)
            else
              Icon(Icons.circle_outlined, color: Colors.grey[400], size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildShopSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Shop'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: DropdownButton<String>(
            value: _selectedShopCollection,
            isExpanded: true,
            underline: const SizedBox(),
            icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
            items: _shops.map((shop) {
              return DropdownMenuItem<String>(
                value: shop['collectionName'],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    shop['shopName'],
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedShopCollection = value;
                  final shop = _shops.firstWhere(
                    (s) => s['collectionName'] == value,
                    orElse: () => {'shopName': 'Unknown'},
                  );
                  _selectedShopName = shop['shopName'];
                });
              }
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingShops) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1A1A2E),
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'Add Customer',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF455A64)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Add Customer',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      // Single scrollable page, full width, every field visible at once —
      // no step wizard, no side-by-side/grid layout.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_userRole == 'client') ...[
                _buildShopSelector(),
                const SizedBox(height: 24),
              ],

              _buildLargeTextField(
                label: 'Customer Name',
                hint: 'e.g., Raj Kumar',
                controller: nameController,
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 24),

              _sectionLabel('Customer Type'),
              const SizedBox(height: 12),
              _buildOptionCard(
                title: 'Retail',
                subtitle: 'Individual small purchases',
                icon: Icons.store_outlined,
                isSelected: customerType == 'Retail',
                onTap: () => setState(() => customerType = 'Retail'),
              ),
              const SizedBox(height: 10),
              _buildOptionCard(
                title: 'Wholesale',
                subtitle: 'Bulk purchases',
                icon: Icons.warehouse_outlined,
                isSelected: customerType == 'Wholesale',
                onTap: () => setState(() => customerType = 'Wholesale'),
                color: Colors.orange,
              ),
              const SizedBox(height: 24),

              _buildLargeTextField(
                label: 'Mobile Number',
                hint: 'e.g., 9876543210',
                controller: mobileController,
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
              ),
              const SizedBox(height: 24),

              _buildLargeTextField(
                label: 'Opening Balance Date',
                hint: 'Tap to select date',
                controller: dateController,
                icon: Icons.calendar_today_outlined,
                readOnly: true,
                onTap: () => _selectDate(context),
              ),
              const SizedBox(height: 24),

              _buildLargeTextField(
                label: 'Opening Balance Amount',
                hint: 'e.g., 5000',
                controller: amountController,
                icon: Icons.currency_rupee,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF455A64),
                disabledBackgroundColor: Colors.grey[400],
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _isLoading ? null : _saveCustomer,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save Customer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
