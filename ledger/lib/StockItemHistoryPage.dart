import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class StockItemHistoryPage extends StatefulWidget {
  final String shopCollection;
  final String itemId;
  final String itemName;
  final double price;
  final DateTime currentDate;

  const StockItemHistoryPage({
    super.key,
    required this.shopCollection,
    required this.itemId,
    required this.itemName,
    required this.price,
    required this.currentDate,
  });

  @override
  State<StockItemHistoryPage> createState() => _StockItemHistoryPageState();
}

class _StockItemHistoryPageState extends State<StockItemHistoryPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    const lookback = 30;
    final dates = List.generate(lookback, (i) {
      final date = widget.currentDate.subtract(Duration(days: i));
      return (date: date, str: DateFormat('dd-MMM-yyyy').format(date));
    });

    final results = await Future.wait<DocumentSnapshot<Map<String, dynamic>>?>(
      dates.map((d) => FirebaseFirestore.instance
          .collection(widget.shopCollection)
          .doc('stockLedger')
          .collection('dates')
          .doc(d.str)
          .collection('items')
          .doc(widget.itemId)
          .get()
          .then<DocumentSnapshot<Map<String, dynamic>>?>((doc) => doc)
          .catchError((_) => null)),
      eagerError: false,
    );

    final List<Map<String, dynamic>> history = [];
    for (int i = 0; i < dates.length; i++) {
      try {
        final doc = results[i];
        if (doc != null && doc.exists) {
          history.add({
            'date': dates[i].date,
            'dateStr': dates[i].str,
            'data': doc.data() as Map<String, dynamic>,
          });
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _history = history;
        _isLoading = false;
      });
    }
  }

  String _parseTime(String? ts) {
    if (ts == null) return '';
    try {
      return DateFormat('hh:mm a').format(DateTime.parse(ts).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmtMoney = NumberFormat('#,##,##0.00');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.itemName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: Colors.black87,
              ),
            ),
            Text(
              '₹${fmtMoney.format(widget.price)} per kg  •  Last 30 days',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey[200]),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        'No history found',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Stock entries will appear here',
                        style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: 24 + MediaQuery.of(context).viewPadding.bottom,
                  ),
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final record = _history[index];
                    final date = record['date'] as DateTime;
                    final dateStr = record['dateStr'] as String;
                    final data = record['data'] as Map<String, dynamic>;

                    final openingStock = (data['openingStock'] ?? 0).toDouble();
                    final totalIn = (data['totalIn'] ?? 0).toDouble();
                    final totalOut = (data['totalOut'] ?? 0).toDouble();
                    final closingStock = (data['closingStock'] ?? 0).toDouble();
                    final salesValue = (data['salesValue'] ?? 0).toDouble();
                    final isClosed = data['isClosed'] ?? false;
                    final inEntries = data['inEntries'] as List<dynamic>? ?? [];
                    final outEntries = data['outEntries'] as List<dynamic>? ?? [];

                    final fmt = NumberFormat('#,##0.##');
                    final todayStr =
                        DateFormat('dd-MMM-yyyy').format(widget.currentDate);
                    final isToday = dateStr == todayStr;

                    return _DaySection(
                      date: date,
                      isToday: isToday,
                      isClosed: isClosed,
                      openingStock: openingStock,
                      totalIn: totalIn,
                      totalOut: totalOut,
                      closingStock: closingStock,
                      salesValue: salesValue,
                      inEntries: inEntries,
                      outEntries: outEntries,
                      fmt: fmt,
                      fmtMoney: fmtMoney,
                      parseTime: _parseTime,
                      isLast: index == _history.length - 1,
                    );
                  },
                ),
    );
  }
}

class _DaySection extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final bool isClosed;
  final double openingStock;
  final double totalIn;
  final double totalOut;
  final double closingStock;
  final double salesValue;
  final List<dynamic> inEntries;
  final List<dynamic> outEntries;
  final NumberFormat fmt;
  final NumberFormat fmtMoney;
  final String Function(String?) parseTime;
  final bool isLast;

  const _DaySection({
    required this.date,
    required this.isToday,
    required this.isClosed,
    required this.openingStock,
    required this.totalIn,
    required this.totalOut,
    required this.closingStock,
    required this.salesValue,
    required this.inEntries,
    required this.outEntries,
    required this.fmt,
    required this.fmtMoney,
    required this.parseTime,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Date header ──────────────────────────────────────
        Container(
          color: Colors.grey[50],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Text(
                DateFormat('dd MMM yyyy').format(date),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isToday ? const Color(0xFF455A64) : Colors.black87,
                  letterSpacing: 0.2,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF455A64),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                isClosed ? 'Closed' : 'Open',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isClosed ? Colors.grey[500] : Colors.green[600],
                ),
              ),
            ],
          ),
        ),

        // ── Stock summary row ─────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(child: _StockStat(
                  label: 'Opening', value: '${fmt.format(openingStock)} kg')),
              _dividerDot(),
              Expanded(child: _StockStat(
                  label: 'IN',
                  value: '+${fmt.format(totalIn)} kg',
                  valueColor: totalIn > 0 ? Colors.green[700] : null)),
              _dividerDot(),
              Expanded(child: _StockStat(
                  label: 'OUT',
                  value: '-${fmt.format(totalOut)} kg',
                  valueColor: totalOut > 0 ? Colors.red[600] : null)),
              _dividerDot(),
              Expanded(child: _StockStat(
                  label: 'Closing',
                  value: '${fmt.format(closingStock)} kg',
                  valueColor: Colors.black87)),
            ],
          ),
        ),

        // ── Sales value ───────────────────────────────────────
        if (salesValue > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Text(
                  'Sales',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                const SizedBox(width: 6),
                Text(
                  '₹${fmtMoney.format(salesValue)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),

        // ── IN entries ────────────────────────────────────────
        if (inEntries.isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Stock IN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey[400],
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          ...inEntries.asMap().entries.map((e) {
            final qty = (e.value['qty'] as num?)?.toDouble() ?? 0;
            final ts = e.value['timestamp'] as String?;
            final timeStr = parseTime(ts);
            final bags = e.value['bags'] as List<dynamic>? ?? [];
            final bagStr = bags
                .where((b) => ((b['bags'] as num?)?.toInt() ?? 0) > 0)
                .map((b) => '${b['bagSize']}kg × ${b['bags']}')
                .join('  •  ');
            return _EntryRow(
              index: e.key + 1,
              qty: '+${fmt.format(qty)} kgs',
              detail: bagStr.isNotEmpty ? bagStr : null,
              time: timeStr,
              isIn: true,
            );
          }),
        ],

        // ── OUT entries ───────────────────────────────────────
        if (outEntries.isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Stock OUT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey[400],
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          ...outEntries.asMap().entries.map((e) {
            // 'soldQty' is the current schema; 'totalQty' is a legacy fallback
            // for entries recorded before the closing-stock entry change.
            final soldQty = (e.value['soldQty'] as num?)?.toDouble() ??
                (e.value['totalQty'] as num?)?.toDouble() ??
                0;
            final bags = e.value['bags'] as List<dynamic>? ?? [];
            final ts = e.value['timestamp'] as String?;
            final timeStr = parseTime(ts);
            final bagStr = bags
                .map((b) => '${b['bagSize']}kg × ${b['bags']}')
                .join('  •  ');
            return _EntryRow(
              index: e.key + 1,
              qty: '-${fmt.format(soldQty)} kgs',
              detail: bagStr.isNotEmpty ? bagStr : null,
              time: timeStr,
              isIn: false,
            );
          }),
        ],

        const SizedBox(height: 12),
        if (!isLast) Divider(height: 1, color: Colors.grey[200]),
      ],
    );
  }

  Widget _dividerDot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('·', style: TextStyle(color: Colors.grey[300], fontSize: 16)),
      );
}

class _StockStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StockStat({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[400],
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? Colors.grey[700],
          ),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  final int index;
  final String qty;
  final String? detail;
  final String time;
  final bool isIn;

  const _EntryRow({
    required this.index,
    required this.qty,
    required this.detail,
    required this.time,
    required this.isIn,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Index dot
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.grey[500],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Left accent bar
          Container(
            width: 2,
            height: detail != null ? 36 : 20,
            decoration: BoxDecoration(
              color: isIn ? Colors.green[300] : Colors.red[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      qty,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isIn ? Colors.green[700] : Colors.red[600],
                      ),
                    ),
                    if (time.isNotEmpty) ...[
                      const Spacer(),
                      Text(
                        time,
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                    ],
                  ],
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
