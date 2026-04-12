import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'StockItemHistoryPage.dart';
import 'StockEntryPages.dart';

/// Bag denominations (kgs) used in OUT dialog
const List<int> kBagSizes = [30, 26, 10, 5, 1];

class StockTab extends StatefulWidget {
  final String shopCollection;
  final DateTime date;
  final bool isLedgerClosed;
  final bool isEmployeeLogin;
  final DocumentReference<Map<String, dynamic>>? ledgerRef;

  const StockTab({
    super.key,
    required this.shopCollection,
    required this.date,
    required this.isLedgerClosed,
    required this.isEmployeeLogin,
    this.ledgerRef,
  });

  @override
  State<StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<StockTab> {
  bool _isLoading = true;
  bool _isStockClosed = false;
  bool _isClosingStock = false;
  List<QueryDocumentSnapshot> _items = [];
  // itemId -> stock entry data
  final Map<String, Map<String, dynamic>> _stockEntries = {};

  String get _ledgerDate =>
      DateFormat('dd-MMM-yyyy').format(widget.date);

  /// Items sorted by today's sales value descending (highest first).
  List<QueryDocumentSnapshot> get _sortedItems {
    final sorted = List<QueryDocumentSnapshot>.from(_items);
    sorted.sort((a, b) {
      final aSales =
          ((_stockEntries[a.id]?['salesValue']) as num? ?? 0).toDouble();
      final bSales =
          ((_stockEntries[b.id]?['salesValue']) as num? ?? 0).toDouble();
      return bSales.compareTo(aSales);
    });
    return sorted;
  }

  CollectionReference get _itemsCol => FirebaseFirestore.instance
      .collection(widget.shopCollection)
      .doc('items')
      .collection('list');

  DocumentReference get _stockDateDoc => FirebaseFirestore.instance
      .collection(widget.shopCollection)
      .doc('stockLedger')
      .collection('dates')
      .doc(_ledgerDate);

  CollectionReference _stockItemsCol() =>
      _stockDateDoc.collection('items');

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      // Step 1 + 2 in parallel
      final parallel = await Future.wait([
        _stockDateDoc.get(),
        _itemsCol.where('isActive', isEqualTo: true).get(),
      ]);

      final dateDoc = parallel[0] as DocumentSnapshot;
      if (dateDoc.exists) {
        final dateData = dateDoc.data() as Map<String, dynamic>?;
        _isStockClosed = dateData?['isClosed'] ?? false;
      }

      final itemSnap = parallel[1] as QuerySnapshot;
      _items = itemSnap.docs.cast<QueryDocumentSnapshot>();

      // Step 3: fetch all existing entries in parallel
      final entryDocs = await Future.wait(
        _items.map((d) => _stockItemsCol().doc(d.id).get()),
      );

      // Step 4: for missing entries, resolve opening stocks in parallel then write
      final missingItems = <int>[];
      for (int i = 0; i < _items.length; i++) {
        if (entryDocs[i].exists) {
          _stockEntries[_items[i].id] =
              entryDocs[i].data() as Map<String, dynamic>;
        } else {
          missingItems.add(i);
        }
      }

      if (missingItems.isNotEmpty) {
        final openingStocks = await Future.wait(
          missingItems.map((i) => _getOpeningStock(
                _items[i].id,
                _items[i].data() as Map<String, dynamic>,
              )),
        );

        final batch = FirebaseFirestore.instance.batch();
        for (int j = 0; j < missingItems.length; j++) {
          final i = missingItems[j];
          final itemId = _items[i].id;
          final itemData = _items[i].data() as Map<String, dynamic>;
          final openingStock = openingStocks[j];

          final entry = <String, dynamic>{
            'itemId': itemId,
            'itemName': itemData['itemName'] ?? '',
            'price': (itemData['price'] ?? 0).toDouble(),
            'openingStock': openingStock,
            'totalIn': 0.0,
            'totalOut': 0.0,
            'closingStock': openingStock,
            'salesValue': 0.0,
            'isClosed': false,
            'createdAt': FieldValue.serverTimestamp(),
          };

          batch.set(_stockItemsCol().doc(itemId), entry);
          _stockEntries[itemId] = {...entry, 'openingStock': openingStock};
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('StockTab init error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// Find opening stock for today:
  /// - Check yesterday's closing stock (carry forward)
  /// - Fallback to item's default openingStock
  Future<double> _getOpeningStock(
      String itemId, Map<String, dynamic> itemData) async {
    // Fetch last 7 days in parallel (covers most cases)
    const lookback = 7;
    final dates = List.generate(lookback, (i) {
      final d = widget.date.subtract(Duration(days: i + 1));
      return DateFormat('dd-MMM-yyyy').format(d);
    });

    try {
      final docs = await Future.wait(
        dates.map((dateStr) => FirebaseFirestore.instance
            .collection(widget.shopCollection)
            .doc('stockLedger')
            .collection('dates')
            .doc(dateStr)
            .collection('items')
            .doc(itemId)
            .get()),
      );

      // Results are ordered oldest→newest (index 0 = yesterday)
      for (final doc in docs) {
        if (doc.exists) {
          final d = doc.data()!;
          return (d['closingStock'] ?? d['openingStock'] ?? 0).toDouble();
        }
      }
    } catch (_) {}

    // No previous entry — use admin-set default
    return (itemData['openingStock'] ?? 0).toDouble();
  }

  Future<void> _refreshEntry(String itemId) async {
    try {
      final doc = await _stockItemsCol().doc(itemId).get();
      if (doc.exists && mounted) {
        setState(() => _stockEntries[itemId] = doc.data() as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Refresh error: $e');
    }
  }

  // ─── IN Page ────────────────────────────────────────────────────────────
  void _showInDialog(String itemId, String itemName) {
    final entry = _stockEntries[itemId] ?? {};
    Navigator.push<double>(
      context,
      MaterialPageRoute(
        builder: (_) => StockInPage(
          itemName: itemName,
          openingStock: (entry['openingStock'] ?? 0).toDouble(),
          totalIn: (entry['totalIn'] ?? 0).toDouble(),
          totalOut: (entry['totalOut'] ?? 0).toDouble(),
        ),
      ),
    ).then((qty) {
      if (qty != null && qty > 0) _submitIn(itemId, qty);
    });
  }


  Future<void> _submitIn(String itemId, double qty) async {
    try {
      final entry = _stockEntries[itemId] ?? {};
      final currentIn = (entry['totalIn'] ?? 0).toDouble();
      final currentOpening = (entry['openingStock'] ?? 0).toDouble();
      final currentOut = (entry['totalOut'] ?? 0).toDouble();
      final newTotalIn = currentIn + qty;
      final newClosing = currentOpening + newTotalIn - currentOut;

      await _stockItemsCol().doc(itemId).update({
        'totalIn': newTotalIn,
        'closingStock': newClosing,
        'inEntries': FieldValue.arrayUnion([
          {
            'qty': qty,
            'timestamp': DateTime.now().toIso8601String(),
          }
        ]),
      });

      await _refreshEntry(itemId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${NumberFormat('#,##0.##').format(qty)} kgs added to ${ _stockEntries[itemId]?['itemName'] ?? ''}'),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('IN submit error: $e');
    }
  }

  // ─── OUT Page ────────────────────────────────────────────────────────────
  void _showOutDialog(String itemId, String itemName) {
    final entry = _stockEntries[itemId] ?? {};
    final available = (entry['openingStock'] ?? 0).toDouble() +
        (entry['totalIn'] ?? 0).toDouble() -
        (entry['totalOut'] ?? 0).toDouble();

    Navigator.push<StockOutResult>(
      context,
      MaterialPageRoute(
        builder: (_) => StockOutPage(
          itemName: itemName,
          available: available,
          bagSizes: kBagSizes,
        ),
      ),
    ).then((result) {
      if (result != null) {
        _submitOut(itemId, result.totalQty, result.bagEntries);
      }
    });
  }



  Future<void> _submitOut(
      String itemId, double qty, List<Map<String, dynamic>> bagEntries) async {
    try {
      final entry = _stockEntries[itemId] ?? {};
      final price = (entry['price'] ?? 0).toDouble();
      final currentOut = (entry['totalOut'] ?? 0).toDouble();
      final currentOpening = (entry['openingStock'] ?? 0).toDouble();
      final currentIn = (entry['totalIn'] ?? 0).toDouble();
      final newTotalOut = currentOut + qty;
      final newClosing = currentOpening + currentIn - newTotalOut;
      final newSalesValue = newTotalOut * price;

      await _stockItemsCol().doc(itemId).update({
        'totalOut': newTotalOut,
        'closingStock': newClosing,
        'salesValue': newSalesValue,
        'outEntries': FieldValue.arrayUnion([
          {
            'totalQty': qty,
            'bags': bagEntries,
            'timestamp': DateTime.now().toIso8601String(),
          }
        ]),
      });

      await _refreshEntry(itemId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${NumberFormat('#,##0.##').format(qty)} kgs OUT recorded'),
            backgroundColor: Colors.orange[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('OUT submit error: $e');
    }
  }

  // ─── Close Stock ─────────────────────────────────────────────────────────
  Future<void> _closeStock() async {
    // Build summary before showing dialog
    final fmt = NumberFormat('#,##0.##');
    final fmtMoney = NumberFormat('#,##,##0.00');
    double previewTotal = 0;
    final List<Map<String, dynamic>> itemSummary = [];
    for (final itemDoc in _items) {
      final entry = _stockEntries[itemDoc.id] ?? {};
      final name = (entry['itemName'] ?? '') as String;
      final sales = (entry['salesValue'] ?? 0).toDouble();
      final closing = (entry['closingStock'] ?? 0).toDouble();
      previewTotal += sales;
      itemSummary.add({'name': name, 'sales': sales, 'closing': closing});
    }

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: const BoxDecoration(
                color: Color(0xFF1565C0),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Close Stock Ledger',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
                  Text(
                    DateFormat('dd MMM').format(widget.date),
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),

            // ── Summary ──
            Flexible(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Items Summary',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[500])),
                    const SizedBox(height: 8),
                    ...itemSummary.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(item['name'] as String,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black87)),
                              ),
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '₹${fmtMoney.format(item['sales'])}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black87),
                                  ),
                                  Text(
                                    '${fmt.format(item['closing'])} kgs left',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )),
                    Divider(color: Colors.grey[200]),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Sales',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87)),
                        Text(
                          '₹${fmtMoney.format(previewTotal)}',
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1565C0)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Total sales will be auto-filled in Close Ledger. This cannot be undone.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── Actions ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: Text('Cancel',
                          style: TextStyle(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text('Close Stock',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _isClosingStock = true);

    try {
      double totalSalesValue = 0;

      // Mark each item as closed and sum up sales values
      final batch = FirebaseFirestore.instance.batch();

      for (final itemDoc in _items) {
        final itemId = itemDoc.id;
        final entry = _stockEntries[itemId] ?? {};
        final salesValue = (entry['salesValue'] ?? 0).toDouble();
        final closingStock = (entry['closingStock'] ?? 0).toDouble();
        totalSalesValue += salesValue;

        batch.update(_stockItemsCol().doc(itemId), {
          'isClosed': true,
          'closingStock': closingStock,
        });
      }

      // Mark the stock date doc as closed
      batch.set(
        _stockDateDoc,
        {
          'isClosed': true,
          'totalSalesValue': totalSalesValue,
          'closedAt': FieldValue.serverTimestamp(),
          'date': _ledgerDate,
        },
        SetOptions(merge: true),
      );

      // Auto-fill saleValue in the cash ledger document
      if (widget.ledgerRef != null) {
        batch.update(widget.ledgerRef!, {
          'saleValue': totalSalesValue,
        });
      }

      await batch.commit();

      setState(() {
        _isStockClosed = true;
        _isClosingStock = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: Colors.white),
                const SizedBox(width: 8),
                Text(
                    'Stock closed. Sales value ₹${NumberFormat('#,##,##0.00').format(totalSalesValue)} added to ledger.'),
              ],
            ),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Close stock error: $e');
      setState(() => _isClosingStock = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error closing stock: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF4285F4)));
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No active items found',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Add items from Settings → Manage Items',
              style:
                  TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Stock Closed Banner
        if (_isStockClosed)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                vertical: 10, horizontal: 16),
            color: Colors.orange[700],
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'STOCK CLOSED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),

        // Items List
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              14,
              14,
              14,
              (_isStockClosed || widget.isLedgerClosed)
                  ? 14 + MediaQuery.of(context).viewPadding.bottom
                  : 14,
            ),
            itemCount: _sortedItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final itemDoc = _sortedItems[index];
              final itemId = itemDoc.id;
              final entry = _stockEntries[itemId] ?? {};

              final itemName = entry['itemName'] ?? '';
              final price = (entry['price'] ?? 0).toDouble();
              final openingStock = (entry['openingStock'] ?? 0).toDouble();
              final totalIn = (entry['totalIn'] ?? 0).toDouble();
              final totalOut = (entry['totalOut'] ?? 0).toDouble();
              final currentStock =
                  (entry['closingStock'] ?? openingStock).toDouble();
              final salesValue = (entry['salesValue'] ?? 0).toDouble();
              final fmt = NumberFormat('#,##0.##');
              final fmtMoney = NumberFormat('#,##,##0.00');
              final isLowStock = currentStock > 0 && currentStock < 30;
              final isOutOfStock = currentStock <= 0;
              final bagTotals = _aggregateBags(itemId);
              final bagEntries = kBagSizes
                  .where((s) => bagTotals.containsKey(s))
                  .map((s) => '${s}kg × ${bagTotals[s]}')
                  .toList();

              // Left border color: red only for out-of-stock, blue otherwise
              final accentColor = isOutOfStock
                  ? const Color(0xFFD32F2F)
                  : const Color(0xFF1565C0);

              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StockItemHistoryPage(
                      shopCollection: widget.shopCollection,
                      itemId: itemId,
                      itemName: itemName,
                      price: price,
                      currentDate: widget.date,
                    ),
                  ),
                ),
                onLongPress: () => _showStockLogBottomSheet(
                  itemId: itemId,
                  itemName: itemName,
                  price: price,
                  entry: entry,
                  fmt: fmt,
                  fmtMoney: fmtMoney,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                      left: BorderSide(color: accentColor, width: 4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Item name + sales amount ──
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    itemName,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₹${fmtMoney.format(price)} per kg',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Sales',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500])),
                                const SizedBox(height: 2),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 150),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      '₹${fmtMoney.format(salesValue)}',
                                      style: TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        color: salesValue > 0
                                            ? Colors.black87
                                            : Colors.grey[400],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        Divider(height: 1, color: Colors.grey[200]),
                        const SizedBox(height: 10),

                        // ── Stats row ──
                        Row(
                          children: [
                            _statCol('Opening',
                                '${fmt.format(openingStock)} kgs',
                                Colors.black87),
                            _vertDivider(),
                            _statCol(
                                'IN', '+${fmt.format(totalIn)} kgs',
                                Colors.black87),
                            _vertDivider(),
                            _statCol(
                                'OUT', '-${fmt.format(totalOut)} kgs',
                                Colors.black87),
                            _vertDivider(),
                            _statCol(
                                'Current',
                                '${fmt.format(currentStock)} kgs',
                                accentColor,
                                bold: true),
                          ],
                        ),

                        // ── Warning ──
                        if (isOutOfStock || isLowStock) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  size: 13,
                                  color: isOutOfStock
                                      ? const Color(0xFFD32F2F)
                                      : Colors.grey[700]),
                              const SizedBox(width: 5),
                              Text(
                                isOutOfStock
                                    ? 'Out of stock'
                                    : 'Low stock — less than 1 bag left',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isOutOfStock
                                      ? const Color(0xFFD32F2F)
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ],

                        // ── Bags sold ──
                        if (bagEntries.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.shopping_bag_outlined,
                                  size: 13, color: Colors.grey[500]),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  'Bags:  ${bagEntries.join('  ·  ')}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600]),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 12),
                        Divider(height: 1, color: Colors.grey[200]),
                            const SizedBox(height: 8),

                            // ── Gesture hints ──
                            Row(
                              children: [
                                Icon(Icons.touch_app_outlined,
                                    size: 11, color: Colors.grey[400]),
                                const SizedBox(width: 3),
                                Text('Hold for log',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[400])),
                                const Spacer(),
                                Icon(Icons.history,
                                    size: 11, color: Colors.grey[400]),
                                const SizedBox(width: 3),
                                Text('Tap for history',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[400])),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // ── Action buttons ──
                            if (!_isStockClosed && !widget.isLedgerClosed)
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () =>
                                          _showInDialog(itemId, itemName),
                                      icon: const Icon(
                                          Icons.add_circle_outline,
                                          size: 16,
                                          color: Colors.white),
                                      label: const Text('IN',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF2E7D32),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 11),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(9)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () =>
                                          _showOutDialog(itemId, itemName),
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          size: 16,
                                          color: Colors.white),
                                      label: const Text('OUT',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF1976D2),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 11),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(9)),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.lock_outline,
                                        size: 14, color: Colors.grey[400]),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isStockClosed
                                          ? 'Stock Closed'
                                          : 'Ledger Closed',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[500],
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                ),
              ); // GestureDetector
            },
          ),
        ),

        // Close Stock Button
        if (!_isStockClosed && !widget.isLedgerClosed)
          Padding(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    _isClosingStock ? null : _closeStock,
                icon: _isClosingStock
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                    : const Icon(Icons.lock_outline,
                        color: Colors.white),
                label: Text(
                  _isClosingStock
                      ? 'Closing Stock...'
                      : 'Close Stock Ledger',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Stock Log Bottom Sheet ─────────────────────────────────────────────
  void _showStockLogBottomSheet({
    required String itemId,
    required String itemName,
    required double price,
    required Map<String, dynamic> entry,
    required NumberFormat fmt,
    required NumberFormat fmtMoney,
  }) {
    final inEntries = (entry['inEntries'] as List<dynamic>?) ?? [];
    final outEntries = (entry['outEntries'] as List<dynamic>?) ?? [];
    final totalIn = (entry['totalIn'] ?? 0).toDouble();
    final totalOut = (entry['totalOut'] ?? 0).toDouble();
    final salesValue = (entry['salesValue'] ?? 0).toDouble();

    String formatTime(String? ts) {
      if (ts == null) return '';
      try {
        return DateFormat('hh:mm a').format(DateTime.parse(ts).toLocal());
      } catch (_) {
        return '';
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // ── Drag handle ──
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Header ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1976D2), Color(0xFF4285F4)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.inventory_2_outlined,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                itemName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                '₹${fmtMoney.format(price)} per kg  •  ${DateFormat('dd MMM yyyy').format(widget.date)}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(Icons.close,
                              color: Colors.grey[500], size: 22),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Summary strip ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F6FA),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          _summaryChip(
                              'Total IN',
                              '+${fmt.format(totalIn)} kgs',
                              Colors.green[700]!,
                              Colors.green[50]!),
                          const SizedBox(width: 10),
                          _summaryChip(
                              'Total OUT',
                              '-${fmt.format(totalOut)} kgs',
                              Colors.orange[700]!,
                              Colors.orange[50]!),
                          const SizedBox(width: 10),
                          _summaryChip(
                              'Sales',
                              '₹${fmtMoney.format(salesValue)}',
                              Colors.blue[700]!,
                              Colors.blue[50]!),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),
                  Divider(color: Colors.grey[200], height: 1),

                  // ── Scrollable log ──
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        // IN section
                        _logSectionHeader(
                          Icons.add_circle_outline,
                          'Stock IN Entries',
                          Colors.green[700]!,
                          inEntries.length,
                        ),
                        const SizedBox(height: 10),
                        if (inEntries.isEmpty)
                          _emptyLogRow('No stock received today', Colors.green[300]!)
                        else
                          ...inEntries.asMap().entries.map((e) {
                            final qty =
                                (e.value['qty'] as num?)?.toDouble() ?? 0;
                            final ts = e.value['timestamp'] as String?;
                            final timeStr = formatTime(ts);
                            return _logRow(
                              index: e.key + 1,
                              isIn: true,
                              mainText: '+${fmt.format(qty)} kgs received',
                              subText: timeStr.isNotEmpty ? timeStr : null,
                              color: Colors.green[700]!,
                              bgColor: Colors.green[50]!,
                              borderColor: Colors.green[100]!,
                            );
                          }),

                        const SizedBox(height: 20),

                        // OUT section
                        _logSectionHeader(
                          Icons.remove_circle_outline,
                          'Stock OUT Entries',
                          Colors.orange[700]!,
                          outEntries.length,
                        ),
                        const SizedBox(height: 10),
                        if (outEntries.isEmpty)
                          _emptyLogRow('No stock sold today', Colors.orange[300]!)
                        else
                          ...outEntries.asMap().entries.map((e) {
                            final totalQty =
                                (e.value['totalQty'] as num?)?.toDouble() ?? 0;
                            final bags =
                                e.value['bags'] as List<dynamic>? ?? [];
                            final ts = e.value['timestamp'] as String?;
                            final timeStr = formatTime(ts);
                            final bagStr = bags
                                .map((b) =>
                                    '${b['bagSize']}kg × ${b['bags']} bag${(b['bags'] as int? ?? 0) > 1 ? 's' : ''}')
                                .join('  •  ');
                            return _logRow(
                              index: e.key + 1,
                              isIn: false,
                              mainText: '-${fmt.format(totalQty)} kgs sold',
                              subText: bagStr.isNotEmpty ? bagStr : null,
                              timeText: timeStr.isNotEmpty ? timeStr : null,
                              color: Colors.orange[700]!,
                              bgColor: Colors.orange[50]!,
                              borderColor: Colors.orange[100]!,
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _summaryChip(
      String label, String value, Color textColor, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textColor)),
          ],
        ),
      ),
    );
  }

  Widget _logSectionHeader(
      IconData icon, String title, Color color, int count) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black87)),
        const Spacer(),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('$count entr${count == 1 ? 'y' : 'ies'}',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ),
      ],
    );
  }

  Widget _emptyLogRow(String message, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Center(
        child: Text(message,
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey[400],
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _logRow({
    required int index,
    required bool isIn,
    required String mainText,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    String? subText,
    String? timeText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot + line
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: color),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        mainText,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: color),
                      ),
                      if (timeText != null || subText == null)
                        Text(
                          timeText ?? '',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                  if (subText != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subText,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (timeText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        timeText,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Aggregates total bags sold per bag size from all outEntries
  Map<int, int> _aggregateBags(String itemId) {
    final entry = _stockEntries[itemId] ?? {};
    final outEntries = entry['outEntries'] as List<dynamic>? ?? [];
    final Map<int, int> totals = {};
    for (final out in outEntries) {
      final bags = out['bags'] as List<dynamic>? ?? [];
      for (final b in bags) {
        final size = (b['bagSize'] as num?)?.toInt() ?? 0;
        final count = (b['bags'] as num?)?.toInt() ?? 0;
        if (size > 0 && count > 0) {
          totals[size] = (totals[size] ?? 0) + count;
        }
      }
    }
    return totals;
  }

  Widget _statCol(String label, String value, Color color,
      {bool bold = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _vertDivider() {
    return Container(
      width: 1,
      height: 32,
      color: Colors.grey[200],
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _statBox(
      String label, String value, Color textColor, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: textColor.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: textColor)),
          ],
        ),
      ),
    );
  }
}
