import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AddEditItemPage extends StatefulWidget {
  final String shopCollection;
  final String shopName;
  final DocumentSnapshot? existingDoc;

  const AddEditItemPage({
    super.key,
    required this.shopCollection,
    required this.shopName,
    this.existingDoc,
  });

  @override
  State<AddEditItemPage> createState() => _AddEditItemPageState();
}

class _AddEditItemPageState extends State<AddEditItemPage> {
  late TextEditingController _itemIdController;
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _stockController;
  late TextEditingController _bagSizeController;

  bool _isActive = true;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;
  List<int> _bagSizes = [];

  bool get isEdit => widget.existingDoc != null;

  @override
  void initState() {
    super.initState();
    final data = widget.existingDoc?.data() as Map<String, dynamic>?;
    
    _itemIdController = TextEditingController(
        text: data != null ? (data['itemId'] ?? '').toString() : '');
    _nameController = TextEditingController(text: data?['itemName'] ?? '');
    _priceController = TextEditingController(
        text: data != null ? (data['price'] ?? 0).toString() : '');
    _stockController = TextEditingController(
        text: data != null ? (data['openingStock'] ?? 0).toString() : '');
    _bagSizeController = TextEditingController();

    if (data != null) {
      _isActive = data['isActive'] ?? true;
      if (data['openingStockDate'] != null) {
        _selectedDate = (data['openingStockDate'] as Timestamp).toDate();
      }
      final rawBagSizes = data['bagSizes'] as List<dynamic>?;
      if (rawBagSizes != null) {
        _bagSizes = rawBagSizes.map((e) => (e as num).toInt()).toList();
      }
    }
  }

  @override
  void dispose() {
    _itemIdController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _bagSizeController.dispose();
    super.dispose();
  }

  void _addBagSize() {
    final size = int.tryParse(_bagSizeController.text.trim());
    if (size == null || size <= 0 || _bagSizes.contains(size)) return;
    setState(() {
      _bagSizes.add(size);
      _bagSizes.sort((a, b) => b.compareTo(a));
      _bagSizeController.clear();
    });
  }

  void _removeBagSize(int size) {
    setState(() => _bagSizes.remove(size));
  }

  /// Mirrors StockTab's cascade fix for the same bug class: if an existing
  /// item's opening stock / start date is corrected here *after* ledger days
  /// already exist for it, those days' frozen openingStock would otherwise
  /// stay stale. Walks forward from [startDate] fixing each existing day's
  /// openingStock, and syncs the item's lastClosingStock once it reaches a
  /// day that's already in sync (or runs out of days).
  ///
  /// A day that hasn't been closed yet (no outEntries) just gets its
  /// closingStock recomputed as opening + totalIn. A day that was ALREADY
  /// closed has a physically-measured closing amount that must not change —
  /// only the derived sold qty / sales value (and that day's sales totals)
  /// get recalculated.
  Future<void> _cascadeOpeningCorrection(
    DocumentReference itemMasterRef,
    String itemKey,
    DateTime startDate,
    double newOpening,
  ) async {
    DateTime cursorDate = startDate;
    double cursorValue = newOpening;
    bool touchedAny = false;

    while (true) {
      final dateStr = DateFormat('dd-MMM-yyyy').format(cursorDate);
      final itemsCol = FirebaseFirestore.instance
          .collection(widget.shopCollection)
          .doc('stockLedger')
          .collection('dates')
          .doc(dateStr)
          .collection('items');
      final ref = itemsCol.doc(itemKey);

      final snap = await ref.get();
      if (!snap.exists) break;

      final d = snap.data() as Map<String, dynamic>;
      final oldOpening = (d['openingStock'] ?? 0).toDouble();
      if (touchedAny && oldOpening == cursorValue) break; // downstream in sync

      final totalIn = (d['totalIn'] ?? 0).toDouble();
      final outEntries = d['outEntries'] as List<dynamic>? ?? [];
      final updates = <String, dynamic>{'openingStock': cursorValue};
      double newValue;

      if (outEntries.isNotEmpty) {
        final price = (d['price'] ?? 0).toDouble();
        final lastOut = outEntries.last as Map<String, dynamic>;
        final measuredClosing = (lastOut['closingQty'] ?? 0).toDouble();
        final newTotalOut =
            (cursorValue + totalIn - measuredClosing).clamp(0.0, double.infinity);
        updates['totalOut'] = newTotalOut;
        updates['salesValue'] = newTotalOut * price;
        updates['closingStock'] = measuredClosing;
        newValue = measuredClosing;

        await ref.update(updates);
        await _resyncDayTotals(dateStr, itemsCol);
      } else {
        newValue = cursorValue + totalIn; // totalOut is always 0 here
        updates['closingStock'] = newValue;
        await ref.update(updates);
      }

      touchedAny = true;
      cursorValue = newValue;
      cursorDate = cursorDate.add(const Duration(days: 1));
    }

    if (touchedAny) {
      await itemMasterRef.update({
        'lastClosingStock': cursorValue,
        'lastClosingDate':
            Timestamp.fromDate(cursorDate.subtract(const Duration(days: 1))),
      });
    }
  }

  /// A price change takes effect from TODAY onward, until the next change.
  ///
  /// Each stock day freezes the item's price when that day's record is first
  /// created, so a day already opened today (or opened ahead) would otherwise
  /// keep the old price. This updates the price — and recalculates sales — on
  /// the existing records for today and any later days, skipping days whose
  /// stock is already closed so past/closed figures never change. Days not
  /// created yet pick up the new master price automatically.
  ///
  /// Returns true if today's stock was already closed (the new price will
  /// then start from tomorrow).
  Future<bool> _applyPriceFromToday(String itemKey, double newPrice) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final datesCol = FirebaseFirestore.instance
        .collection(widget.shopCollection)
        .doc('stockLedger')
        .collection('dates');

    // Today plus up to 30 days ahead (in case future ledgers were opened).
    final dateStrs = List.generate(
      31,
      (i) => DateFormat('dd-MMM-yyyy').format(today.add(Duration(days: i))),
    );
    final results = await Future.wait([
      Future.wait(dateStrs.map((s) => datesCol.doc(s).get())),
      Future.wait(
        dateStrs.map((s) => datesCol.doc(s).collection('items').doc(itemKey).get()),
      ),
    ]);
    final dateDocs = results[0];
    final itemDocs = results[1];

    bool todayClosed = false;
    for (int i = 0; i < dateStrs.length; i++) {
      final itemSnap = itemDocs[i];
      if (!itemSnap.exists) continue;

      final dayData = dateDocs[i].data();
      final dayClosed = dayData != null && dayData['isClosed'] == true;
      if (dayClosed) {
        if (i == 0) todayClosed = true;
        continue; // never rewrite a closed day's figures
      }

      final d = itemSnap.data()!;
      if ((d['price'] ?? 0).toDouble() == newPrice) continue;

      final totalOut = (d['totalOut'] ?? 0).toDouble();
      await itemSnap.reference.update({
        'price': newPrice,
        'salesValue': totalOut * newPrice,
      });
      if (totalOut > 0) {
        await _resyncDayTotals(
          dateStrs[i],
          datesCol.doc(dateStrs[i]).collection('items'),
        );
      }
    }
    return todayClosed;
  }

  /// Recomputes a date's total sales from its item docs and syncs it to the
  /// stockLedger date doc and that date's ledger doc (if one exists).
  Future<void> _resyncDayTotals(
      String dateStr, CollectionReference itemsCol) async {
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
      await ledgerQuery.docs.first.reference
          .set({'saleValue': total}, SetOptions(merge: true));
    }
  }

  Future<void> _saveItem() async {
    final itemId = _itemIdController.text.trim();
    final name = _nameController.text.trim();
    if (itemId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter an item ID.'),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter item name.'),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final price = double.tryParse(_priceController.text.trim()) ?? 0;
      final openingStock = double.tryParse(_stockController.text.trim()) ?? 0;
      bool priceStartsTomorrow = false;

      final col = FirebaseFirestore.instance
          .collection(widget.shopCollection)
          .doc('items')
          .collection('list');

      final Map<String, dynamic> saveData = {
        'itemId': itemId,
        'itemName': name,
        'price': price,
        'openingStock': openingStock,
        'openingStockDate': Timestamp.fromDate(_selectedDate),
        'isActive': _isActive,
        'bagSizes': _bagSizes,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!isEdit) {
        saveData['createdAt'] = FieldValue.serverTimestamp();
        await col.add(saveData);
      } else {
        final existingData =
            widget.existingDoc!.data() as Map<String, dynamic>;
        final originalKey =
            (existingData['itemId'] ?? '').toString().trim().isNotEmpty
                ? (existingData['itemId'] as String).trim()
                : widget.existingDoc!.id;
        final originalOpening =
            (existingData['openingStock'] ?? 0).toDouble();
        DateTime? originalDateOnly;
        if (existingData['openingStockDate'] != null) {
          final raw = (existingData['openingStockDate'] as Timestamp).toDate();
          originalDateOnly = DateTime(raw.year, raw.month, raw.day);
        }
        final selectedDateOnly = DateTime(
            _selectedDate.year, _selectedDate.month, _selectedDate.day);

        final masterRef = col.doc(widget.existingDoc!.id);
        await masterRef.update(saveData);

        // Only safe to cascade when the ledger key (itemId) didn't change —
        // a rename would point at a different stock ledger document entirely.
        final keyUnchanged = originalKey == itemId;

        // New price applies from today onward (before the opening cascade,
        // so any sales it recalculates use the new price).
        final originalPrice = (existingData['price'] ?? 0).toDouble();
        if (keyUnchanged && originalPrice != price) {
          priceStartsTomorrow = await _applyPriceFromToday(itemId, price);
        }
        final valueChanged = originalOpening != openingStock ||
            originalDateOnly != selectedDateOnly;
        if (keyUnchanged && valueChanged) {
          await _cascadeOpeningCorrection(
            masterRef,
            itemId,
            selectedDateOnly,
            openingStock,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!isEdit
                ? 'Item added successfully'
                : priceStartsTomorrow
                    ? 'Item updated. Today\'s stock is already closed, so the new price applies from tomorrow.'
                    : 'Item updated successfully'),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF455A64)),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Colors.grey[500],
          letterSpacing: 0.2),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isNumber = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          keyboardType: isNumber
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[300], fontSize: 16, fontWeight: FontWeight.w500),
            prefixIcon: Icon(icon, color: Colors.grey[400], size: 22),
            filled: true,
            fillColor: const Color(0xFFF8F9FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF455A64), width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        title: Text(
          isEdit ? 'Edit Item' : 'New Item',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, letterSpacing: -0.5),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Internal Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Info Ribbon ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECEFF1).withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFCFD8DC).withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.storefront_rounded, size: 20, color: const Color(0xFF455A64)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Adding to: ${widget.shopName}',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF455A64)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    _buildTextField(
                      controller: _itemIdController,
                      label: 'Item ID',
                      hint: 'e.g. 1, 2, 3...',
                      icon: Icons.tag_rounded,
                      isNumber: true,
                    ),
                    const SizedBox(height: 20),

                    _buildTextField(
                      controller: _nameController,
                      label: 'Item Name',
                      hint: 'e.g. Ponni Basmati',
                      icon: Icons.inventory_2_outlined,
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _priceController,
                            label: 'Price per kg (₹)',
                            hint: '0.00',
                            icon: Icons.currency_rupee_rounded,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _stockController,
                            label: 'Opening Stock',
                            hint: '0 kg',
                            icon: Icons.scale_outlined,
                            isNumber: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _buildSectionLabel('Opening Stock Date'),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 20, color: Colors.grey.shade400),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                DateFormat('dd MMMM yyyy').format(_selectedDate),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
                              ),
                            ),
                            Icon(Icons.edit_calendar_rounded, size: 20, color: Colors.grey.shade400),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildSectionLabel('Bag Denominations (kg)'),
                    const SizedBox(height: 4),
                    Text(
                      'Bag sizes this item is packed in — used in New Stock & Closing Stock entry',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _bagSizeController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: false),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            onSubmitted: (_) => _addBagSize(),
                            decoration: InputDecoration(
                              hintText: 'e.g. 25',
                              hintStyle: TextStyle(color: Colors.grey[300], fontSize: 16, fontWeight: FontWeight.w500),
                              prefixIcon: Icon(Icons.inventory_outlined, color: Colors.grey[400], size: 22),
                              filled: true,
                              fillColor: const Color(0xFFF8F9FA),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Color(0xFF455A64), width: 2),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 54,
                          width: 54,
                          child: ElevatedButton(
                            onPressed: _addBagSize,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF455A64),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: const Icon(Icons.add_rounded, size: 26),
                          ),
                        ),
                      ],
                    ),
                    if (_bagSizes.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _bagSizes.map((size) {
                          return Chip(
                            label: Text('$size kg',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            backgroundColor: const Color(0xFFECEFF1),
                            deleteIcon: const Icon(Icons.close_rounded, size: 18),
                            onDeleted: () => _removeBagSize(size),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.power_settings_new_rounded, size: 22, color: _isActive ? Colors.green.shade600 : Colors.grey.shade400),
                              const SizedBox(width: 14),
                              const Text('Active Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          Switch(
                            value: _isActive,
                            activeTrackColor: const Color(0xFF455A64),
                            activeColor: Colors.white,
                            onChanged: (v) => setState(() => _isActive = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4)),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveItem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF455A64),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        isEdit ? 'UPDATE ITEM' : 'SAVE ITEM',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
