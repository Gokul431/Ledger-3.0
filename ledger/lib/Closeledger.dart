import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CloseLedgerScreen extends StatefulWidget {
  final DateTime date;
  final String? shopCollection;

  const CloseLedgerScreen({super.key, required this.date, this.shopCollection});

  @override
  State<CloseLedgerScreen> createState() => _CloseLedgerScreenState();
}

class _CloseLedgerScreenState extends State<CloseLedgerScreen> {
  late DateTime _selectedDate;
  final List<int> denominations = [500, 100, 50, 20, 10, 1];
  late List<TextEditingController> _controllers;
  late TextEditingController _salesController;
  late List<int> _denominationTotals;

  bool _isLoading = true;

  int _openingBalance = 0;
  int _closingBalance = 0;
  bool _ledgerClosed = false;

  // Shop info
  String? _selectedShopCollection;
  String _userRole = '';
  bool _isEmployeeLogin = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.date;

    _controllers = List.generate(
      denominations.length,
      (_) => TextEditingController(),
    );
    _salesController = TextEditingController();
    _denominationTotals = List.generate(denominations.length, (_) => 0);

    for (int i = 0; i < _controllers.length; i++) {
      _controllers[i].addListener(() => _updateTotal(i));
    }

    _initializeAndLoad();
  }

  Future<void> _initializeAndLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loginType = prefs.getString('loginType') ?? 'employee';
      final shopCollection =
          widget.shopCollection ??
          prefs.getString('shopCollection') ??
          'vks_retails';

      setState(() {
        _userRole = loginType;
        _isEmployeeLogin = loginType == 'employee';
        _selectedShopCollection = shopCollection;
      });

      if (_isEmployeeLogin) {
        // Employee can only view, not close
        _showEmployeeRestrictedDialog();
        return;
      }

      await _loadLedgerData();
    } catch (e) {
      debugPrint('Error initializing: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showEmployeeRestrictedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.lock, color: Colors.red[700], size: 28),
            const SizedBox(width: 12),
            const Text('Access Restricted'),
          ],
        ),
        content: const Text(
          'Employees cannot close ledgers.\nOnly Admin can close ledgers.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _updateTotal(int index) {
    int count = int.tryParse(_controllers[index].text) ?? 0;
    setState(() {
      _denominationTotals[index] = count * denominations[index];
    });
  }

  int get _grandTotal {
    return _denominationTotals.fold(0, (sum, t) => sum + t);
  }

  int get _totalNotes =>
      _controllers.fold(0, (sum, c) => sum + (int.tryParse(c.text) ?? 0));

  Future<void> _loadLedgerData() async {
    setState(() => _isLoading = true);

    try {
      if (_selectedShopCollection == null) {
        throw Exception('Shop collection not available');
      }

      final firestore = FirebaseFirestore.instance;
      final ledgerDate = DateFormat('dd-MMM-yyyy').format(_selectedDate);

      // Get ledger from: shopCollection/ledgers/dates/{ledgerDate}
      final docRef = firestore
          .collection(_selectedShopCollection!)
          .doc('ledgers')
          .collection('dates')
          .doc(ledgerDate);

      final doc = await docRef.get();

      if (!doc.exists) {
        _showErrorDialog('No ledger found for this date');
        return;
      }

      final data = doc.data();

      final ob = data?['openingBalance'];
      _openingBalance = ob is int ? ob : (ob is double ? ob.toInt() : 0);

      final cb = data?['closingBalance'];
      _closingBalance = cb is int ? cb : (cb is double ? cb.toInt() : 0);

      _ledgerClosed =
          (data?['status'] ?? '').toString().toLowerCase() == 'closed';

      if (_ledgerClosed) {
        final denominationsMap = Map<String, dynamic>.from(
          data?['denominations'] ?? {},
        );

        for (int i = 0; i < denominations.length; i++) {
          final key = denominations[i].toString();
          int count = 0;

          if (denominationsMap.containsKey(key)) {
            final v = denominationsMap[key];
            count = v is int ? v : (v is double ? v.toInt() : 0);
          }

          _controllers[i].text = count.toString();
          _denominationTotals[i] = count * denominations[i];
        }
        
        _salesController.text = (data?['saleValue'] ?? 0).toString();
      } else {
        // Set all denominations to 0 (removed auto-calculation)
        for (int i = 0; i < denominations.length; i++) {
          _controllers[i].text = '0';
          _denominationTotals[i] = 0;
        }
      }

    } catch (e) {
      debugPrint('Error loading ledger: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading ledger: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveLedgerToFirestore() async {
    // Validate sales value
    if (_salesController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter sales value'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final double salesValue =
        double.tryParse(_salesController.text.replaceAll(',', '').trim()) ??
        0.0;

    if (salesValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid sales value'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_selectedShopCollection == null) {
        throw Exception('Shop collection not available');
      }

      final firestore = FirebaseFirestore.instance;
      final ledgerDate = DateFormat('dd-MMM-yyyy').format(_selectedDate);

      // Reference: shopCollection/ledgers/dates/{ledgerDate}
      final docRef = firestore
          .collection(_selectedShopCollection!)
          .doc('ledgers')
          .collection('dates')
          .doc(ledgerDate);

      final Map<String, int> denominationMap = {};
      for (int i = 0; i < denominations.length; i++) {
        denominationMap[denominations[i].toString()] =
            int.tryParse(_controllers[i].text) ?? 0;
      }

      int closingBalance = _denominationTotals.fold(0, (sum, t) => sum + t);

      // Update the ledger document
      await docRef.update({
        'closingBalance': closingBalance,
        'denominations': denominationMap,
        'totals': _denominationTotals,
        'saleValue': salesValue,
        'status': 'Closed',
        'closedAt': FieldValue.serverTimestamp(),
      });

      _closingBalance = closingBalance;
      _ledgerClosed = true;

      if (!mounted) return;
      _showSuccessDialog(closingBalance);
    } catch (e) {
      debugPrint('Error closing ledger: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to close ledger: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog(int closingBalance) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green[600],
                  size: 60,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Ledger Closed!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Your ledger has been closed successfully with closing balance of ₹${NumberFormat('#,##,##0').format(closingBalance)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConfirmCloseDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange[700], size: 28),
            const SizedBox(width: 12),
            const Text('Confirm Close'),
          ],
        ),
        content: const Text(
          'Are you sure you want to close this ledger?\nThis action cannot be undone.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveLedgerToFirestore();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Close Ledger'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    _salesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Close Ledger',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('dd MMM yyyy').format(_selectedDate),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Opening Balance Card
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue[400]!, Colors.blue[600]!],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.account_balance,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Opening Balance',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '₹${NumberFormat('#,##,##0').format(_openingBalance)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Denomination Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Denomination Count',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _ledgerClosed
                              ? 'Ledger closed - View only'
                              : 'Enter the count of each denomination',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 12),

                        ...List.generate(denominations.length, (i) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 55,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.blue[400]!,
                                        Colors.blue[600]!,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '₹${denominations[i]}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  '×',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  width: 70,
                                  decoration: BoxDecoration(
                                    color: _ledgerClosed
                                        ? Colors.grey[200]
                                        : Colors.grey[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                    ),
                                  ),
                                  child: TextField(
                                    controller: _controllers[i],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    enabled: !_ledgerClosed,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: '0',
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 10,
                                      ),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                const Text(
                                  '=',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '₹${NumberFormat('#,##,##0').format(_denominationTotals[i])}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[700],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        const SizedBox(height: 8),

                        // Total Cash Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green[400]!, Colors.green[600]!],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Cash',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    '₹${NumberFormat('#,##,##0').format(_grandTotal)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Notes',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '$_totalNotes notes',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Sales Value (Required)
                        Row(
                          children: [
                            const Text(
                              'Sales Value',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '*',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _salesController,
                          keyboardType: TextInputType.number,
                          enabled: !_ledgerClosed,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Enter today\'s sales value...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[400],
                            ),
                            filled: true,
                            fillColor: _ledgerClosed
                                ? Colors.grey[200]
                                : Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFF4285F4),
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),

                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: _ledgerClosed
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(14),
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
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: ElevatedButton(
                        onPressed: _showConfirmCloseDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4285F4),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Close Ledger',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}