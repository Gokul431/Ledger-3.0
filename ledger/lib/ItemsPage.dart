import 'package:flutter/material.dart';
import 'AddEditItemPage.dart';
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
      final snap =
          await FirebaseFirestore.instance.collection('shop_list').get();

      final shops = snap.docs.map((d) {
        final data = d.data();
        return {
          'collectionName': data['collectionName'] ?? '',
          'shopName': data['shopName'] ?? 'Unknown Shop',
        };
      }).where((s) => (s['collectionName'] as String).isNotEmpty).toList();

      shops.sort((a, b) =>
          (a['shopName'] as String).compareTo(b['shopName'] as String));

      if (mounted) {
        setState(() {
          _shops = shops;
          if (_selectedShopCollection == null && shops.isNotEmpty) {
            _selectedShopCollection = shops[0]['collectionName'];
            _selectedShopName = shops[0]['shopName'];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ItemsPage load shops error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToEdit({DocumentSnapshot? doc}) {
    if (_selectedShopCollection == null || _selectedShopName == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditItemPage(
          shopCollection: _selectedShopCollection!,
          shopName: _selectedShopName!,
          existingDoc: doc,
        ),
      ),
    );
  }


  // ─── Save ────────────────────────────────────────────────────────────────


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
                const SizedBox(height: 12),

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
              onPressed: () => _navigateToEdit(),
              backgroundColor: const Color(0xFF1565C0),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add Item',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            )
          : null,
    );
  }

  // ─── Shop Selector Card ──────────────────────────────────────────────────

  Widget _buildShopSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Managing items for',
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _selectedShopCollection,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[200]!)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[200]!)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFF1565C0), width: 2)),
              filled: true,
              fillColor: const Color(0xFFF8F9FB),
              prefixIcon: const Icon(Icons.storefront_rounded,
                  color: Color(0xFF1565C0), size: 22),
            ),
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF1565C0)),
            items: _shops
                .map((s) => DropdownMenuItem<String>(
                      value: s['collectionName'] as String,
                      child: Text(
                        s['shopName'] as String,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(
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
                            fontWeight: FontWeight.w800,
                            color: Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${NumberFormat('#,##,##0.00').format(price)} / kg',
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.green[50] : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isActive
                                    ? Colors.green[700]
                                    : Colors.grey[600]),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert_rounded, color: Colors.grey[400]),
                          padding: EdgeInsets.zero,
                          onSelected: (value) {
                            if (value == 'edit') {
                              _navigateToEdit(doc: doc);
                            } else if (value == 'delete') {
                              _deleteItem(doc.id);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_rounded, size: 18),
                                  SizedBox(width: 10),
                                  Text('Edit Item'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_rounded, color: Colors.red, size: 18),
                                  SizedBox(width: 10),
                                  Text('Delete Item', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[100]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OPENING STOCK',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey[500],
                              letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${NumberFormat('#,##0.##').format(openingStock)} kg',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 24, color: Colors.grey[200]),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DATE ADDED',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey[500],
                              letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stockDate.isNotEmpty ? stockDate : '-',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
