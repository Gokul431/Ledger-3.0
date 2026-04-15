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
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _stockController;
  
  bool _isActive = true;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  bool get isEdit => widget.existingDoc != null;

  @override
  void initState() {
    super.initState();
    final data = widget.existingDoc?.data() as Map<String, dynamic>?;
    
    _nameController = TextEditingController(text: data?['itemName'] ?? '');
    _priceController = TextEditingController(
        text: data != null ? (data['price'] ?? 0).toString() : '');
    _stockController = TextEditingController(
        text: data != null ? (data['openingStock'] ?? 0).toString() : '');
        
    if (data != null) {
      _isActive = data['isActive'] ?? true;
      if (data['openingStockDate'] != null) {
        _selectedDate = (data['openingStockDate'] as Timestamp).toDate();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _saveItem() async {
    final name = _nameController.text.trim();
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

      final col = FirebaseFirestore.instance
          .collection(widget.shopCollection)
          .doc('items')
          .collection('list');

      final Map<String, dynamic> saveData = {
        'itemName': name,
        'price': price,
        'openingStock': openingStock,
        'openingStockDate': Timestamp.fromDate(_selectedDate),
        'isActive': _isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!isEdit) {
        saveData['createdAt'] = FieldValue.serverTimestamp();
        await col.add(saveData);
      } else {
        await col.doc(widget.existingDoc!.id).update(saveData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit
                ? 'Item updated successfully'
                : 'Item added successfully'),
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
          colorScheme: const ColorScheme.light(primary: Color(0xFF1565C0)),
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
              borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
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
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
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
                        color: Colors.blue.shade50.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade100.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.storefront_rounded, size: 20, color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Adding to: ${widget.shopName}',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blue.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

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
                            activeTrackColor: const Color(0xFF1565C0),
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
                  backgroundColor: const Color(0xFF1565C0),
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
