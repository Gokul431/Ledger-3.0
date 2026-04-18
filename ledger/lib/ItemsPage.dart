import 'package:flutter/material.dart';
import 'AddEditItemPage.dart';
import 'StockAnalyticsPage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  static const _primary = Color(0xFF455A64);

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

  Future<void> _deleteItem(String docId) async {
    if (_selectedShopCollection == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Item',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
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
            const SnackBar(
                content: Text('Item deleted'),
                behavior: SnackBarBehavior.floating),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Failed to delete: $e'),
                behavior: SnackBarBehavior.floating),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        surfaceTintColor: Colors.transparent,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE8EAED)),
        ),
        title: const Text(
          'Manage Items',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF1A1A2E)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Analytics & Reports',
            onPressed: _selectedShopCollection == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StockAnalyticsPage(
                          shopCollection: _selectedShopCollection!,
                          shopName: _selectedShopName ?? '',
                        ),
                      ),
                    ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _primary, strokeWidth: 2))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Shop selector ──
                _buildShopSelector(),

                // ── Items list ──
                Expanded(
                  child: _selectedShopCollection == null
                      ? _emptyState(Icons.store_outlined, 'No shops found',
                          'Add shops first from the admin panel')
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
                                  child: Text('Error: ${snapshot.error}'));
                            }
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator(
                                      color: _primary, strokeWidth: 2));
                            }
                            final docs = snapshot.data?.docs ?? [];
                            if (docs.isEmpty) {
                              return _emptyState(
                                  Icons.inventory_2_outlined,
                                  'No items yet',
                                  'Tap "New Item" below to get started');
                            }
                            return ListView.builder(
                              padding: EdgeInsets.only(
                                bottom: 90 +
                                    MediaQuery.of(context).viewPadding.bottom,
                              ),
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                return _buildItemRow(docs[index], index, docs.length);
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
              backgroundColor: _primary,
              elevation: 2,
              icon: const Icon(Icons.post_add_rounded,
                  color: Colors.white, size: 20),
              label: const Text(
                'New Item',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            )
          : null,
    );
  }

  // ── Shop selector ─────────────────────────────────────────────────────────

  Widget _buildShopSelector() {
    return Container(
      color: Colors.grey[50],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Text('Shop',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedShopCollection,
                isExpanded: true,
                icon: Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey[500], size: 18),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87),
                onChanged: (val) {
                  if (val == null) return;
                  final shop =
                      _shops.firstWhere((s) => s['collectionName'] == val);
                  setState(() {
                    _selectedShopCollection = val;
                    _selectedShopName = shop['shopName'] as String;
                  });
                },
                items: _shops
                    .map((s) => DropdownMenuItem<String>(
                          value: s['collectionName'] as String,
                          child: Text(s['shopName'] as String,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Item row ──────────────────────────────────────────────────────────────

  Widget _buildItemRow(DocumentSnapshot doc, int index, int total) {
    final d = doc.data() as Map<String, dynamic>;
    final itemName = (d['itemName'] ?? '') as String;
    final price = (d['price'] ?? 0).toDouble();
    final openingStock = (d['openingStock'] ?? 0).toDouble();
    final isActive = d['isActive'] ?? true;
    final stockDate = d['openingStockDate'] != null
        ? DateFormat('dd MMM yyyy')
            .format((d['openingStockDate'] as Timestamp).toDate())
        : '';

    final fmt = NumberFormat('#,##0.##');
    final fmtMoney = NumberFormat('#,##,##0.00');

    return Column(
      children: [
        InkWell(
          onTap: () => _navigateToEdit(doc: doc),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Index number ──
                SizedBox(
                  width: 24,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[400],
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // ── Main info ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text(
                        itemName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Price
                      Text(
                        '₹${fmtMoney.format(price)} / kg',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 10),
                      // Meta row
                      Row(
                        children: [
                          Text(
                            'Opening  ',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[400],
                                fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '${fmt.format(openingStock)} kg',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87),
                          ),
                          if (stockDate.isNotEmpty) ...[
                            Text('  ·  ',
                                style: TextStyle(
                                    color: Colors.grey[300], fontSize: 13)),
                            Text(
                              'Added  ',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[400],
                                  fontWeight: FontWeight.w500),
                            ),
                            Text(
                              stockDate,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Right side: status + menu ──
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isActive ? 'Active' : 'Inactive',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isActive ? Colors.green[600] : Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 6),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded,
                          color: Colors.grey[400], size: 18),
                      padding: EdgeInsets.zero,
                      onSelected: (value) {
                        if (value == 'edit') _navigateToEdit(doc: doc);
                        if (value == 'delete') _deleteItem(doc.id);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            Icon(Icons.edit_outlined, size: 16),
                            SizedBox(width: 10),
                            Text('Edit', style: TextStyle(fontSize: 14)),
                          ]),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            Icon(Icons.delete_outline,
                                color: Colors.red, size: 16),
                            SizedBox(width: 10),
                            Text('Delete',
                                style: TextStyle(
                                    color: Colors.red, fontSize: 14)),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          color: Colors.grey[200],
          indent: 16,
          endIndent: 16,
        ),
      ],
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: Colors.grey[300]),
          const SizedBox(height: 14),
          Text(title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500])),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[400])),
          ),
        ],
      ),
    );
  }
}
