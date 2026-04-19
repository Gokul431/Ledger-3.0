import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

const List<int> kBagSizes = [30, 26, 10, 5, 1];

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

  const StockInPage({
    super.key,
    required this.itemName,
    required this.openingStock,
    required this.totalIn,
    required this.totalOut,
    this.initialBags,
    this.isViewMode = false,
    this.loadNumber,
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
    _controllers =
        List.generate(kBagSizes.length, (_) => TextEditingController());
    // Pre-fill controllers if viewing an existing load
    if (widget.initialBags != null) {
      for (int i = 0; i < kBagSizes.length; i++) {
        final size = kBagSizes[i];
        final match = widget.initialBags!.where(
            (b) => (b['bagSize'] as num?)?.toInt() == size).firstOrNull;
        if (match != null) {
          final count = (match['bags'] as num?)?.toInt() ?? 0;
          if (count > 0) _controllers[i].text = '$count';
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

  int _count(int i) => int.tryParse(_controllers[i].text) ?? 0;

  double get _totalIn {
    double t = 0;
    for (int i = 0; i < kBagSizes.length; i++) {
      t += _count(i) * kBagSizes[i];
    }
    return t;
  }

  void _submit() {
    if (_totalIn <= 0) return;
    final bagEntries = <Map<String, dynamic>>[];
    for (int i = 0; i < kBagSizes.length; i++) {
      final c = _count(i);
      if (c > 0) {
        bagEntries.add({
          'bagSize': kBagSizes[i],
          'bags': c,
          'kgs': c * kBagSizes[i],
        });
      }
    }
    Navigator.pop(context, StockInResult(_totalIn, bagEntries));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    final totalIn = _totalIn;

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
                    color: Colors.black87)),
            Text(widget.itemName,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey[200]),
        ),
      ),
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
                      const Expanded(
                        child: Text('Bag Size',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54)),
                      ),
                      Text('No. of Bags',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 60,
                        child: Text('Total',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── Bag rows ──
                ...List.generate(kBagSizes.length, (i) {
                  final size = kBagSizes[i];
                  final count = _count(i);
                  final kgs = count * size;
                  final hasValue = count > 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: hasValue
                          ? const Border(
                              left: BorderSide(
                                  color: Color(0xFF455A64), width: 3))
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Bag size label
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$size kg',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87)),
                              if (hasValue)
                                Text('= ${fmt.format(kgs)} kg',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500])),
                            ],
                          ),
                        ),
                        // Text field
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _controllers[i],
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            readOnly: widget.isViewMode,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87),
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: TextStyle(
                                  fontSize: 16, color: Colors.grey[300]),
                              filled: true,
                              fillColor: widget.isViewMode
                                  ? Colors.grey[100]
                                  : const Color(0xFFF5F6FA),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey[200]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey[200]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: Color(0xFF455A64), width: 2),
                              ),
                            ),
                            onChanged: widget.isViewMode
                                ? null
                                : (_) => setState(() {}),
                          ),
                        ),
                        // Total kgs
                        SizedBox(
                          width: 60,
                          child: Text(
                            hasValue ? '${fmt.format(kgs)} kg' : '',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600]),
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total IN',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                        Text(
                          '${fmt.format(totalIn)} kg',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Submit button (hidden in view mode) ──
          if (!widget.isViewMode)
            Container(
              color: Colors.white,
              padding:
                  EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
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
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    totalIn > 0
                        ? 'Add ${fmt.format(totalIn)} kg'
                        : 'Enter Bag Quantities',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
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
  final Map<int, int>? initialBags;
  final bool isViewMode;

  const StockOutPage({
    super.key,
    required this.itemName,
    required this.available,
    required this.bagSizes,
    this.initialBags,
    this.isViewMode = false,
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
        widget.bagSizes.length, (_) => TextEditingController());
    if (widget.initialBags != null) {
      for (int i = 0; i < widget.bagSizes.length; i++) {
        final count = widget.initialBags![widget.bagSizes[i]] ?? 0;
        if (count > 0) _controllers[i].text = '$count';
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

  int _count(int i) => int.tryParse(_controllers[i].text) ?? 0;

  double get _totalOut {
    double t = 0;
    for (int i = 0; i < widget.bagSizes.length; i++) {
      t += _count(i) * widget.bagSizes[i];
    }
    return t;
  }

  bool get _overStock => _totalOut > widget.available;

  void _submit() {
    if (_totalOut <= 0 || _overStock) return;
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
    Navigator.pop(context, StockOutResult(_totalOut, bagEntries));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    final totalOut = _totalOut;
    final overStock = _overStock;

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
                widget.isViewMode ? 'Closing Stock' : 'Stock Sold',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87)),
            Text(widget.itemName,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey[200]),
        ),
      ),
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
                      const Expanded(
                        child: Text('Bag Size',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54)),
                      ),
                      Text('No. of Bags',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 60,
                        child: Text('Total',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54)),
                      ),
                    ],
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
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: hasValue
                          ? const Border(
                              left: BorderSide(
                                  color: Color(0xFF455A64), width: 3))
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Bag size label
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$size kg',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87)),
                              if (hasValue)
                                Text('= ${fmt.format(kgs)} kg',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500])),
                            ],
                          ),
                        ),
                        // Text field
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _controllers[i],
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            readOnly: widget.isViewMode,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87),
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: TextStyle(
                                  fontSize: 16, color: Colors.grey[300]),
                              filled: true,
                              fillColor: widget.isViewMode
                                  ? Colors.grey[100]
                                  : const Color(0xFFF5F6FA),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey[200]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey[200]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: Color(0xFF455A64), width: 2),
                              ),
                            ),
                            onChanged: widget.isViewMode
                                ? null
                                : (_) => setState(() {}),
                          ),
                        ),
                        // Total kgs
                        SizedBox(
                          width: 60,
                          child: Text(
                            hasValue ? '${fmt.format(kgs)} kg' : '',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                // ── Total OUT summary ──
                if (totalOut > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border(
                        left: BorderSide(
                          color: overStock
                              ? const Color(0xFFD32F2F)
                              : const Color(0xFF455A64),
                          width: 4,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Sold',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[500])),
                            const SizedBox(height: 2),
                            Text(
                              '${fmt.format(totalOut)} kg',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: overStock
                                      ? const Color(0xFFD32F2F)
                                      : Colors.black87),
                            ),
                          ],
                        ),
                        if (overStock)
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  size: 16, color: Color(0xFFD32F2F)),
                              const SizedBox(width: 4),
                              Text('Exceeds\navailable',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red[700],
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Submit button (hidden in view mode) ──
          if (!widget.isViewMode)
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (totalOut > 0 && !overStock) ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF455A64),
                  disabledBackgroundColor: Colors.grey[200],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  totalOut > 0 && !overStock
                      ? 'Record ${fmt.format(totalOut)} kg Sold'
                      : 'Enter Bag Quantities',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
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

  const _InfoCard(
      {required this.label,
      required this.value,
      required this.valueColor});

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
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: valueColor)),
        ],
      ),
    );
  }
}
