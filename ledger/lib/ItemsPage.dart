import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});

  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _shops = [];
  String? _selectedShopCollection;
  String? _selectedShopName;

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedShop = prefs.getString('selectedShopCollection') ??
          prefs.getString('shopCollection');

      final snap =
          await FirebaseFirestore.instance.collection('shop_list').get();

      final shops = snap.docs.map((d) {
        final data = d.data();
        return {
          'collectionName': data['collectionName'] ?? '',
          'shopName': data['shopName'] ?? 'Unknown Shop',
        };
      }).where((s) => (s['collectionName'] as String).isNotEmpty).toList();

      // Sort alphabetically
      shops.sort((a, b) =>
          (a['shopName'] as String).compareTo(b['shopName'] as String));

      String? selectedCollection;
      String? selectedName;

      // Use saved selection if it's in the fetched list
      if (savedShop != null && shops.any((s) => s['collectionName'] == savedShop)) {
        selectedCollection = savedShop;
        selectedName =
            shops.firstWhere((s) => s['collectionName'] == savedShop)['shopName'];
      } else if (shops.isNotEmpty) {
        selectedCollection = shops[0]['collectionName'];
        selectedName = shops[0]['shopName'];
      }

      if (mounted) {
        setState(() {
          _shops = shops;
          _selectedShopCollection = selectedCollection;
          _selectedShopName = selectedName;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ItemsPage load shops error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Add / Edit dialog ──────────────────────────────────────────────────

  void _showAddItemDialog({DocumentSnapshot? existingDoc}) {
    if (_selectedShopCollection == null) {
      _showError('Please select a shop first.');
      return;
    }

    final data = existingDoc?.data() as Map<String, dynamic>?;
    final nameController =
        TextEditingController(text: data?['itemName'] ?? '');
    final priceController = TextEditingController(
        text: data != null ? (data['price'] ?? 0).toString() : '');
    final stockController = TextEditingController(
        text: data != null ? (data['openingStock'] ?? 0).toString() : '');
    bool isActive = data?['isActive'] ?? true;
    DateTime selectedDate = data?['openingStockDate'] != null
        ? (data!['openingStockDate'] as Timestamp).toDate()
        : DateTime.now();
    final isEdit = existingDoc != null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                isEdit ? Icons.edit_outlined : Icons.add_circle_outline,
                color: const Color(0xFF1565C0),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEdit ? 'Edit Item' : 'Add New Item',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _selectedShopName ?? '',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w400),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(
                    nameController, 'Item Name', 'e.g. Ponni Basmati'),
                const SizedBox(height: 14),
                _buildTextField(
                    priceController, 'Price (₹ per kg)', '0',
                    isNumber: true),
                const SizedBox(height: 14),
                _buildTextField(
                    stockController, 'Opening Stock (kgs)', '0',
                    isNumber: true),
                const SizedBox(height: 14),

                // Opening Stock Date
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      builder: (ctx, child) => Theme(
                        data: Theme.of(ctx).copyWith(
                          colorScheme: const ColorScheme.light(
                              primary: Color(0xFF1565C0)),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 18, color: Colors.grey[600]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Opening Stock Date',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600])),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('dd MMM yyyy')
                                    .format(selectedDate),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_drop_down,
                            color: Colors.grey[600]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Active Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Active Status',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    Switch(
                      value: isActive,
                      activeTrackColor: const Color(0xFF1565C0),
                      activeThumbColor: Colors.white,
                      onChanged: (v) =>
                          setDialogState(() => isActive = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style:
                      TextStyle(color: Colors.grey[700], fontSize: 15)),
            ),
            ElevatedButton(
              onPressed: () => _saveItem(
                ctx,
                existingDoc?.id,
                nameController.text.trim(),
                double.tryParse(priceController.text.trim()) ?? 0,
                double.tryParse(stockController.text.trim()) ?? 0,
                selectedDate,
                isActive,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                isEdit ? 'Update' : 'Save Item',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: Color(0xFF1565C0), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  // ─── Save ────────────────────────────────────────────────────────────────

  Future<void> _saveItem(
    BuildContext ctx,
    String? docId,
    String name,
    double price,
    double openingStock,
    DateTime openingStockDate,
    bool isActive,
  ) async {
    if (_selectedShopCollection == null || _selectedShopCollection!.isEmpty) {
      _showError('No shop selected.');
      return;
    }
    if (name.isEmpty) {
      _showError('Please enter item name.');
      return;
    }
    if (ctx.mounted) Navigator.pop(ctx);

    try {
      final col = FirebaseFirestore.instance
          .collection(_selectedShopCollection!)
          .doc('items')
          .collection('list');

      final Map<String, dynamic> saveData = {
        'itemName': name,
        'price': price,
        'openingStock': openingStock,
        'openingStockDate': Timestamp.fromDate(openingStockDate),
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (docId == null) {
        saveData['createdAt'] = FieldValue.serverTimestamp();
        await col.add(saveData);
      } else {
        await col.doc(docId).update(saveData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(docId == null
                ? 'Item added to $_selectedShopName'
                : 'Item updated in $_selectedShopName'),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      _showError('Failed to save item: $e');
    }
  }

  // ─── Delete ──────────────────────────────────────────────────────────────

  Future<void> _deleteItem(String docId) async {
    if (_selectedShopCollection == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Item',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection(_selectedShopCollection!)
            .doc('items')
            .collection('list')
            .doc(docId)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Item deleted'),
              backgroundColor: Colors.red[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } catch (e) {
        _showError('Failed to delete: $e');
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: const Text(
          'Manage Items',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1565C0)))
          : Column(
              children: [
                // ── Shop Selector ──
                _buildShopSelector(),

                // ── Items List ──
                Expanded(
                  child: _selectedShopCollection == null
                      ? _emptyState(
                          Icons.store_outlined,
                          'No shops found',
                          'Add shops first from the admin panel',
                        )
                      : StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection(_selectedShopCollection!)
                              .doc('items')
                              .collection('list')
                              .orderBy('createdAt', descending: false)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Error: ${snapshot.error}',
                                    style:
                                        TextStyle(color: Colors.red[600])),
                              );
                            }
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator(
                                      color: Color(0xFF1565C0)));
                            }

                            final docs = snapshot.data?.docs ?? [];
                            if (docs.isEmpty) {
                              return _emptyState(
                                Icons.inventory_2_outlined,
                                'No items yet',
                                'Tap + to add your first item for $_selectedShopName',
                              );
                            }

                            return ListView.separated(
                              padding: EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  16 +
                                      MediaQuery.of(context)
                                          .viewPadding
                                          .bottom),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                return _buildItemCard(docs[index]);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: _selectedShopCollection != null
          ? FloatingActionButton.extended(
              onPressed: _showAddItemDialog,
              backgroundColor: const Color(0xFF1565C0),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add Item',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }

  // ─── Shop Selector Card ──────────────────────────────────────────────────

  Widget _buildShopSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Managing items for',
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          if (_shops.isEmpty)
            Text('No shops found',
                style: TextStyle(color: Colors.red[400], fontSize: 14))
          else
            DropdownButtonFormField<String>(
              initialValue: _selectedShopCollection,
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey[300]!)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey[300]!)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: Color(0xFF1565C0), width: 2)),
                filled: true,
                fillColor: const Color(0xFFF5F6FA),
                prefixIcon: const Icon(Icons.store_outlined,
                    color: Color(0xFF1565C0), size: 20),
              ),
              icon: const Icon(Icons.keyboard_arrow_down,
                  color: Color(0xFF1565C0)),
              items: _shops
                  .map((s) => DropdownMenuItem<String>(
                        value: s['collectionName'] as String,
                        child: Text(
                          s['shopName'] as String,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val == null) return;
                final shop =
                    _shops.firstWhere((s) => s['collectionName'] == val);
                setState(() {
                  _selectedShopCollection = val;
                  _selectedShopName = shop['shopName'] as String;
                });
              },
            ),
          const SizedBox(height: 4),
          Divider(height: 1, color: Colors.grey[200]),
        ],
      ),
    );
  }

  // ─── Item Card ───────────────────────────────────────────────────────────

  Widget _buildItemCard(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final itemName = d['itemName'] ?? '';
    final price = (d['price'] ?? 0).toDouble();
    final openingStock = (d['openingStock'] ?? 0).toDouble();
    final isActive = d['isActive'] ?? true;
    final stockDate = d['openingStockDate'] != null
        ? DateFormat('dd MMM yyyy')
            .format((d['openingStockDate'] as Timestamp).toDate())
        : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
              color:
                  isActive ? const Color(0xFF1565C0) : Colors.grey[300]!,
              width: 4),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Row(
          children: [
            Expanded(
              child: Text(
                itemName,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.black87 : Colors.grey[500]),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isActive ? Colors.green[50] : Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isActive
                        ? Colors.green[300]!
                        : Colors.grey[300]!),
              ),
              child: Text(
                isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? Colors.green[700]
                        : Colors.grey[600]),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '₹${NumberFormat('#,##,##0.00').format(price)}/kg',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Stock: ${NumberFormat('#,##0.##').format(openingStock)} kgs',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
              if (stockDate.isNotEmpty)
                Text('Date: $stockDate',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[400])),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: Colors.grey[600]),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          onSelected: (value) {
            if (value == 'edit') {
              _showAddItemDialog(existingDoc: doc);
            } else if (value == 'delete') {
              _deleteItem(doc.id);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined,
                      color: Color(0xFF1565C0), size: 18),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.red, size: 18),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Empty state ─────────────────────────────────────────────────────────

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600])),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[400])),
          ),
        ],
      ),
    );
  }
}
