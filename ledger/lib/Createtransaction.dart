import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'Addcustomer.dart';

enum CustomerLedgerType { yes, no }

enum LedgerPaymentType { paymentIn, paymentOut }

class CreateTransactionScreen extends StatefulWidget {
  final DateTime date;
  final String? shopCollection;

  const CreateTransactionScreen({
    super.key,
    required this.date,
    this.shopCollection,
  });

  @override
  State<CreateTransactionScreen> createState() =>
      _CreateTransactionScreenState();
}

class _CreateTransactionScreenState extends State<CreateTransactionScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Shop related
  String? _userRole;
  bool _isLoadingShops = true;

  /// The shop this transaction belongs to. Never defaults to a hard-coded
  /// shop — if it can't be determined, saving is blocked with an error so a
  /// transaction can't land in the wrong shop.
  String? _shopCollection;

  // Form data
  CustomerLedgerType _customerLedgerType = CustomerLedgerType.yes;
  LedgerPaymentType _ledgerPaymentType = LedgerPaymentType.paymentOut;
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  String? _transactionDetails;
  String? _amount;

  bool _isLoading = false;
  bool _loadingCustomers = true;
  List<Map<String, dynamic>> _customers = [];
  double _outstandingAmount = 0.0;
  double _openingBalance = 0.0;

  // Bill photo
  File? _selectedImage;
  bool _isUploadingImage = false;
  final ImagePicker _imagePicker = ImagePicker();

  // Controllers
  late TextEditingController _transactionDetailsController;
  late TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _transactionDetailsController = TextEditingController();
    _amountController = TextEditingController();
    _initializeAndLoadCustomers();
  }

  @override
  void dispose() {
    _transactionDetailsController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _initializeAndLoadCustomers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loginType = prefs.getString('loginType') ?? 'client';

      // Same resolution as Ledger Details: the shop passed in, else the
      // logged-in user's saved shop. No hard-coded fallback.
      String? shop = widget.shopCollection;
      if (shop == null || shop.isEmpty) shop = prefs.getString('shopCollection');
      if (shop != null && shop.isEmpty) shop = null;

      if (!mounted) return;
      setState(() {
        _userRole = loginType;
        _shopCollection = shop;
        _isLoadingShops = false;
      });

      if (shop == null) {
        setState(() => _loadingCustomers = false);
        _showError(_noShopMessage);
        return;
      }

      await _loadCustomers();
    } catch (e) {
      debugPrint('Error initializing: $e');
      setState(() => _isLoadingShops = false);
    }
  }

  static const String _noShopMessage =
      'Shop not found. Please go back and open the ledger again, '
      'or log in again.';

  Future<void> _loadCustomers() async {
    final shopCollection = _shopCollection;
    if (shopCollection == null) return;

    setState(() => _loadingCustomers = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(shopCollection)
          .doc('customers')
          .collection('list')
          .where('status', isEqualTo: 'Active')
          .get();

      final customerList = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['customerName'] ?? 'Unnamed',
          'openingAmount': (data['openingAmount'] ?? 0).toDouble(),
        };
      }).toList();

      customerList.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );

      setState(() {
        _customers = customerList;
        _loadingCustomers = false;
        _selectedCustomerId = null;
        _outstandingAmount = 0.0;
        _openingBalance = 0.0;
      });
    } catch (e) {
      debugPrint('Error loading customers: $e');
      setState(() => _loadingCustomers = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading customers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadOutstandingAmount(String customerId) async {
    final shopCollection = _shopCollection;
    if (shopCollection == null) return;

    try {
      final customerRef = FirebaseFirestore.instance
          .collection(shopCollection)
          .doc('customers')
          .collection('list')
          .doc(customerId);
      final txns = customerRef.collection('transactions');

      // Server-side sums + the customer doc, all in parallel (previously the
      // whole transaction history was downloaded, then the doc fetched after).
      // Entries are added up directly (same as the Customer details page);
      // server-side sum queries were unreliable on the client's phones.
      final results = await Future.wait<Object>([
        txns.get(),
        customerRef.get(),
      ]);
      double totalPaymentIn = 0;
      double totalPaymentOut = 0;
      for (final doc
          in (results[0] as QuerySnapshot<Map<String, dynamic>>).docs) {
        final d = doc.data();
        final amt = (d['amount'] ?? 0).toDouble();
        if (d['isCredit'] == true) {
          totalPaymentOut += amt; // Payment OUT → INCREASE outstanding
        } else {
          totalPaymentIn += amt; // Payment IN → REDUCE outstanding
        }
      }
      final customerDoc =
          results[1] as DocumentSnapshot<Map<String, dynamic>>;

      final openingAmount = (customerDoc.data()?['openingAmount'] ?? 0)
          .toDouble();

      setState(() {
        // ✅ CORRECT FORMULA: Outstanding = Opening - Payment IN + Payment OUT
        // Payment IN reduces what customer owes, Payment OUT increases what customer owes
        _outstandingAmount = openingAmount - totalPaymentIn + totalPaymentOut;
        _openingBalance = openingAmount;
      });
    } catch (e) {
      debugPrint('Error loading outstanding amount: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        // Shrink phone-camera photos (often 3-5 MB) to a bill-readable size
        // so uploads finish in a second or two instead of many seconds.
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 70,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Select Image Source',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildImageSourceOption(
                        icon: Icons.camera_alt,
                        label: 'Camera',
                        color: const Color(0xFF455A64),
                        onTap: () {
                          Navigator.pop(context);
                          _pickImage(ImageSource.camera);
                        },
                      ),
                      _buildImageSourceOption(
                        icon: Icons.photo_library,
                        label: 'Gallery',
                        color: const Color(0xFF455A64),
                        onTap: () {
                          Navigator.pop(context);
                          _pickImage(ImageSource.gallery);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _uploadImageToFirebase() async {
    if (_selectedImage == null) return null;

    try {
      setState(() => _isUploadingImage = true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName =
          'bill_${timestamp}_${_selectedImage!.path.split('/').last}';
      final ref = FirebaseStorage.instance.ref().child('bills').child(fileName);

      await ref.putFile(_selectedImage!);
      final downloadUrl = await ref.getDownloadURL();

      setState(() => _isUploadingImage = false);
      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      setState(() => _isUploadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _saveTransaction() async {
    // Validate transaction type specific fields
    if (_customerLedgerType == CustomerLedgerType.yes) {
      if (_selectedCustomerId == null) {
        _showError('Please select a customer');
        return;
      }
    } else {
      if (_transactionDetailsController.text.trim().isEmpty) {
        _showError('Please enter transaction details');
        return;
      }
    }

    if (_amountController.text.isEmpty) {
      _showError('Please enter amount');
      return;
    }

    final amountText = _amountController.text.trim().replaceAll(',', '');
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _showError('Please enter valid amount');
      return;
    }

    final shopCollection = _shopCollection;
    if (shopCollection == null) {
      _showError(_noShopMessage);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Upload image first if selected
      String? billPhotoUrl;
      if (_selectedImage != null) {
        billPhotoUrl = await _uploadImageToFirebase();
      }

      final ledgerDate = DateFormat('dd-MMM-yyyy').format(widget.date);
      String finalLedgerName;
      String description;

      if (_customerLedgerType == CustomerLedgerType.yes) {
        // For customer transactions, use customer name as ledger name
        finalLedgerName = _selectedCustomerName ?? 'Customer';
        description = 'Customer transaction';
      } else {
        // For general expenses, use transaction details as both ledger name and description
        finalLedgerName = _transactionDetailsController.text;
        description = _transactionDetailsController.text;
      }

      // Calculate isCredit based on new logic
      // Payment IN = DEBIT (isCredit = false)
      // Payment OUT = CREDIT (isCredit = true)
      final isCredit = _ledgerPaymentType == LedgerPaymentType.paymentOut;

      debugPrint(
        'Saving: Amount=$amount, Ledger=$finalLedgerName, Shop=$shopCollection, Photo=${billPhotoUrl != null ? "Yes" : "No"}',
      );
      debugPrint(
        'Payment Type: ${_ledgerPaymentType == LedgerPaymentType.paymentIn ? "Payment IN" : "Payment OUT"}, isCredit=$isCredit',
      );

      // All writes go in one batch: a single network round trip instead of
      // three sequential ones, and they succeed or fail together.
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      // The ledger entry and the customer's copy share ONE id, so later
      // edits/deletes from Ledger Details can always find the customer copy.
      final ledgerTxnRef = db
          .collection(shopCollection)
          .doc('ledgers')
          .collection('transactions')
          .doc();

      // Save customer transaction if it's a customer transaction
      if (_customerLedgerType == CustomerLedgerType.yes) {
        final customerRef = db
            .collection(shopCollection)
            .doc('customers')
            .collection('list')
            .doc(_selectedCustomerId!);
        batch.set(customerRef.collection('transactions').doc(ledgerTxnRef.id), {
          'amount': amount,
          'description': description,
          // Payment IN = DEBIT (isCredit = false)
          // Payment OUT = CREDIT (isCredit = true)
          'isCredit': isCredit,
          'ledgerDate': ledgerDate,
          'createdAt': FieldValue.serverTimestamp(),
          if (billPhotoUrl != null) 'billPhotoUrl': billPhotoUrl,
        });
        batch.update(customerRef, {
          'lastTransaction': FieldValue.serverTimestamp(),
        });
      }

      // Save to shop's ledger collection
      batch.set(
        ledgerTxnRef,
        {
          'amount': amount,
          'description': description,
          'ledgerName': finalLedgerName,
          // Payment IN = DEBIT (isCredit = false)
          // Payment OUT = CREDIT (isCredit = true)
          'isCredit': isCredit,
          'transactionType': _customerLedgerType == CustomerLedgerType.yes
              ? 'Customer'
              : 'General',
          'ledgerDate': ledgerDate,
          'createdAt': FieldValue.serverTimestamp(),
          if (_customerLedgerType == CustomerLedgerType.yes &&
              _selectedCustomerName != null)
            'customerName': _selectedCustomerName!,
          if (_customerLedgerType == CustomerLedgerType.yes)
            'customerId': _selectedCustomerId!,
          if (_customerLedgerType == CustomerLedgerType.yes)
            'customerTxnId': ledgerTxnRef.id,
          if (billPhotoUrl != null) 'billPhotoUrl': billPhotoUrl,
        },
      );

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                const Text(
                  'Transaction saved!',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
            'Create Transaction',
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
          'Create Transaction',
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
              // ── Date ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF455A64).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF455A64).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Color(0xFF455A64)),
                    const SizedBox(width: 12),
                    Text(
                      DateFormat('dd-MMM-yyyy').format(widget.date),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF455A64),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Transaction type ──
              _sectionLabel('Transaction Type'),
              const SizedBox(height: 12),
              _buildOptionCard(
                title: 'Customer Transaction',
                subtitle: 'Payment from or to a customer',
                icon: Icons.person,
                isSelected: _customerLedgerType == CustomerLedgerType.yes,
                onTap: () => setState(
                  () => _customerLedgerType = CustomerLedgerType.yes,
                ),
              ),
              const SizedBox(height: 10),
              _buildOptionCard(
                title: 'General Transaction',
                subtitle: 'Other business expenses or income',
                icon: Icons.business,
                isSelected: _customerLedgerType == CustomerLedgerType.no,
                onTap: () =>
                    setState(() => _customerLedgerType = CustomerLedgerType.no),
              ),
              const SizedBox(height: 28),

              // ── Payment direction ──
              _sectionLabel('Payment Direction'),
              const SizedBox(height: 12),
              _buildOptionCard(
                title: 'Payment In',
                subtitle: 'Money received',
                icon: Icons.arrow_downward,
                isSelected: _ledgerPaymentType == LedgerPaymentType.paymentIn,
                onTap: () => setState(
                  () => _ledgerPaymentType = LedgerPaymentType.paymentIn,
                ),
                color: Colors.green,
              ),
              const SizedBox(height: 10),
              _buildOptionCard(
                title: 'Payment Out',
                subtitle: 'Money spent',
                icon: Icons.arrow_upward,
                isSelected: _ledgerPaymentType == LedgerPaymentType.paymentOut,
                onTap: () => setState(
                  () => _ledgerPaymentType = LedgerPaymentType.paymentOut,
                ),
                color: Colors.red,
              ),
              const SizedBox(height: 28),

              // ── Customer / details ──
              if (_customerLedgerType == CustomerLedgerType.yes) ...[
                _sectionLabel('Customer'),
                const SizedBox(height: 12),
                if (_loadingCustomers)
                  const Center(child: CircularProgressIndicator())
                else if (_customers.isEmpty)
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AddCustomer(shopCollection: _shopCollection),
                        ),
                      ).then((_) => _loadCustomers());
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF455A64).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF455A64).withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            color: Color(0xFF455A64),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No customers. Tap to add one.',
                              style: TextStyle(
                                color: Color(0xFF455A64),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(canvasColor: Colors.white),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCustomerId,
                          isExpanded: true,
                          hint: Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                color: Colors.grey[500],
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Select a customer',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          icon: Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.grey[600],
                            size: 24,
                          ),
                          items: _customers.map((customer) {
                            return DropdownMenuItem<String>(
                              value: customer['id'],
                              child: Text(
                                customer['name'],
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedCustomerId = value);
                              final customer = _customers.firstWhere(
                                (c) => c['id'] == value,
                              );
                              setState(
                                () => _selectedCustomerName = customer['name'],
                              );
                              _loadOutstandingAmount(value);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                if (_selectedCustomerId != null) ...[
                  const SizedBox(height: 16),
                  // Outstanding Amount Card - Dynamic color based on amount
                  // Positive amount (customer owes us) = RED
                  // Negative amount (we owe customer) = GREEN
                  Builder(
                    builder: (context) {
                      final bool isPositive = _outstandingAmount >= 0;
                      final Color primaryColor = isPositive
                          ? Colors.red[700]!
                          : Colors.green[700]!;
                      final Color backgroundColor = isPositive
                          ? Colors.red[50]!
                          : Colors.green[50]!;
                      final Color borderColor = isPositive
                          ? Colors.red[200]!
                          : Colors.green[200]!;
                      final Color iconBackgroundColor = isPositive
                          ? Colors.red[100]!
                          : Colors.green[100]!;

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: iconBackgroundColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.account_balance_wallet,
                                color: primaryColor,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Outstanding Amount',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₹${NumberFormat('#,##,##0.00').format(_outstandingAmount.abs())}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ] else ...[
                _sectionLabel('Transaction Details'),
                const SizedBox(height: 12),
                _buildLargeTextField(
                  label: 'What is this transaction about?',
                  hint: 'e.g., Office supplies, Petrol, Tea, Salary',
                  controller: _transactionDetailsController,
                ),
              ],
              const SizedBox(height: 28),

              // ── Amount ──
              _sectionLabel('Amount'),
              const SizedBox(height: 12),
              _buildLargeTextField(
                label: 'Amount in Rupees',
                hint: 'e.g., 500',
                keyboardType: TextInputType.number,
                controller: _amountController,
              ),
              const SizedBox(height: 28),

              // ── Bill photo ──
              _sectionLabel('Bill Photo (Optional)'),
              const SizedBox(height: 12),
              _buildBillPhotoSection(),
            ],
          ),
        ),
      ),
      // Lift the button bar above the on-screen keyboard so it is never hidden.
      bottomNavigationBar: Builder(
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
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
              onPressed: _isLoading || _isUploadingImage
                  ? null
                  : _saveTransaction,
              child: _isLoading || _isUploadingImage
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save Transaction',
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
        ),
      ),
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

  Widget _buildLargeTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: keyboardType,
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

  Widget _buildBillPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedImage != null) ...[
          Container(
            width: double.infinity,
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _selectedImage!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedImage = null;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showImageSourceDialog,
            icon: const Icon(Icons.camera_alt, size: 18),
            label: const Text('Change Photo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF455A64),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ] else ...[
          GestureDetector(
            onTap: _showImageSourceDialog,
            child: Container(
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey[300]!,
                  style: BorderStyle.solid,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tap to add bill photo',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
