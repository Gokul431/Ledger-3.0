import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'StockEntryPages.dart';

/// Bag denominations (kgs) used in the Closing Stock (OUT) dialog
const List<int> kClosingStockBagSizes = [75, 26, 10, 5, 1];

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
  // cached bag aggregates per itemId
  final Map<String, Map<int, double>> _bagCache = {};
  // stable sorted list — rebuilt only when _stockEntries changes
  List<QueryDocumentSnapshot> _cachedSorted = [];

  // Formatters created once
  final _fmt = NumberFormat('#,##0.##');
  final _fmtMoney = NumberFormat('#,##,##0.00');

  String get _ledgerDate => DateFormat('dd-MMM-yyyy').format(widget.date);

  /// Rebuild cached sorted list — call after any _stockEntries change.
  void _rebuildSorted() {
    _cachedSorted = List<QueryDocumentSnapshot>.from(_items);
    _cachedSorted.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;
      final aId = int.tryParse(aData['itemId']?.toString() ?? '') ?? 999999;
      final bId = int.tryParse(bData['itemId']?.toString() ?? '') ?? 999999;
      return aId.compareTo(bId);
    });
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

  CollectionReference _stockItemsCol() => _stockDateDoc.collection('items');

  CollectionReference _stockItemsColForDate(String dateStr) => FirebaseFirestore
      .instance
      .collection(widget.shopCollection)
      .doc('stockLedger')
      .collection('dates')
      .doc(dateStr)
      .collection('items');

  /// After an item's closing stock changes for [fromDate] (via an IN entry,
  /// a closing-stock edit, a load edit, or a delete), propagate the new
  /// value forward as the opening stock of any later day that was already
  /// created (e.g. by opening the app on that day before this edit was
  /// made).
  ///
  /// A later day that hasn't been closed yet (no outEntries) just gets its
  /// closingStock recomputed as opening + totalIn. But a later day that was
  /// ALREADY closed has a physically-measured closing amount (outEntries'
  /// closingQty) that must NOT change just because an earlier day's opening
  /// was corrected — only the derived sold qty / sales value (which depend
  /// on opening) get recalculated, and that day's sales totals are resynced.
  ///
  /// Finally syncs the item's master doc with the closing stock of the most
  /// recent day actually touched, so a correction to an old day doesn't
  /// leave later days — or the master's own carry-forward value — out of
  /// sync.
  Future<void> _cascadeClosingForward(
    String itemId,
    DateTime fromDate,
    double closing,
  ) async {
    DateTime cursorDate = fromDate;
    double cursorValue = closing;

    while (true) {
      final nextDate = cursorDate.add(const Duration(days: 1));
      final nextDateStr = DateFormat('dd-MMM-yyyy').format(nextDate);
      final nextItemsCol = _stockItemsColForDate(nextDateStr);
      final nextRef = nextItemsCol.doc(itemId);

      final snap = await nextRef.get();
      if (!snap.exists) break;

      final d = snap.data() as Map<String, dynamic>;
      final oldOpening = (d['openingStock'] ?? 0).toDouble();
      if (oldOpening == cursorValue) break; // downstream already in sync

      final totalIn = (d['totalIn'] ?? 0).toDouble();
      final outEntries = d['outEntries'] as List<dynamic>? ?? [];
      final updates = <String, dynamic>{'openingStock': cursorValue};
      double newValue;

      if (outEntries.isNotEmpty) {
        final price = (d['price'] ?? 0).toDouble();
        final lastOut = outEntries.last as Map<String, dynamic>;
        final measuredClosing = (lastOut['closingQty'] ?? 0).toDouble();
        final newTotalOut = (cursorValue + totalIn - measuredClosing).clamp(
          0.0,
          double.infinity,
        );
        final newSalesValue = newTotalOut * price;
        updates['totalOut'] = newTotalOut;
        updates['salesValue'] = newSalesValue;
        updates['closingStock'] = measuredClosing;
        newValue = measuredClosing;

        await nextRef.update(updates);
        await _resyncDayTotals(nextDateStr, nextItemsCol);
      } else {
        newValue = cursorValue + totalIn; // totalOut is always 0 here
        updates['closingStock'] = newValue;
        await nextRef.update(updates);
      }

      cursorDate = nextDate;
      cursorValue = newValue;
    }

    final masterRef = _itemMasterRef(itemId);
    if (masterRef != null) {
      await masterRef.update({
        'lastClosingStock': cursorValue,
        'lastClosingDate': Timestamp.fromDate(cursorDate),
      });
    }
  }

  /// Recomputes a date's total sales from its item docs and syncs it to the
  /// stockLedger date doc and that date's ledger doc (if one exists).
  Future<void> _resyncDayTotals(
    String dateStr,
    CollectionReference itemsCol,
  ) async {
    final itemDocs = await itemsCol.get();
    double total = 0;
    for (final doc in itemDocs.docs) {
      final data = doc.data() as Map<String, dynamic>;
      total += (data['salesValue'] ?? 0).toDouble();
    }

    final dateDocRef = FirebaseFirestore.instance
        .collection(widget.shopCollection)
        .doc('stockLedger')
        .collection('dates')
        .doc(dateStr);
    await dateDocRef.set({'totalSalesValue': total}, SetOptions(merge: true));

    final ledgerQuery = await FirebaseFirestore.instance
        .collection(widget.shopCollection)
        .doc('ledgers')
        .collection('dates')
        .where('ledgerDate', isEqualTo: dateStr)
        .limit(1)
        .get();
    if (ledgerQuery.docs.isNotEmpty) {
      await ledgerQuery.docs.first.reference.set({
        'saleValue': total,
      }, SetOptions(merge: true));
    }
  }

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
      final allItems = itemSnap.docs.cast<QueryDocumentSnapshot>();

      // Show items from their openingStockDate onward — once an item starts,
      // it stays on every later ledger day (carried forward), not just its first day.
      final startOfDay = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day,
      );
      final endOfDay = startOfDay.add(const Duration(days: 1));
      _items = allItems.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = data['openingStockDate'] as Timestamp?;
        if (ts == null) return false;
        final d = ts.toDate();
        return d.isBefore(endOfDay);
      }).toList();

      // Step 3: fetch all existing entries using user-defined itemId as key
      final entryDocs = await Future.wait(
        _items.map((d) => _stockItemsCol().doc(_itemStockKey(d)).get()),
      );

      // Step 4: for missing entries, resolve opening stocks in parallel then write
      final missingItems = <int>[];
      for (int i = 0; i < _items.length; i++) {
        if (entryDocs[i].exists) {
          _stockEntries[_itemStockKey(_items[i])] =
              entryDocs[i].data() as Map<String, dynamic>;
        } else {
          missingItems.add(i);
        }
      }

      if (missingItems.isNotEmpty) {
        final openingStocks = await Future.wait(
          missingItems.map(
            (i) => _getOpeningStock(
              _itemStockKey(_items[i]),
              _items[i].data() as Map<String, dynamic>,
            ),
          ),
        );

        final batch = FirebaseFirestore.instance.batch();
        for (int j = 0; j < missingItems.length; j++) {
          final i = missingItems[j];
          final stockKey = _itemStockKey(_items[i]);
          final itemData = _items[i].data() as Map<String, dynamic>;
          final openingStock = openingStocks[j];

          final entry = <String, dynamic>{
            'itemId': stockKey,
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

          batch.set(_stockItemsCol().doc(stockKey), entry);
          _stockEntries[stockKey] = {...entry, 'openingStock': openingStock};
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('StockTab init error: $e');
    }
    if (mounted) {
      setState(() {
        _rebuildSorted();
        _isLoading = false;
      });
    }
  }

  /// Find opening stock for today:
  /// - Check yesterday's closing stock (carry forward)
  /// - Fallback to item's default openingStock
  Future<double> _getOpeningStock(
    String itemId,
    Map<String, dynamic> itemData,
  ) async {
    // Fetch last 7 days in parallel (covers most cases)
    const lookback = 7;
    final dates = List.generate(lookback, (i) {
      final d = widget.date.subtract(Duration(days: i + 1));
      return DateFormat('dd-MMM-yyyy').format(d);
    });

    try {
      final docs = await Future.wait(
        dates.map(
          (dateStr) => FirebaseFirestore.instance
              .collection(widget.shopCollection)
              .doc('stockLedger')
              .collection('dates')
              .doc(dateStr)
              .collection('items')
              .doc(itemId)
              .get(),
        ),
      );

      // Results are ordered oldest→newest (index 0 = yesterday)
      for (final doc in docs) {
        if (doc.exists) {
          final d = doc.data()!;
          return (d['closingStock'] ?? d['openingStock'] ?? 0).toDouble();
        }
      }
    } catch (_) {}

    // No entry within the last 7 days (e.g. shop was closed for longer) —
    // fall back to the item's denormalized last known closing stock, which
    // has no lookback limit, before finally using the admin-set default.
    return (itemData['lastClosingStock'] ?? itemData['openingStock'] ?? 0)
        .toDouble();
  }

  /// Firestore reference for an item's master doc, looked up by its stock key.
  DocumentReference? _itemMasterRef(String stockKey) {
    for (final doc in _items) {
      if (_itemStockKey(doc) == stockKey) return doc.reference;
    }
    return null;
  }

  /// Master doc data for an item, looked up by its stock key.
  Map<String, dynamic>? _itemMasterData(String stockKey) {
    for (final doc in _items) {
      if (_itemStockKey(doc) == stockKey)
        return doc.data() as Map<String, dynamic>;
    }
    return null;
  }

  /// Bag denominations configured on the item itself (set on Add/Edit Item).
  /// Falls back to [fallback] for items that predate this feature.
  List<int> _bagSizesFor(String stockKey, List<int> fallback) {
    final raw = _itemMasterData(stockKey)?['bagSizes'] as List<dynamic>?;
    if (raw == null || raw.isEmpty) return fallback;
    return raw.map((e) => (e as num).toInt()).toList();
  }

  Future<void> _refreshEntry(String itemId) async {
    try {
      final doc = await _stockItemsCol().doc(itemId).get();
      if (doc.exists && mounted) {
        setState(() {
          _stockEntries[itemId] = doc.data() as Map<String, dynamic>;
          _bagCache.remove(itemId);
          _rebuildSorted();
        });
      }
    } catch (e) {
      debugPrint('Refresh error: $e');
    }
  }

  /// Stable key for a stock entry: uses the user-defined itemId field so the
  /// same physical item carries its closing stock forward across dates.
  String _itemStockKey(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final id = (data['itemId'] ?? '').toString().trim();
    return id.isNotEmpty ? id : doc.id;
  }

  Map<int, double> _aggregateBags(String itemId) {
    if (_bagCache.containsKey(itemId)) return _bagCache[itemId]!;
    final entry = _stockEntries[itemId] ?? {};
    final outEntries = entry['outEntries'] as List<dynamic>? ?? [];
    final Map<int, double> totals = {};
    for (final out in outEntries) {
      final bags = out['bags'] as List<dynamic>? ?? [];
      for (final b in bags) {
        final size = (b['bagSize'] as num?)?.toInt() ?? 0;
        final count = (b['bags'] as num?)?.toDouble() ?? 0;
        if (size > 0 && count > 0) {
          totals[size] = (totals[size] ?? 0) + count;
        }
      }
    }
    _bagCache[itemId] = totals;
    return totals;
  }

  // ─── IN Page ────────────────────────────────────────────────────────────
  void _showInDialog(String itemId, String itemName) {
    final entry = _stockEntries[itemId] ?? {};
    Navigator.push<StockInResult>(
      context,
      MaterialPageRoute(
        builder: (_) => StockInPage(
          itemName: itemName,
          openingStock: (entry['openingStock'] ?? 0).toDouble(),
          totalIn: (entry['totalIn'] ?? 0).toDouble(),
          totalOut: (entry['totalOut'] ?? 0).toDouble(),
          bagSizes: _bagSizesFor(itemId, kNewStockBagSizes),
          price: (entry['price'] ?? 0).toDouble(),
        ),
      ),
    ).then((result) {
      if (result != null && result.totalQty > 0) {
        _submitIn(itemId, result);
      }
    });
  }

  Future<void> _submitIn(String itemId, StockInResult result) async {
    final qty = result.totalQty;
    try {
      final entry = _stockEntries[itemId] ?? {};
      final currentIn = (entry['totalIn'] ?? 0).toDouble();
      final currentOpening = (entry['openingStock'] ?? 0).toDouble();
      final currentOut = (entry['totalOut'] ?? 0).toDouble();
      final newTotalIn = currentIn + qty;
      final newClosing = currentOpening + newTotalIn - currentOut;

      final batch = FirebaseFirestore.instance.batch();
      batch.update(_stockItemsCol().doc(itemId), {
        'totalIn': newTotalIn,
        'closingStock': newClosing,
        'inEntries': FieldValue.arrayUnion([
          {
            'qty': qty,
            'bags': result.bagEntries,
            'timestamp': DateTime.now().toIso8601String(),
          },
        ]),
      });
      await batch.commit();
      await _cascadeClosingForward(itemId, widget.date, newClosing);

      await _refreshEntry(itemId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${NumberFormat('#,##0.##').format(qty)} kgs added to ${_stockEntries[itemId]?['itemName'] ?? ''}',
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('IN submit error: $e');
    }
  }

  // ─── OUT Page (records Closing Stock; Sold is derived) ──────────────────
  void _showOutDialog(String itemId, String itemName) {
    final entry = _stockEntries[itemId] ?? {};
    final available =
        (entry['openingStock'] ?? 0).toDouble() +
        (entry['totalIn'] ?? 0).toDouble();
    final price = (entry['price'] ?? 0).toDouble();

    Navigator.push<StockOutResult>(
      context,
      MaterialPageRoute(
        builder: (_) => StockOutPage(
          itemName: itemName,
          available: available,
          bagSizes: _bagSizesFor(itemId, kClosingStockBagSizes),
          price: price,
        ),
      ),
    ).then((result) {
      if (result != null) {
        _recordClosingStock(itemId, result);
      }
    });
  }

  /// Stores the entered Closing Stock directly, then derives:
  ///   Sold = (Opening + New Stock) − Closing Stock
  ///   Sales Value = Sold × Price
  Future<void> _recordClosingStock(String itemId, StockOutResult result) async {
    try {
      final entry = _stockEntries[itemId] ?? {};
      final price = (entry['price'] ?? 0).toDouble();
      final opening = (entry['openingStock'] ?? 0).toDouble();
      final totalIn = (entry['totalIn'] ?? 0).toDouble();
      final available = opening + totalIn;
      final newClosing = result.totalQty.clamp(0.0, available).toDouble();
      final newTotalOut = available - newClosing;
      final newSalesValue = newTotalOut * price;

      final batch = FirebaseFirestore.instance.batch();

      batch.update(_stockItemsCol().doc(itemId), {
        'outEntries': [
          {
            'closingQty': newClosing,
            'soldQty': newTotalOut,
            'bags': result.bagEntries,
            'timestamp': DateTime.now().toIso8601String(),
          },
        ],
        'totalOut': newTotalOut,
        'closingStock': newClosing,
        'salesValue': newSalesValue,
      });

      // Recalculate total sales across all items and sync to ledger doc
      double newTotalSales = newSalesValue;
      for (final itemDoc in _items) {
        final key = _itemStockKey(itemDoc);
        if (key == itemId) continue;
        final e = _stockEntries[key] ?? {};
        newTotalSales += (e['salesValue'] ?? 0).toDouble();
      }

      batch.set(
        _stockDateDoc as DocumentReference<Map<String, dynamic>>,
        {'totalSalesValue': newTotalSales},
        SetOptions(merge: true),
      );

      if (widget.ledgerRef != null) {
        batch.set(widget.ledgerRef!, {
          'saleValue': newTotalSales,
        }, SetOptions(merge: true));
      }

      await batch.commit();
      await _cascadeClosingForward(itemId, widget.date, newClosing);
      _bagCache.remove(itemId);
      await _refreshEntry(itemId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Closing stock saved — ${NumberFormat('#,##0.##').format(newClosing)} kg left, sales ₹${NumberFormat('#,##,##0.00').format(newTotalSales)}',
            ),
            backgroundColor: Colors.orange[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Closing stock update error: $e');
    }
  }

  // ─── Update load entry (edit existing NS row) ────────────────────────────
  Future<void> _updateLoadEntry(
    String itemId,
    int loadIndex,
    StockInResult result,
  ) async {
    try {
      final entry = _stockEntries[itemId] ?? {};
      final inEntries = List<dynamic>.from(
        entry['inEntries'] as List<dynamic>? ?? [],
      );
      if (loadIndex >= inEntries.length) return;

      final oldQty = (inEntries[loadIndex]['qty'] as num?)?.toDouble() ?? 0;
      inEntries[loadIndex] = {
        'qty': result.totalQty,
        'bags': result.bagEntries,
        'timestamp':
            inEntries[loadIndex]['timestamp'] ??
            DateTime.now().toIso8601String(),
      };

      final opening = (entry['openingStock'] ?? 0).toDouble();
      final currentTotalIn = (entry['totalIn'] ?? 0).toDouble();
      final newTotalIn = currentTotalIn - oldQty + result.totalQty;
      final totalOut = (entry['totalOut'] ?? 0).toDouble();
      final newClosing = opening + newTotalIn - totalOut;

      final batch = FirebaseFirestore.instance.batch();
      batch.update(_stockItemsCol().doc(itemId), {
        'inEntries': inEntries,
        'totalIn': newTotalIn,
        'closingStock': newClosing,
      });
      await batch.commit();
      await _cascadeClosingForward(itemId, widget.date, newClosing);
      await _refreshEntry(itemId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Load ${loadIndex + 1} updated'),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Update load error: $e');
    }
  }

  // ─── Delete entries (admin only) ─────────────────────────────────────────
  Future<bool> _confirmDelete(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(
                color: Colors.red[700],
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteLoadEntry(String itemId, int loadIndex) async {
    final confirmed = await _confirmDelete(
      'Delete load?',
      'This will remove this New Stock entry and recalculate the closing stock.',
    );
    if (!confirmed) return;

    try {
      final entry = _stockEntries[itemId] ?? {};
      final inEntries = List<dynamic>.from(
        entry['inEntries'] as List<dynamic>? ?? [],
      );
      if (loadIndex >= inEntries.length) return;

      final removedQty = (inEntries[loadIndex]['qty'] as num?)?.toDouble() ?? 0;
      inEntries.removeAt(loadIndex);

      final opening = (entry['openingStock'] ?? 0).toDouble();
      final currentTotalIn = (entry['totalIn'] ?? 0).toDouble();
      final newTotalIn = currentTotalIn - removedQty;
      final totalOut = (entry['totalOut'] ?? 0).toDouble();
      final newClosing = opening + newTotalIn - totalOut;

      await _stockItemsCol().doc(itemId).update({
        'inEntries': inEntries,
        'totalIn': newTotalIn,
        'closingStock': newClosing,
      });
      await _cascadeClosingForward(itemId, widget.date, newClosing);
      await _refreshEntry(itemId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Load entry deleted'),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Delete load error: $e');
    }
  }

  Future<void> _deleteClosingEntry(String itemId) async {
    final confirmed = await _confirmDelete(
      'Delete closing stock?',
      'This will remove today\'s closing stock and sales for this item, and re-open it for entry.',
    );
    if (!confirmed) return;

    try {
      final entry = _stockEntries[itemId] ?? {};
      final opening = (entry['openingStock'] ?? 0).toDouble();
      final totalIn = (entry['totalIn'] ?? 0).toDouble();
      final newClosing = opening + totalIn;

      final batch = FirebaseFirestore.instance.batch();
      batch.update(_stockItemsCol().doc(itemId), {
        'outEntries': [],
        'totalOut': 0,
        'closingStock': newClosing,
        'salesValue': 0,
      });

      // Recalculate total sales across all items (this item's contributes 0 now)
      double newTotalSales = 0;
      for (final itemDoc in _items) {
        final key = _itemStockKey(itemDoc);
        if (key == itemId) continue;
        final e = _stockEntries[key] ?? {};
        newTotalSales += (e['salesValue'] ?? 0).toDouble();
      }

      batch.set(
        _stockDateDoc as DocumentReference<Map<String, dynamic>>,
        {'totalSalesValue': newTotalSales},
        SetOptions(merge: true),
      );

      if (widget.ledgerRef != null) {
        batch.set(widget.ledgerRef!, {
          'saleValue': newTotalSales,
        }, SetOptions(merge: true));
      }

      await batch.commit();
      await _cascadeClosingForward(itemId, widget.date, newClosing);
      _bagCache.remove(itemId);
      await _refreshEntry(itemId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Closing stock entry deleted'),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Delete closing error: $e');
    }
  }

  // ─── Close Stock ─────────────────────────────────────────────────────────
  Future<void> _closeStock() async {
    // Build summary before showing dialog
    double previewTotal = 0;
    final List<Map<String, dynamic>> itemSummary = [];
    for (final itemDoc in _items) {
      final entry = _stockEntries[_itemStockKey(itemDoc)] ?? {};
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
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: const BoxDecoration(
                color: Color(0xFF455A64),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Close Stock Ledger',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    DateFormat('dd MMM').format(widget.date),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),

            // ── Summary ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Items Summary',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...itemSummary.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item['name'] as String,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₹${_fmtMoney.format(item['sales'])}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                Text(
                                  '${_fmt.format(item['closing'])} kgs left',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(color: Colors.grey[200]),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Sales',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          '₹${_fmtMoney.format(previewTotal)}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF455A64),
                          ),
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
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Total sales will be auto-filled in Close Ledger. This cannot be undone.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
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
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF455A64),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Close Stock',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
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
        final itemId = _itemStockKey(itemDoc);
        final entry = _stockEntries[itemId] ?? {};
        final salesValue = (entry['salesValue'] ?? 0).toDouble();
        final closingStock = (entry['closingStock'] ?? 0).toDouble();
        totalSalesValue += salesValue;

        batch.update(_stockItemsCol().doc(itemId), {
          'isClosed': true,
          'closingStock': closingStock,
        });
        batch.update(itemDoc.reference, {
          'lastClosingStock': closingStock,
          'lastClosingDate': Timestamp.fromDate(widget.date),
        });
      }

      // Mark the stock date doc as closed
      batch.set(_stockDateDoc, {
        'isClosed': true,
        'totalSalesValue': totalSalesValue,
        'closedAt': FieldValue.serverTimestamp(),
        'date': _ledgerDate,
      }, SetOptions(merge: true));

      // Auto-fill saleValue in the cash ledger document
      if (widget.ledgerRef != null) {
        batch.update(widget.ledgerRef!, {'saleValue': totalSalesValue});
      }

      await batch.commit();

      setState(() {
        _isStockClosed = true;
        _isClosingStock = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock closed'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
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
      return Shimmer.fromColors(
        baseColor: Colors.grey[200]!,
        highlightColor: Colors.grey[50]!,
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: 6,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Colors.white),
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 130,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 70,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: 90,
                  height: 11,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: List.generate(
                    4,
                    (i) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i < 3 ? 8 : 0),
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No active items found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add items from Settings → Manage Items',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    // Capped to a comfortable reading width and centered — a no-op on
    // phones (narrower than the cap), but keeps item cards (with their
    // 4-column stats grid) from stretching edge-to-edge on tablets.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          children: [
            // Stock Closed Banner
            if (_isStockClosed)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 11,
                  horizontal: 16,
                ),
                color: const Color(0xFFE67E22), // More saturated orange
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock, color: Colors.white, size: 16),
                    SizedBox(width: 10),
                    Text(
                      'STOCK CLOSED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

            // Items List
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.only(
                  bottom: (_isStockClosed || widget.isLedgerClosed)
                      ? MediaQuery.of(context).viewPadding.bottom
                      : 0,
                ),
                itemCount: _cachedSorted.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.grey.shade200,
                ),
                itemBuilder: (context, index) {
                  final itemDoc = _cachedSorted[index];
                  final itemId = _itemStockKey(itemDoc);
                  final entry = _stockEntries[itemId] ?? {};

                  final itemName = entry['itemName'] ?? '';
                  final itemDisplayId = itemId;
                  final price = (entry['price'] ?? 0).toDouble();
                  final openingStock = (entry['openingStock'] ?? 0).toDouble();
                  final totalIn = (entry['totalIn'] ?? 0).toDouble();
                  final totalOut = (entry['totalOut'] ?? 0).toDouble();
                  final currentStock = (entry['closingStock'] ?? openingStock)
                      .toDouble();
                  final salesValue = (entry['salesValue'] ?? 0).toDouble();
                  final isLowStock = currentStock > 0 && currentStock < 1;
                  final isOutOfStock = currentStock <= 0;
                  final inEntries =
                      (entry['inEntries'] as List<dynamic>?) ?? [];

                  return GestureDetector(
                    onLongPress: () => _showStockLogBottomSheet(
                      itemId: itemId,
                      itemName: itemName,
                      price: price,
                      entry: entry,
                      fmt: _fmt,
                      fmtMoney: _fmtMoney,
                    ),
                    child: Container(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Header: id badge + name + price + today's sales ──
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (itemDisplayId.isNotEmpty) ...[
                                  Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF3B6CE0),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      int.tryParse(
                                            itemDisplayId,
                                          )?.toString().padLeft(2, '0') ??
                                          itemDisplayId,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '₹${_fmtMoney.format(price)} / kg',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_isStockClosed && salesValue > 0)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'TODAY\'S SALES',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '₹${_fmtMoney.format(salesValue)}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // ── Stats Box ──
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FA),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  _minimalStat(
                                    'OPENING',
                                    '${_fmt.format(openingStock)}kg',
                                  ),
                                  _statDivider(),
                                  _minimalStat(
                                    'NEW STOCK',
                                    '+${_fmt.format(totalIn)}kg',
                                  ),
                                  _statDivider(),
                                  _minimalStat(
                                    'CLOSING',
                                    '${_fmt.format(currentStock)}kg',
                                    isBold: true,
                                  ),
                                  _statDivider(),
                                  _minimalStat(
                                    'OUT',
                                    '-${_fmt.format(totalOut)}kg',
                                  ),
                                ],
                              ),
                            ),

                            // ── Warnings ──
                            if (isOutOfStock || isLowStock) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7E6),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFFFE58F),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 16,
                                      color: Colors.orange.shade800,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isOutOfStock
                                          ? 'Out of stock'
                                          : 'Low stock — less than 1 kg left',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.orange.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // ── Closing Stock (bag breakdown of what's left) — tappable to record ──
                            const SizedBox(height: 12),
                            Builder(
                              builder: (_) {
                                final bagTotals = _aggregateBags(itemId);
                                final outEntries =
                                    (entry['outEntries'] as List<dynamic>?) ??
                                    [];
                                final canAct =
                                    (!_isStockClosed &&
                                        !widget.isLedgerClosed) ||
                                    !widget.isEmployeeLogin;
                                final hasOut = outEntries.isNotEmpty;

                                // Empty state — closing stock not recorded yet
                                if (!hasOut) {
                                  if (!canAct) return const SizedBox.shrink();
                                  return GestureDetector(
                                    onTap: () =>
                                        _showOutDialog(itemId, itemName),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.red.shade200,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.remove_circle_outline,
                                            size: 16,
                                            color: Colors.red.shade400,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Tap to record closing stock',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.red.shade400,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right,
                                            size: 16,
                                            color: Colors.red.shade400,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }

                                final closingBagSizes = _bagSizesFor(
                                  itemId,
                                  kClosingStockBagSizes,
                                );
                                // Include any sizes recorded before the item's
                                // denominations were (re)configured, so past
                                // entries never silently disappear from the summary.
                                final extraClosingSizes =
                                    bagTotals.keys
                                        .where(
                                          (s) => !closingBagSizes.contains(s),
                                        )
                                        .toList()
                                      ..sort((a, b) => b.compareTo(a));
                                final closingDisplaySizes = [
                                  ...closingBagSizes.where(
                                    bagTotals.containsKey,
                                  ),
                                  ...extraClosingSizes,
                                ];
                                final bagStr = bagTotals.isEmpty
                                    ? '${_fmt.format(currentStock)} kg'
                                    : closingDisplaySizes
                                          .map(
                                            (s) =>
                                                '${_fmt.format(bagTotals[s])}(${s}kg)',
                                          )
                                          .join(',  ');
                                final isReadOnly =
                                    _isStockClosed && widget.isEmployeeLogin;
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push<StockOutResult>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => StockOutPage(
                                          itemName: itemName,
                                          available: openingStock + totalIn,
                                          bagSizes: closingBagSizes,
                                          initialBags: bagTotals,
                                          isViewMode: true,
                                          isReadOnly: isReadOnly,
                                          price: price,
                                        ),
                                      ),
                                    ).then((result) {
                                      if (result != null) {
                                        _recordClosingStock(itemId, result);
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.inventory_2_outlined,
                                          size: 16,
                                          color: Colors.red.shade700,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'CLOSING',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.red.shade700,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            bagStr,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.red.shade900,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.right,
                                          ),
                                        ),
                                        if (!widget.isEmployeeLogin) ...[
                                          const SizedBox(width: 4),
                                          GestureDetector(
                                            onTap: () =>
                                                _deleteClosingEntry(itemId),
                                            child: Icon(
                                              Icons.delete_outline,
                                              size: 18,
                                              color: Colors.red.shade700,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 6),
                                        Icon(
                                          Icons.chevron_right,
                                          size: 16,
                                          color: Colors.red.shade400,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                            // ── Stock IN — one row per load, up to 5 loads ──
                            const SizedBox(height: 8),
                            Builder(
                              builder: (_) {
                                final canAct =
                                    (!_isStockClosed &&
                                        !widget.isLedgerClosed) ||
                                    !widget.isEmployeeLogin;
                                final canAddMore =
                                    canAct && inEntries.length < 5;

                                final inBagSizes = _bagSizesFor(
                                  itemId,
                                  kNewStockBagSizes,
                                );

                                String loadBagStr(dynamic e) {
                                  final qty =
                                      (e['qty'] as num?)?.toDouble() ?? 0;
                                  final bags =
                                      e['bags'] as List<dynamic>? ?? [];
                                  if (bags.isNotEmpty) {
                                    final Map<int, double> sizeMap = {};
                                    for (final b in bags) {
                                      final sz =
                                          (b['bagSize'] as num?)?.toInt() ?? 0;
                                      final cnt =
                                          (b['bags'] as num?)?.toDouble() ?? 0;
                                      if (sz > 0 && cnt > 0)
                                        sizeMap[sz] = (sizeMap[sz] ?? 0) + cnt;
                                    }
                                    final extraSizes =
                                        sizeMap.keys
                                            .where(
                                              (sz) => !inBagSizes.contains(sz),
                                            )
                                            .toList()
                                          ..sort((a, b) => b.compareTo(a));
                                    final displaySizes = [
                                      ...inBagSizes.where(sizeMap.containsKey),
                                      ...extraSizes,
                                    ];
                                    final s = displaySizes
                                        .map(
                                          (sz) =>
                                              '${_fmt.format(sizeMap[sz])}(${sz}kg)',
                                        )
                                        .join(', ');
                                    return s.isNotEmpty
                                        ? s
                                        : '+${_fmt.format(qty)} kg';
                                  }
                                  return '+${_fmt.format(qty)} kg';
                                }

                                return Column(
                                  children: [
                                    // Empty state — no loads yet
                                    if (inEntries.isEmpty && canAct)
                                      GestureDetector(
                                        onTap: () =>
                                            _showInDialog(itemId, itemName),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: Colors.green.shade200,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.add_circle_outline,
                                                size: 16,
                                                color: Colors.green.shade400,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  'Tap to add new stock',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        Colors.green.shade400,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right,
                                                size: 16,
                                                color: Colors.green.shade400,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                    // One row per existing load
                                    ...inEntries.asMap().entries.map((entry) {
                                      final i = entry.key;
                                      final e = entry.value;
                                      final bags = (e['bags'] as List<dynamic>?)
                                          ?.cast<Map<String, dynamic>>();
                                      final isReadOnly =
                                          _isStockClosed &&
                                          widget.isEmployeeLogin;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: GestureDetector(
                                          onTap: () {
                                            Navigator.push<StockInResult>(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => StockInPage(
                                                  itemName: itemName,
                                                  openingStock: openingStock,
                                                  totalIn: totalIn,
                                                  totalOut: totalOut,
                                                  initialBags: bags,
                                                  isViewMode: true,
                                                  loadNumber: i + 1,
                                                  isReadOnly: isReadOnly,
                                                  bagSizes: inBagSizes,
                                                  price: price,
                                                ),
                                              ),
                                            ).then((result) {
                                              if (result != null) {
                                                _updateLoadEntry(
                                                  itemId,
                                                  i,
                                                  result,
                                                );
                                              }
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.green.shade200,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.check_circle_outline,
                                                  size: 16,
                                                  color: Colors.green.shade700,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'N.S ${i + 1}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        Colors.green.shade700,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    loadBagStr(e),
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color:
                                                          Colors.green.shade800,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (!widget
                                                    .isEmployeeLogin) ...[
                                                  const SizedBox(width: 4),
                                                  GestureDetector(
                                                    onTap: () =>
                                                        _deleteLoadEntry(
                                                          itemId,
                                                          i,
                                                        ),
                                                    child: Icon(
                                                      Icons.delete_outline,
                                                      size: 18,
                                                      color:
                                                          Colors.green.shade700,
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(width: 6),
                                                Icon(
                                                  Icons.chevron_right,
                                                  size: 16,
                                                  color: Colors.green.shade400,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }),

                                    // + Add Load button (shown when loads exist and can add more)
                                    if (canAddMore && inEntries.isNotEmpty)
                                      GestureDetector(
                                        onTap: () =>
                                            _showInDialog(itemId, itemName),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: Colors.green.shade300,
                                              style: BorderStyle.solid,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.add,
                                                size: 16,
                                                color: Colors.green.shade700,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Load ${inEntries.length + 1}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.green.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
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
                  16,
                  8,
                  16,
                  16 + MediaQuery.of(context).viewPadding.bottom,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isClosingStock ? null : _closeStock,
                    icon: _isClosingStock
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.lock_outline, color: Colors.white),
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx, scrollController) {
            return Container(
              width: double.infinity,
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
                            color: const Color(0xFF455A64),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
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
                                '₹${_fmtMoney.format(price)} per kg  •  ${DateFormat('dd MMM yyyy').format(widget.date)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(
                            Icons.close,
                            color: Colors.grey[500],
                            size: 22,
                          ),
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
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F6FA),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          _summaryChip(
                            'Total IN',
                            '+${_fmt.format(totalIn)} kgs',
                            Colors.green[700]!,
                            Colors.green[50]!,
                          ),
                          const SizedBox(width: 10),
                          _summaryChip(
                            'Total OUT',
                            '-${_fmt.format(totalOut)} kgs',
                            Colors.orange[700]!,
                            Colors.orange[50]!,
                          ),
                          const SizedBox(width: 10),
                          _summaryChip(
                            'Sales',
                            '₹${_fmtMoney.format(salesValue)}',
                            const Color(0xFF455A64),
                            const Color(0xFFF0F4F7),
                          ),
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
                      padding: EdgeInsets.fromLTRB(
                        20,
                        16,
                        20,
                        24 + MediaQuery.of(ctx).padding.bottom,
                      ),
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
                          _emptyLogRow(
                            'No stock received today',
                            Colors.green[300]!,
                          )
                        else
                          ...inEntries.asMap().entries.map((e) {
                            final qty =
                                (e.value['qty'] as num?)?.toDouble() ?? 0;
                            final ts = e.value['timestamp'] as String?;
                            final timeStr = formatTime(ts);
                            final bags =
                                e.value['bags'] as List<dynamic>? ?? [];
                            final bagStr = bags
                                .map((b) {
                                  final bagCount =
                                      (b['bags'] as num?)?.toDouble() ?? 0;
                                  return '${b['bagSize']}kg × ${_fmt.format(bagCount)} bag${bagCount > 1 ? 's' : ''}';
                                })
                                .join('  •  ');
                            return _logRow(
                              index: e.key + 1,
                              isIn: true,
                              mainText: '+${_fmt.format(qty)} kgs received',
                              subText: bagStr.isNotEmpty ? bagStr : null,
                              timeText: timeStr.isNotEmpty ? timeStr : null,
                              color: Colors.green[700]!,
                              bgColor: Colors.green[50]!,
                              borderColor: Colors.green[100]!,
                            );
                          }),

                        const SizedBox(height: 20),

                        // OUT section
                        _logSectionHeader(
                          Icons.remove_circle_outline,
                          'Closing Stock Entries',
                          Colors.orange[700]!,
                          outEntries.length,
                        ),
                        const SizedBox(height: 10),
                        if (outEntries.isEmpty)
                          _emptyLogRow(
                            'No closing stock recorded today',
                            Colors.orange[300]!,
                          )
                        else
                          ...outEntries.asMap().entries.map((e) {
                            // 'closingQty'/'soldQty' are the current schema; 'totalQty'
                            // is a legacy fallback for entries recorded before this field
                            // split (where it held the sold quantity directly).
                            final closingQty = (e.value['closingQty'] as num?)
                                ?.toDouble();
                            final soldQty =
                                (e.value['soldQty'] as num?)?.toDouble() ??
                                (e.value['totalQty'] as num?)?.toDouble() ??
                                0;
                            final bags =
                                e.value['bags'] as List<dynamic>? ?? [];
                            final ts = e.value['timestamp'] as String?;
                            final timeStr = formatTime(ts);
                            final bagStr = bags
                                .map((b) {
                                  final bagCount =
                                      (b['bags'] as num?)?.toDouble() ?? 0;
                                  return '${b['bagSize']}kg × ${_fmt.format(bagCount)} bag${bagCount > 1 ? 's' : ''}';
                                })
                                .join('  •  ');
                            final subParts = [
                              if (closingQty != null)
                                'Closing stock entered: ${_fmt.format(closingQty)} kg',
                              if (bagStr.isNotEmpty) bagStr,
                            ];
                            return _logRow(
                              index: e.key + 1,
                              isIn: false,
                              mainText: '-${_fmt.format(soldQty)} kgs sold',
                              subText: subParts.isNotEmpty
                                  ? subParts.join('  •  ')
                                  : null,
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
    String label,
    String value,
    Color textColor,
    Color bgColor,
  ) {
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
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logSectionHeader(
    IconData icon,
    String title,
    Color color,
    int count,
  ) {
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
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count entr${count == 1 ? 'y' : 'ies'}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
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
        child: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[400],
            fontWeight: FontWeight.w500,
          ),
        ),
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
                      color: color,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          color: color,
                        ),
                      ),
                      if (timeText != null || subText == null)
                        Text(
                          timeText ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  if (subText != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subText,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (timeText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        timeText,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[400],
                          fontWeight: FontWeight.w500,
                        ),
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

  Widget _minimalStat(String label, String value, {bool isBold = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: isBold ? Colors.black : Colors.grey.shade800,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 20,
      color: Colors.grey.shade200,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
