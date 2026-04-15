import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// ─── Stock IN Page ───────────────────────────────────────────────────────────

class StockInPage extends StatefulWidget {
  final String itemName;
  final double openingStock;
  final double totalIn;
  final double totalOut;

  const StockInPage({
    super.key,
    required this.itemName,
    required this.openingStock,
    required this.totalIn,
    required this.totalOut,
  });

  @override
  State<StockInPage> createState() => _StockInPageState();
}

class _StockInPageState extends State<StockInPage> {
  final _controller = TextEditingController();
  double _enteredQty = 0;

  double get _currentStock =>
      widget.openingStock + widget.totalIn - widget.totalOut;
  double get _newClosing => _currentStock + _enteredQty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_enteredQty <= 0) return;
    Navigator.pop(context, _enteredQty);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final bottom = MediaQuery.of(context).viewInsets.bottom;

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
            const Text(
              'Stock IN',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
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
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, bottom + 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Current stock card ──
            _InfoCard(
              label: 'Current Stock',
              value: '${fmt.format(_currentStock)} kgs',
              valueColor: _currentStock <= 0
                  ? const Color(0xFFD32F2F)
                  : const Color(0xFF1565C0),
            ),

            const SizedBox(height: 20),

            // ── Input ──
            const Text(
              'Quantity Arriving',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[300]),
                suffixText: 'kgs',
                suffixStyle: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[500]),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFF1565C0), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 20),
              ),
              onChanged: (v) {
                setState(() => _enteredQty = double.tryParse(v) ?? 0);
              },
            ),

            // ── Live preview ──
            if (_enteredQty > 0) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                      left: const BorderSide(
                          color: Color(0xFF1565C0), width: 4)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('After this entry',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _PreviewCell('Before',
                            '${fmt.format(_currentStock)} kgs',
                            Colors.black54),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward,
                              size: 16, color: Colors.black38),
                        ),
                        _PreviewCell('+IN',
                            '+${fmt.format(_enteredQty)} kgs',
                            const Color(0xFF1565C0)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward,
                              size: 16, color: Colors.black38),
                        ),
                        _PreviewCell('New Stock',
                            '${fmt.format(_newClosing)} kgs',
                            Colors.black87,
                            bold: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            // ── Submit button ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _enteredQty > 0 ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  disabledBackgroundColor: Colors.grey[200],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  _enteredQty > 0
                      ? 'Add ${fmt.format(_enteredQty)} kgs'
                      : 'Enter Quantity',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stock OUT Page ──────────────────────────────────────────────────────────

class StockOutResult {
  final double totalQty;
  final List<Map<String, dynamic>> bagEntries;
  const StockOutResult(this.totalQty, this.bagEntries);
}

class StockOutPage extends StatefulWidget {
  final String itemName;
  final double available;
  final List<int> bagSizes;

  const StockOutPage({
    super.key,
    required this.itemName,
    required this.available,
    required this.bagSizes,
  });

  @override
  State<StockOutPage> createState() => _StockOutPageState();
}

class _StockOutPageState extends State<StockOutPage> {
  late final List<int> _counts;

  @override
  void initState() {
    super.initState();
    _counts = List.filled(widget.bagSizes.length, 0);
  }

  double get _totalOut {
    double t = 0;
    for (int i = 0; i < widget.bagSizes.length; i++) {
      t += _counts[i] * widget.bagSizes[i];
    }
    return t;
  }

  bool get _overStock => _totalOut > widget.available;

  void _submit() {
    if (_totalOut <= 0 || _overStock) return;
    final bagEntries = <Map<String, dynamic>>[];
    for (int i = 0; i < widget.bagSizes.length; i++) {
      if (_counts[i] > 0) {
        bagEntries.add({
          'bagSize': widget.bagSizes[i],
          'bags': _counts[i],
          'kgs': _counts[i] * widget.bagSizes[i],
        });
      }
    }
    Navigator.pop(context, StockOutResult(_totalOut, bagEntries));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final bottom = MediaQuery.of(context).viewPadding.bottom;

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
            const Text(
              'Stock OUT',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
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
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              children: [
                // ── Available stock ──
                _InfoCard(
                  label: 'Available Stock',
                  value: '${fmt.format(widget.available)} kgs',
                  valueColor: widget.available <= 0
                      ? const Color(0xFFD32F2F)
                      : const Color(0xFF1565C0),
                ),

                const SizedBox(height: 20),

                // ── Bag sizes header ──
                Row(
                  children: [
                    const Expanded(
                      child: Text('Bag Size',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54)),
                    ),
                    Text('Quantity',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54)),
                    const SizedBox(width: 8),
                    Text('Total',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54)),
                  ],
                ),
                const SizedBox(height: 8),

                // ── Bag rows ──
                ...List.generate(widget.bagSizes.length, (i) {
                  final size = widget.bagSizes[i];
                  final count = _counts[i];
                  final kgs = count * size;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: count > 0
                          ? const Border(
                              left: BorderSide(
                                  color: Color(0xFF1565C0), width: 3))
                          : Border.all(color: Colors.transparent),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 1)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$size kg',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87)),
                              if (count > 0)
                                Text('= ${fmt.format(kgs)} kgs',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500])),
                            ],
                          ),
                        ),
                        // Counter
                        _CounterButton(
                          icon: Icons.remove,
                          enabled: count > 0,
                          onTap: () =>
                              setState(() => _counts[i] = count - 1),
                        ),
                        Container(
                          width: 48,
                          alignment: Alignment.center,
                          child: Text(
                            '$count',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87),
                          ),
                        ),
                        _CounterButton(
                          icon: Icons.add,
                          enabled: true,
                          onTap: () =>
                              setState(() => _counts[i] = count + 1),
                        ),
                      ],
                    ),
                  );
                }),

                // ── Total OUT summary ──
                if (_totalOut > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border(
                        left: BorderSide(
                          color: _overStock
                              ? const Color(0xFFD32F2F)
                              : const Color(0xFF1565C0),
                          width: 4,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total OUT',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[500])),
                            const SizedBox(height: 2),
                            Text(
                              '${fmt.format(_totalOut)} kgs',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: _overStock
                                      ? const Color(0xFFD32F2F)
                                      : Colors.black87),
                            ),
                          ],
                        ),
                        if (_overStock)
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  size: 16,
                                  color: Color(0xFFD32F2F)),
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

          // ── Bottom submit ──
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 12 + bottom),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    (_totalOut > 0 && !_overStock) ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  disabledBackgroundColor: Colors.grey[200],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  _totalOut > 0 && !_overStock
                      ? 'Record ${fmt.format(_totalOut)} kgs OUT'
                      : 'Select Bags',
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

// ─── Shared widgets ──────────────────────────────────────────────────────────

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
              color: Colors.black.withOpacity(0.05),
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

class _PreviewCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;

  const _PreviewCell(this.label, this.value, this.color,
      {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _CounterButton(
      {required this.icon,
      required this.enabled,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF1565C0).withOpacity(0.08)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 18,
            color: enabled
                ? const Color(0xFF1565C0)
                : Colors.grey[300]),
      ),
    );
  }
}
