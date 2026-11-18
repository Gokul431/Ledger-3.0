import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Bag denominations (kgs) for the New Stock (IN) dialog.
const List<int> kNewStockBagSizes = [25, 26, 10, 5, 1];

/// Renders a bag count without a trailing ".0" for whole numbers.
String _formatCount(double count) =>
    count % 1 == 0 ? count.toInt().toString() : count.toString();

// ─── Stock IN Result ──────────────────────────────────────────────────────────

class StockInResult {
  final double totalQty;
  final List<Map<String, dynamic>> bagEntries;
  const StockInResult(this.totalQty, this.bagEntries);
}

// ─── Stock IN Page ────────────────────────────────────────────────────────────

class StockInPage extends StatefulWidget {
  final String itemName;
  final double openingStock;
  final double totalIn;
  final double totalOut;
  final List<Map<String, dynamic>>? initialBags;
  final bool isViewMode;
  final int? loadNumber;
  final bool isReadOnly;
  final List<int> bagSizes;
  final double? price;

  const StockInPage({
    super.key,
    required this.itemName,
    required this.openingStock,
    required this.totalIn,
    required this.totalOut,
    this.initialBags,
    this.isViewMode = false,
    this.loadNumber,
    this.isReadOnly = false,
    this.bagSizes = kNewStockBagSizes,
    this.price,
  });

  @override
  State<StockInPage> createState() => _StockInPageState();
}

class _StockInPageState extends State<StockInPage> {
  late final List<TextEditingController> _controllers;

  double get _currentStock =>
      widget.openingStock + widget.totalIn - widget.totalOut;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.bagSizes.length,
      (_) => TextEditingController(),
    );
    // Pre-fill controllers if viewing an existing load
    if (widget.initialBags != null) {
      for (int i = 0; i < widget.bagSizes.length; i++) {
        final size = widget.bagSizes[i];
        final match = widget.initialBags!
            .where((b) => (b['bagSize'] as num?)?.toInt() == size)
            .firstOrNull;
        if (match != null) {
          final count = (match['bags'] as num?)?.toDouble() ?? 0;
          if (count > 0) _controllers[i].text = _formatCount(count);
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  double _count(int i) => double.tryParse(_controllers[i].text) ?? 0;

  double get _totalIn {
    double t = 0;
    for (int i = 0; i < widget.bagSizes.length; i++) {
      t += _count(i) * widget.bagSizes[i];
    }
    return t;
  }

  void _submit() {
    if (_totalIn <= 0) return;
    final bagEntries = <Map<String, dynamic>>[];
    for (int i = 0; i < widget.bagSizes.length; i++) {
      final c = _count(i);
      if (c > 0) {
        bagEntries.add({
          'bagSize': widget.bagSizes[i],
          'bags': c,
          'kgs': c * widget.bagSizes[i],
        });
      }
    }
    Navigator.pop(context, StockInResult(_totalIn, bagEntries));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final fmtMoney = NumberFormat('#,##,##0.00');
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    final totalIn = _totalIn;
    final valueIn = widget.price != null ? totalIn * widget.price! : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isViewMode
                  ? 'Load ${widget.loadNumber ?? ''}'
                  : 'New Stock',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            Text(
              widget.itemName,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey[200]),
        ),
      ),
      // Full width, single column — the bag rows below flex their input
      // field to fill the row instead of leaving blank space on tablet.
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              children: [
                // ── Current stock ──
                _InfoCard(
                  label: 'Stock Available',
                  value: '${fmt.format(_currentStock)} kg',
                  valueColor: _currentStock <= 0
                      ? const Color(0xFFD32F2F)
                      : const Color(0xFF455A64),
                ),
                const SizedBox(height: 20),

                // ── Column headers ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 76,
                        child: Text(
                          'Bag Size',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'No. of Bags',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 100,
                        child: Text(
                          'Total',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Text(
                    'Tip: a number here means bags of that size (e.g. 5.5 in the 10kg row = 55kg). For loose kg, type it in the 1kg row.',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Bag rows ──
                ...List.generate(widget.bagSizes.length, (i) {
                  final size = widget.bagSizes[i];
                  final count = _count(i);
                  final kgs = count * size;
                  final hasValue = count > 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: hasValue
                          ? const Border(
                              left: BorderSide(
                                color: Color(0xFF455A64),
                                width: 3,
                              ),
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Bag size — fixed width, doesn't stretch
                        SizedBox(
                          width: 76,
                          child: Text(
                            '$size kg',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // No. of bags — flexible, fills the row on wide
                        // screens (a bigger, easier target) instead of
                        // leaving blank space.
                        Expanded(
                          child: TextField(
                            controller: _controllers[i],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}'),
                              ),
                            ],
                            readOnly: widget.isReadOnly,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[300],
                              ),
                              filled: true,
                              fillColor: widget.isReadOnly
                                  ? Colors.grey[100]
                                  : const Color(0xFFF5F6FA),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey[200]!,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey[200]!,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF455A64),
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: widget.isReadOnly
                                ? null
                                : (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Total kgs — fixed width, right aligned
                        SizedBox(
                          width: 100,
                          child: Text(
                            hasValue ? '${fmt.format(kgs)} kg' : '—',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                // ── Total summary ──
                if (totalIn > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: const Border(
                        left: BorderSide(color: Color(0xFF455A64), width: 4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total IN',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            Text(
                              '${fmt.format(totalIn)} kg',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        if (valueIn != null) ...[
                          const SizedBox(height: 10),
                          Divider(color: Colors.grey[200], height: 1),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Stock value',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                              Text(
                                '₹${fmtMoney.format(valueIn)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Submit / Update button (hidden when read-only) ──
          if (!widget.isReadOnly)
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: totalIn > 0 ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF455A64),
                    disabledBackgroundColor: Colors.grey[200],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    widget.isViewMode
                        ? (totalIn > 0
                              ? 'Update ${fmt.format(totalIn)} kg'
                              : 'Enter Bag Quantities')
                        : (totalIn > 0
                              ? 'Add ${fmt.format(totalIn)} kg'
                              : 'Enter Bag Quantities'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Stock OUT Result ─────────────────────────────────────────────────────────

class StockOutResult {
  final double totalQty;
  final List<Map<String, dynamic>> bagEntries;
  const StockOutResult(this.totalQty, this.bagEntries);
}

// ─── Stock OUT Page ───────────────────────────────────────────────────────────

class StockOutPage extends StatefulWidget {
  final String itemName;
  final double available;
  final List<int> bagSizes;
  final Map<int, double>? initialBags;
  final bool isViewMode;
  final bool isReadOnly;
  final double? price;

  const StockOutPage({
    super.key,
    required this.itemName,
    required this.available,
    required this.bagSizes,
    this.initialBags,
    this.isViewMode = false,
    this.isReadOnly = false,
    this.price,
  });

  @override
  State<StockOutPage> createState() => _StockOutPageState();
}

class _StockOutPageState extends State<StockOutPage> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.bagSizes.length,
      (_) => TextEditingController(),
    );
    if (widget.initialBags != null) {
      for (int i = 0; i < widget.bagSizes.length; i++) {
        final count = widget.initialBags![widget.bagSizes[i]] ?? 0;
        if (count > 0) _controllers[i].text = _formatCount(count);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  double _count(int i) => double.tryParse(_controllers[i].text) ?? 0;

  /// Total entered here = Closing Stock (what's left), not what was sold.
  double get _totalClosing {
    double t = 0;
    for (int i = 0; i < widget.bagSizes.length; i++) {
      t += _count(i) * widget.bagSizes[i];
    }
    return t;
  }

  /// Sold = Available (Opening + New Stock) − Closing Stock entered.
  double get _soldDerived =>
      (widget.available - _totalClosing).clamp(0.0, widget.available);

  bool get _exceedsAvailable => _totalClosing > widget.available;

  Future<void> _submit() async {
    if (_exceedsAvailable) return;
    // Closing 0 kg is valid (everything sold / no stock left), but confirm
    // it so an empty form isn't saved by accident.
    if (_totalClosing <= 0) {
      final fmt = NumberFormat('#,##0.##');
      final fmtMoney = NumberFormat('#,##,##0.00');
      final sold = widget.available;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No stock left?'),
          content: Text(
            sold > 0
                ? 'Closing stock will be saved as 0 kg.\n\n'
                    'All ${fmt.format(sold)} kg will be counted as sold'
                    '${widget.price != null ? ' (₹${fmtMoney.format(sold * widget.price!)})' : ''}.'
                : 'Closing stock will be saved as 0 kg.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save 0 kg'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final bagEntries = <Map<String, dynamic>>[];
    for (int i = 0; i < widget.bagSizes.length; i++) {
      final c = _count(i);
      if (c > 0) {
        bagEntries.add({
          'bagSize': widget.bagSizes[i],
          'bags': c,
          'kgs': c * widget.bagSizes[i],
        });
      }
    }
    Navigator.pop(context, StockOutResult(_totalClosing, bagEntries));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final fmtMoney = NumberFormat('#,##,##0.00');
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    final totalClosing = _totalClosing;
    final exceedsAvailable = _exceedsAvailable;
    final soldDerived = _soldDerived;
    final salesDerived = widget.price != null
        ? soldDerived * widget.price!
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Closing Stock',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            Text(
              widget.itemName,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey[200]),
        ),
      ),
      // Full width, single column — the bag rows below flex their input
      // field to fill the row instead of leaving blank space on tablet.
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              children: [
                // ── Available stock ──
                _InfoCard(
                  label: 'Stock Available',
                  value: '${fmt.format(widget.available)} kg',
                  valueColor: widget.available <= 0
                      ? const Color(0xFFD32F2F)
                      : const Color(0xFF455A64),
                ),
                const SizedBox(height: 20),

                // ── Column headers ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 76,
                        child: Text(
                          'Bag Size',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'No. of Bags',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 100,
                        child: Text(
                          'Total',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Text(
                    'Enter the stock remaining (closing stock) — count the bags left of each size. The app works out how much was sold from this. For loose kg, type it in the 1kg row.',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Bag rows ──
                ...List.generate(widget.bagSizes.length, (i) {
                  final size = widget.bagSizes[i];
                  final count = _count(i);
                  final kgs = count * size;
                  final hasValue = count > 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: hasValue
                          ? const Border(
                              left: BorderSide(
                                color: Color(0xFF455A64),
                                width: 3,
                              ),
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Bag size — fixed width, doesn't stretch
                        SizedBox(
                          width: 76,
                          child: Text(
                            '$size kg',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // No. of bags — flexible, fills the row on wide
                        // screens (a bigger, easier target) instead of
                        // leaving blank space.
                        Expanded(
                          child: TextField(
                            controller: _controllers[i],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}'),
                              ),
                            ],
                            readOnly: widget.isReadOnly,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[300],
                              ),
                              filled: true,
                              fillColor: widget.isReadOnly
                                  ? Colors.grey[100]
                                  : const Color(0xFFF5F6FA),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey[200]!,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey[200]!,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF455A64),
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: widget.isReadOnly
                                ? null
                                : (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Total kgs — fixed width, right aligned
                        SizedBox(
                          width: 100,
                          child: Text(
                            hasValue ? '${fmt.format(kgs)} kg' : '—',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                // ── Closing Stock summary ──
                if (totalClosing > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border(
                        left: BorderSide(
                          color: exceedsAvailable
                              ? const Color(0xFFD32F2F)
                              : const Color(0xFF455A64),
                          width: 4,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Closing Stock (left)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${fmt.format(totalClosing)} kg',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: exceedsAvailable
                                        ? const Color(0xFFD32F2F)
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            if (exceedsAvailable)
                              Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: Color(0xFFD32F2F),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Exceeds\navailable',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        if (!exceedsAvailable) ...[
                          const SizedBox(height: 10),
                          Divider(color: Colors.grey[200], height: 1),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Sold today',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                              Text(
                                '${fmt.format(soldDerived)} kg',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          if (salesDerived != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Sales value',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                Text(
                                  '₹${fmtMoney.format(salesDerived)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Submit / Update button (hidden when read-only) ──
          if (!widget.isReadOnly)
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: !exceedsAvailable ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF455A64),
                    disabledBackgroundColor: Colors.grey[200],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    exceedsAvailable
                        ? 'More than available stock'
                        : totalClosing <= 0
                        ? (widget.isViewMode
                              ? 'Update to 0 kg (No Stock Left)'
                              : 'Save 0 kg Closing (No Stock Left)')
                        : widget.isViewMode
                        ? 'Update ${fmt.format(totalClosing)} kg Closing'
                        : 'Save ${fmt.format(totalClosing)} kg Closing',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _InfoCard({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
