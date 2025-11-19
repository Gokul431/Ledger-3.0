import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:excel/excel.dart' as excel;
import 'Closeledger.dart';
import 'Createtransaction.dart';

import 'edit_transaction_screen.dart'; // ✅ Import the new edit screen

import 'pdf_export_service.dart';
import 'excel_export_service.dart';

class LedgerDetailsScreen extends StatefulWidget {
  final DateTime date;
  final String? shopCollection;
  final String? shopName;

  const LedgerDetailsScreen({
    super.key,
    required this.date,
    this.shopCollection,
    this.shopName,
  });

  @override
  State<LedgerDetailsScreen> createState() => _LedgerDetailsScreenState();
}

class _LedgerDetailsScreenState extends State<LedgerDetailsScreen>
    with WidgetsBindingObserver {
  // Shop related
  String? _userRole;
  String? _selectedShopCollection;
  String? _selectedShopName;
  bool _isLoadingShops = false;

  // Ledger data
  Map<String, dynamic>? _ledgerData;
  DocumentReference<Map<String, dynamic>>? _ledgerRef;
  bool _isLoading = true;
  bool _isLedgerClosed = false;
  bool _isDownloading = false;
  bool _isEmployeeLogin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAndLoadLedger();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('App lifecycle state: $state');

    switch (state) {
      case AppLifecycleState.paused:
        // App going to background
        break;
      case AppLifecycleState.resumed:
        // App coming back to foreground
        if (mounted) {
          _fetchLedgerByDate(); // Refresh data when coming back
        }
        break;
      case AppLifecycleState.detached:
        // App being destroyed
        break;
      default:
        break;
    }
  }

  Future<void> _initializeAndLoadLedger() async {
    if (!mounted) return; // ✅ Early return if disposed

    try {
      final prefs = await SharedPreferences.getInstance();
      final loginType = prefs.getString('loginType') ?? 'client';

      String? shopCollection = widget.shopCollection;
      String? shopName = widget.shopName;

      if (shopCollection == null || shopCollection.isEmpty) {
        shopCollection = prefs.getString('shopCollection');
        shopName = prefs.getString('shopName');
      }

      debugPrint('Initialized - Shop: $shopCollection, Role: $loginType');

      if (!mounted) return; // ✅ Check again before setState

      if (shopCollection == null || shopCollection.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: Shop information not available'),
              backgroundColor: Colors.red,
            ),
          );
        }
        if (mounted) {
          // ✅ Extra safety check
          setState(() {
            _isLoading = false;
            _isLoadingShops = false;
          });
        }
        return;
      }

      if (mounted) {
        // ✅ Check before setState
        setState(() {
          _userRole = loginType;
          _isEmployeeLogin = loginType == 'employee';
          _selectedShopCollection = shopCollection;
          _selectedShopName = shopName;
          _isLoadingShops = false;
        });
      }

      await _fetchLedgerByDate();
    } catch (e) {
      debugPrint('Error initializing: $e');
      if (mounted) {
        // ✅ Check before setState
        setState(() => _isLoadingShops = false);
      }
    }
  }

  /// Fetch ledger document by ledgerDate from shop collection
  Future<void> _fetchLedgerByDate() async {
    if (!mounted) return;
    if (_selectedShopCollection == null || _selectedShopCollection!.isEmpty) {
      debugPrint('Error: Shop collection is null or empty');
      setState(() => _isLoading = false);
      return;
    }

    final ledgerDate = DateFormat('dd-MMM-yyyy').format(widget.date);

    try {
      debugPrint(
        'Fetching ledger from: $_selectedShopCollection/ledgers/dates for date: $ledgerDate',
      );

      final query = await FirebaseFirestore.instance
          .collection(
            _selectedShopCollection!,
          ) // ✅ Using correct shop collection
          .doc('ledgers')
          .collection('dates')
          .where('ledgerDate', isEqualTo: ledgerDate)
          .limit(1)
          .get();

      if (!mounted) return;

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final data = doc.data();

        debugPrint('Ledger found: ${doc.id}');

        final status = (data['status'] ?? 'Open').toString().toLowerCase();

        setState(() {
          _ledgerData = data;
          _ledgerRef = doc.reference;
          _isLedgerClosed = (status == 'closed');
          _isLoading = false;
        });
      } else {
        debugPrint(
          "No ledger found for $ledgerDate in $_selectedShopCollection",
        );
        if (mounted) {
          // ✅ Check before setState
          setState(() {
            _ledgerData = null;
            _ledgerRef = null;
            _isLedgerClosed = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching ledger: $e");
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching ledger: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ✅ FIXED: Stream of transactions without orderBy to avoid index requirement
  Stream<QuerySnapshot<Map<String, dynamic>>>? _getTransactionsStream() {
    if (_selectedShopCollection == null || _selectedShopCollection!.isEmpty) {
      return null;
    }

    final ledgerDate = DateFormat('dd-MMM-yyyy').format(widget.date);

    return FirebaseFirestore.instance
        .collection(_selectedShopCollection!)
        .doc('ledgers')
        .collection('transactions')
        .where('ledgerDate', isEqualTo: ledgerDate)
        .snapshots(); // ✅ Removed .orderBy to avoid index requirement
  }

  /// Update closing balance
  Future<void> _updateClosingBalance(double newTotal) async {
    if (_ledgerRef == null || _isLedgerClosed) return;
    try {
      await _ledgerRef!.update({'closingBalance': newTotal});
    } catch (e) {
      debugPrint("Error updating closing balance: $e");
    }
  }

  /// Get proper title for transaction
  String _getTransactionTitle(Map<String, dynamic> data) {
    final transactionType = data['transactionType']?.toString() ?? '';
    final customerName = data['customerName']?.toString() ?? '';
    final ledgerName = data['ledgerName']?.toString() ?? '';
    final description = data['description']?.toString() ?? '';

    if (transactionType == 'Customer' && customerName.isNotEmpty) {
      return customerName;
    } else if (transactionType == 'General' && ledgerName.isNotEmpty) {
      return ledgerName;
    } else if (customerName.isNotEmpty) {
      return customerName;
    } else if (ledgerName.isNotEmpty) {
      return ledgerName;
    } else if (description.isNotEmpty) {
      return description;
    } else {
      return 'Unnamed Transaction';
    }
  }

  /// Get subtitle for transaction - Professional labels
  String _getTransactionSubtitle(Map<String, dynamic> data) {
    final transactionType = data['transactionType']?.toString() ?? '';
    final description = data['description']?.toString() ?? '';
    final bool isCredit = (data['isCredit'] ?? false) as bool;

    // For Customer transactions
    if (transactionType == 'Customer') {
      // Ignore generic "Customer transaction" description
      if (description.isNotEmpty &&
          description.toLowerCase() != 'customer transaction') {
        return description;
      }
      return isCredit ? 'Customer Credit' : 'Customer Payment';
    }

    // For General transactions - show professional label instead of repeating name
    if (transactionType == 'General') {
      // Ignore generic descriptions like "Petrol", "Rent", etc.
      // Just show the transaction type
      return isCredit ? 'General Credit' : 'General Expense';
    }

    return description.isNotEmpty ? description : 'Transaction';
  }

  /// Build professional shimmer loading effect
  Widget _buildProfessionalShimmer(bool isLandscape) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[50]!,
      period: const Duration(milliseconds: 1200),
      direction: ShimmerDirection.ltr,
      child: Container(
        color: Colors.grey[50],
        child: Column(
          children: [
            Container(
              margin: EdgeInsets.zero,
              padding: EdgeInsets.symmetric(
                vertical: isLandscape ? 16 : 20,
                horizontal: 16,
              ),
              color: Colors.white,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 14,
                          width: 80,
                          color: Colors.grey[200],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 22,
                          width: double.infinity,
                          color: Colors.grey[200],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.white,
                child: ListView.builder(
                  itemCount: 8,
                  itemBuilder: (context, index) {
                    return Column(
                      children: [
                        Container(
                          padding: EdgeInsets.all(isLandscape ? 14 : 16),
                          child: Row(
                            children: [
                              Container(
                                width: isLandscape ? 16 : 18,
                                height: isLandscape ? 16 : 18,
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: isLandscape ? 12 : 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      height: isLandscape ? 14 : 16,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    SizedBox(height: isLandscape ? 6 : 8),
                                    Container(
                                      height: isLandscape ? 11 : 12,
                                      width:
                                          MediaQuery.of(context).size.width *
                                          0.6,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                height: isLandscape ? 15 : 16,
                                width: 80,
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          indent: isLandscape ? 80 : 78,
                          endIndent: isLandscape ? 24 : 16,
                          color: Colors.grey[200],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Full-width Opening Balance Card
  Widget _buildOpeningBalanceCard(double opening) {
    final isLandscape = _isLandscape(context);
    return Container(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.symmetric(
        vertical: isLandscape ? 16 : 20,
        horizontal: 16,
      ),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.trending_up,
              color: Colors.green[700],
              size: isLandscape ? 20 : 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Opening Balance',
                  style: TextStyle(
                    fontSize: isLandscape ? 13 : 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '₹${NumberFormat('#,##,##0.00').format(opening)}',
                    style: TextStyle(
                      fontSize: isLandscape ? 22 : 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.green[700],
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build transaction item - SIMPLIFIED to use _getTransactionSubtitle
  Widget _buildTransactionItem(
    BuildContext context,
    Map<String, dynamic> data,
    DocumentSnapshot doc,
    bool isLandscape,
  ) {
    final title = _getTransactionTitle(data);
    final subtitle = _getTransactionSubtitle(data); // ✅ USE THE METHOD!
    final bool isCredit = (data['isCredit'] ?? false) as bool;
    final double amount = (data['amount'] ?? 0).toDouble();
    final createdAt = (data['createdAt'] as Timestamp).toDate();

    final statusColor = isCredit ? Colors.green : Colors.red;

    return GestureDetector(
      // Only allow long press for ADMIN users
      onLongPress: !_isEmployeeLogin
          ? () => _showTransactionOptionsDialog(context, doc, data)
          : () => _showEmployeeRestrictedDialog(),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isLandscape ? 14 : 16),
            child: Row(
              children: [
                Container(
                  width: isLandscape ? 16 : 18,
                  height: isLandscape ? 16 : 18,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: statusColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    isCredit
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: statusColor,
                    size: isLandscape ? 12 : 14,
                  ),
                ),
                SizedBox(width: isLandscape ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: isLandscape ? 14.5 : 15.5,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      SizedBox(height: isLandscape ? 2 : 3),
                      Text(
                        '$subtitle · ${DateFormat('h:mm a').format(createdAt)}',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                          fontSize: isLandscape ? 12 : 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: isLandscape ? 15.5 : 16.5,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            indent: isLandscape ? 80 : 78,
            endIndent: isLandscape ? 24 : 16,
            color: Colors.grey[200],
          ),
        ],
      ),
    );
  }

  /// Show transaction options bottom sheet - FIXED FOR NO OVERFLOW
  void _showTransactionOptionsDialog(
    BuildContext context,
    DocumentSnapshot doc,
    Map<String, dynamic> data,
  ) {
    // Check if ledger is closed
    if (_isLedgerClosed) {
      _showLedgerClosedDialog();
      return;
    }

    final title = _getTransactionTitle(data);
    final amount = (data['amount'] ?? 0).toDouble();
    final isCredit = data['isCredit'] ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          // ✅ FIXED: Use constraints instead of fixed height
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
            minHeight: 280,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Transaction Options',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: (isCredit ? Colors.green : Colors.red)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isCredit
                                  ? Icons.add_circle_outline
                                  : Icons.remove_circle_outline,
                              color: isCredit
                                  ? Colors.green[700]
                                  : Colors.red[700],
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '₹${amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isCredit
                                    ? Colors.green[700]
                                    : Colors.red[700],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Options - FIXED: Wrapped in Flexible to prevent overflow
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.edit_outlined,
                            color: Colors.blue[700],
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Edit Transaction',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text('Modify amount or details'),
                        onTap: () {
                          Navigator.pop(context);
                          _editTransaction(doc, data);
                        },
                      ),

                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.delete_outline,
                            color: Colors.red[700],
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Delete Transaction',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text('Remove this transaction'),
                        onTap: () {
                          Navigator.pop(context);
                          _confirmDeleteTransaction(doc, data);
                        },
                      ),
                    ],
                  ),
                ),

                // Bottom padding for safe area
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Navigate to separate edit screen
  void _editTransaction(DocumentSnapshot doc, Map<String, dynamic> data) {
    if (!mounted) return; // ✅ Safety check

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditTransactionScreen(
          transactionDoc: doc,
          transactionData: data,
          shopCollection: _selectedShopCollection!,
          ledgerDate: widget.date,
        ),
      ),
    ).then((result) {
      // ✅ Check if widget is still mounted before refreshing
      if (mounted && result == true) {
        _fetchLedgerByDate();
      }
    });
  }

  /// Simple professional delete confirmation dialog
  void _confirmDeleteTransaction(
    DocumentSnapshot doc,
    Map<String, dynamic> data,
  ) {
    final title = _getTransactionTitle(data);
    final amount = (data['amount'] ?? 0).toDouble();
    final isCredit = data['isCredit'] ?? false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.red, size: 24),
              SizedBox(width: 12),
              Text(
                'Delete Transaction',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to delete this transaction?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      isCredit
                          ? Icons.add_circle_outline
                          : Icons.remove_circle_outline,
                      color: isCredit ? Colors.green[700] : Colors.red[700],
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₹${amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: isCredit ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This will update your closing balance automatically.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.orange[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteTransaction(doc);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Delete transaction with correct balance calculation
  Future<void> _deleteTransaction(DocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      final amount = (data['amount'] ?? 0).toDouble();
      final isCredit = data['isCredit'] ?? false;

      // Start batch for atomic updates
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // Delete transaction
      batch.delete(doc.reference);

      // Update closing balance correctly
      await _updateClosingBalanceForDelete(batch, amount, isCredit);

      // Commit all changes
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 8),
                Text('Transaction deleted successfully'),
              ],
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }

      // Refresh ledger data
      _fetchLedgerByDate();
    } catch (e) {
      debugPrint('Error deleting transaction: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting transaction: $e'),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    }
  }

  /// Update closing balance when deleting transaction
  Future<void> _updateClosingBalanceForDelete(
    WriteBatch batch,
    double amount,
    bool isCredit,
  ) async {
    try {
      final ledgerDate = DateFormat('dd-MMM-yyyy').format(widget.date);

      // Get the ledger document
      final ledgerQuery = await FirebaseFirestore.instance
          .collection(_selectedShopCollection!)
          .doc('ledgers')
          .collection('dates')
          .where('ledgerDate', isEqualTo: ledgerDate)
          .limit(1)
          .get();

      if (ledgerQuery.docs.isEmpty) return;

      final ledgerDoc = ledgerQuery.docs.first;
      final currentClosingBalance = (ledgerDoc.data()['closingBalance'] ?? 0)
          .toDouble();

      // Calculate new balance by removing the deleted transaction's impact
      double newBalance = currentClosingBalance;
      if (isCredit) {
        newBalance -= amount; // Remove credit impact
      } else {
        newBalance += amount; // Remove debit impact
      }

      // Update ledger document in the batch
      batch.update(ledgerDoc.reference, {
        'closingBalance': newBalance,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating balance for delete: $e');
      rethrow;
    }
  }

  /// Show employee restricted dialog
  void _showEmployeeRestrictedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Colors.orange, size: 24),
              SizedBox(width: 12),
              Text(
                'Admin Only',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: const Text(
            'You do not have permission to edit or delete transactions. Only administrators can modify transactions.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Understood',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Show dialog when trying to create transaction on closed ledger
  void _showLedgerClosedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.lock, color: Colors.red, size: 24),
              SizedBox(width: 12),
              Text(
                'Ledger Closed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'This ledger has been closed and locked. You cannot add, edit, or delete transactions in a closed ledger.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'OK',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Handle add transaction button press
  void _handleAddTransaction() {
    if (!mounted) return;
    if (_isLedgerClosed) {
      _showLedgerClosedDialog();
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreateTransactionScreen(
            date: widget.date,
            shopCollection: _selectedShopCollection,
          ),
        ),
      ).then((_) {
        if (mounted) {
          _fetchLedgerByDate();
        }
      });
    }
  }

  /// Show download format selection dialog
  void _showDownloadDialog(List<QueryDocumentSnapshot> docs) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.download, color: Color(0xFF4285F4), size: 22),
              SizedBox(width: 8),
              Text(
                'Download Format',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select format:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _downloadPDF(docs);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.red[200]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.picture_as_pdf,
                              color: Colors.red[600],
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'PDF',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _downloadExcel(docs);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.green[200]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.table_chart,
                              color: Colors.green[600],
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Excel',
                              style: TextStyle(fontWeight: FontWeight.w600),
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
        );
      },
    );
  }

  Future<void> _saveAndShowPdf(pw.Document pdf, String fileName) async {
    final output = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fullName = '${fileName}_$timestamp.pdf';
    final filePath = '${output.path}/$fullName';

    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    debugPrint('PDF saved to: $filePath');
    _showFileOptionsDialog(filePath, 'PDF');
  }

  Future<void> _downloadPDF(List<QueryDocumentSnapshot> docs) async {
    setState(() => _isDownloading = true);

    try {
      final ledgerDate = DateFormat('dd-MMM-yyyy').format(widget.date);
      final opening = (_ledgerData?['openingBalance'] ?? 0).toDouble();
      final closing = (_ledgerData?['closingBalance'] ?? 0).toDouble();
      final saleValue = (_ledgerData?['saleValue'] ?? 0).toDouble();

      // ✅ Sort transactions by createdAt in memory before passing to export
      final List<Map<String, dynamic>> transactions = docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();

      // Sort transactions chronologically (first added = first shown)
      transactions.sort((a, b) {
        try {
          final aCreated = a['createdAt'] as Timestamp?;
          final bCreated = b['createdAt'] as Timestamp?;

          if (aCreated != null && bCreated != null) {
            return aCreated.compareTo(bCreated); // Ascending order
          }

          return 0; // Keep original order if no timestamps
        } catch (e) {
          return 0;
        }
      });

      // ✅ CALL generateLedgerPDF WITH isLedgerClosed PARAMETER
      final pdf = PDFExportService.generateLedgerPDF(
        date: widget.date,
        shopName: _selectedShopName ?? 'Shop',
        openingBalance: opening,
        closingBalance: closing,
        saleValue: saleValue,
        transactions: transactions,
        isLedgerClosed: _isLedgerClosed, // ✅ ADD THIS LINE - Pass ledger status
      );

      await _saveAndShowPdf(
        pdf,
        'ledger_${_selectedShopCollection}_$ledgerDate',
      );
    } catch (e) {
      debugPrint('Error generating PDF: $e');
      _showErrorSnackBar('Error generating PDF: $e');
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  Future<void> _downloadExcel(List<QueryDocumentSnapshot> docs) async {
    setState(() => _isDownloading = true);

    try {
      final ledgerDate = DateFormat('dd-MMM-yyyy').format(widget.date);
      final opening = (_ledgerData?['openingBalance'] ?? 0).toDouble();
      final closing = (_ledgerData?['closingBalance'] ?? 0).toDouble();
      final saleValue = (_ledgerData?['saleValue'] ?? 0).toDouble();

      // ✅ Sort transactions by createdAt in memory before passing to export
      final List<Map<String, dynamic>> transactions = docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();

      // Sort transactions chronologically (first added = first shown)
      transactions.sort((a, b) {
        try {
          final aCreated = a['createdAt'] as Timestamp?;
          final bCreated = b['createdAt'] as Timestamp?;

          if (aCreated != null && bCreated != null) {
            return aCreated.compareTo(bCreated); // Ascending order
          }

          return 0; // Keep original order if no timestamps
        } catch (e) {
          return 0;
        }
      });

      // ✅ CALL generateLedgerExcel WITH isLedgerClosed PARAMETER (MATCHING PDF)
      final excelFile = ExcelExportService.generateLedgerExcel(
        date: widget.date,
        shopName: _selectedShopName ?? 'Shop',
        openingBalance: opening,
        closingBalance: closing,
        saleValue: saleValue,
        transactions: transactions,
        isLedgerClosed: _isLedgerClosed, // ✅ ADD THIS LINE - Pass ledger status
      );

      final output = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName =
          'ledger_${_selectedShopCollection}_${ledgerDate}_$timestamp.xlsx';
      final filePath = '${output.path}/$fileName';

      final file = File(filePath);
      await file.writeAsBytes(excelFile.encode()!);
      debugPrint('Excel saved to: $filePath');
      _showFileOptionsDialog(filePath, 'Excel');
    } catch (e) {
      debugPrint('Error generating Excel: $e');
      _showErrorSnackBar('Error generating Excel: $e');
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  void _showFileOptionsDialog(String filePath, String fileType) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                fileType == 'PDF' ? Icons.picture_as_pdf : Icons.table_chart,
                color: fileType == 'PDF' ? Colors.red[600] : Colors.green[600],
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                '$fileType Generated',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'Your ledger $fileType has been generated successfully. What would you like to do?',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _shareFile(filePath, fileType);
              },
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                OpenFile.open(filePath);
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _shareFile(String filePath, String fileType) async {
    try {
      final ledgerDate = DateFormat('dd-MMM-yyyy').format(widget.date);

      if (fileType == 'PDF') {
        final fileName = 'ledger_${_selectedShopName}_$ledgerDate.pdf';
        await Printing.sharePdf(
          bytes: File(filePath).readAsBytesSync(),
          filename: fileName,
        );
      } else if (fileType == 'Excel') {
        final fileName = 'ledger_${_selectedShopName}_$ledgerDate.xlsx';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Excel file: $fileName'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sharing $fileType: $e');
      _showErrorSnackBar('Error sharing $fileType: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  bool _isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = _isLandscape(context);
    final ledgerDate = DateFormat('dd-MMM-yyyy').format(widget.date);
    final opening = (_ledgerData?['openingBalance'] ?? 0).toDouble();

    if (_isLoadingShops) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color(0xFF4285F4),
          foregroundColor: Colors.white,
          title: const Text(
            'Ledger Details',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF4285F4)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ledger Details',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isLandscape ? 20 : 22,
              ),
            ),
            Text(
              'As of Date: $ledgerDate',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white70,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add_circle_outline, size: isLandscape ? 24 : 26),
            tooltip: _isLedgerClosed
                ? "Cannot add - Ledger is closed"
                : "Add Transaction",
            onPressed: _ledgerRef == null ? null : _handleAddTransaction,
            color: _isLedgerClosed
                ? Colors.white.withOpacity(0.4)
                : Colors.white,
          ),
          if (!_isEmployeeLogin)
            IconButton(
              icon: Icon(Icons.lock_outline, size: isLandscape ? 22 : 24),
              tooltip: "Close Ledger",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CloseLedgerScreen(
                      date: widget.date,
                      shopCollection: _selectedShopCollection,
                    ),
                  ),
                ).then((_) {
                  if (mounted) {
                    _fetchLedgerByDate();
                  }
                });
              },
            ),
          SizedBox(width: isLandscape ? 12 : 8),
        ],
      ),
      body: Column(
        children: [
          if (_isLedgerClosed)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(isLandscape ? 10 : 12),
              color: Colors.red[700],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock,
                    color: Colors.white,
                    size: isLandscape ? 18 : 20,
                  ),
                  SizedBox(width: isLandscape ? 6 : 8),
                  Text(
                    'LEDGER CLOSED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isLandscape ? 14 : 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          _isLoading
              ? Container(
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.symmetric(
                    vertical: isLandscape ? 16 : 20,
                    horizontal: 16,
                  ),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 14,
                              width: 80,
                              color: Colors.grey[200],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 22,
                              width: double.infinity,
                              color: Colors.grey[200],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : _buildOpeningBalanceCard(opening),
          Expanded(
            child: _isLoading
                ? _buildProfessionalShimmer(isLandscape)
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _getTransactionsStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildProfessionalShimmer(isLandscape);
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text("Error: ${snapshot.error}"));
                      }

                      final docs = snapshot.data?.docs ?? [];

                      // ✅ Sort transactions in memory to get chronological order (first added = first shown)
                      if (docs.isNotEmpty) {
                        docs.sort((a, b) {
                          try {
                            final aData = a.data();
                            final bData = b.data();
                            final aCreated = aData['createdAt'] as Timestamp?;
                            final bCreated = bData['createdAt'] as Timestamp?;

                            if (aCreated != null && bCreated != null) {
                              return aCreated.compareTo(
                                bCreated,
                              ); // ✅ Ascending order (first added first)
                            }

                            // Fallback to document ID comparison
                            return a.id.compareTo(b.id);
                          } catch (e) {
                            return a.id.compareTo(b.id);
                          }
                        });
                      }

                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: isLandscape ? 56 : 64,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: isLandscape ? 12 : 16),
                              Text(
                                'No transactions found',
                                style: TextStyle(
                                  fontSize: isLandscape ? 16 : 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                              if (!_isLedgerClosed) ...[
                                SizedBox(height: isLandscape ? 6 : 8),
                                Text(
                                  'Tap + to add a transaction',
                                  style: TextStyle(
                                    fontSize: isLandscape ? 13 : 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                if (!_isEmployeeLogin) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Long press transactions to edit/delete (Admin only)',
                                    style: TextStyle(
                                      fontSize: isLandscape ? 12 : 13,
                                      color: Colors.grey[500],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        );
                      }

                      double totalCredit = 0;
                      double totalDebit = 0;

                      for (var d in docs) {
                        final data = d.data();
                        final bool isCredit = data['isCredit'] ?? false;
                        final double amt = (data['amount'] ?? 0).toDouble();
                        if (isCredit) {
                          totalCredit += amt;
                        } else {
                          totalDebit += amt;
                        }
                      }

                      final newClosing = opening + totalCredit - totalDebit;
                      _updateClosingBalance(newClosing);

                      return Container(
                        color: Colors.white,
                        child: ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data();
                            return _buildTransactionItem(
                              context,
                              data,
                              doc,
                              isLandscape,
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getTransactionsStream(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          return FloatingActionButton(
            backgroundColor: const Color(0xFF4285F4),
            onPressed: _isDownloading ? null : () => _showDownloadDialog(docs),
            tooltip: 'Download Report',
            child: _isDownloading
                ? SizedBox(
                    width: isLandscape ? 18 : 20,
                    height: isLandscape ? 18 : 20,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(
                    Icons.download,
                    color: Colors.white,
                    size: isLandscape ? 20 : 22,
                  ),
          );
        },
      ),
    );
  }
}
