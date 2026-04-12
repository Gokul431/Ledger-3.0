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

    // Fetch all 30 days in parallel, nulls for failures
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

  @override
  Widget build(BuildContext context) {
    final fmtMoney = NumberFormat('#,##,##0.00');

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1976D2), Color(0xFF4285F4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.itemName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            Text(
              '₹${fmtMoney.format(widget.price)} per kg  •  Last 30 days',
              style:
                  TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
      backgroundColor: const Color(0xFFF5F6FA),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4285F4)))
          : _history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No history found',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Stock entries will appear here',
                        style:
                            TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final record = _history[index];
                    final date = record['date'] as DateTime;
                    final dateStr = record['dateStr'] as String;
                    final data = record['data'] as Map<String, dynamic>;

                    final openingStock =
                        (data['openingStock'] ?? 0).toDouble();
                    final totalIn = (data['totalIn'] ?? 0).toDouble();
                    final totalOut = (data['totalOut'] ?? 0).toDouble();
                    final closingStock =
                        (data['closingStock'] ?? 0).toDouble();
                    final salesValue = (data['salesValue'] ?? 0).toDouble();
                    final isClosed = data['isClosed'] ?? false;
                    final inEntries =
                        data['inEntries'] as List<dynamic>? ?? [];
                    final outEntries =
                        data['outEntries'] as List<dynamic>? ?? [];

                    final fmt = NumberFormat('#,##0.##');
                    final todayStr = DateFormat('dd-MMM-yyyy')
                        .format(widget.currentDate);
                    final isToday = dateStr == todayStr;

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: isToday
                            ? Border.all(
                                color: const Color(0xFF4285F4), width: 2)
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Date header row
                            Row(
                              children: [
                                Icon(Icons.calendar_today_outlined,
                                    size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 6),
                                Text(
                                  DateFormat('dd MMM yyyy').format(date),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87),
                                ),
                                if (isToday) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4285F4)
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'Today',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF4285F4)),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isClosed
                                        ? Colors.orange[50]
                                        : Colors.green[50],
                                    borderRadius:
                                        BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isClosed
                                          ? Colors.orange[300]!
                                          : Colors.green[300]!,
                                    ),
                                  ),
                                  child: Text(
                                    isClosed ? 'Closed' : 'Open',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isClosed
                                            ? Colors.orange[700]
                                            : Colors.green[700]),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),

                            // Stock stats
                            Row(
                              children: [
                                _statCell('Opening',
                                    '${fmt.format(openingStock)} kgs',
                                    Colors.blue[700]!),
                                _statCell('IN',
                                    '+${fmt.format(totalIn)} kgs',
                                    Colors.green[700]!),
                                _statCell('OUT',
                                    '-${fmt.format(totalOut)} kgs',
                                    Colors.orange[700]!),
                                _statCell('Closing',
                                    '${fmt.format(closingStock)} kgs',
                                    const Color(0xFF4285F4)),
                              ],
                            ),

                            // Sales value
                            if (salesValue > 0) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.green[200]!),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Sales Value',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      '₹${fmtMoney.format(salesValue)}',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.green[700]),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // IN entries
                            if (inEntries.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildEntriesSection(
                                'Stock IN',
                                Icons.add_circle_outline,
                                Colors.green[700]!,
                                Colors.green[50]!,
                                Colors.green[200]!,
                                inEntries.map((e) {
                                  final qty =
                                      (e['qty'] as num?)?.toDouble() ?? 0;
                                  final ts = e['timestamp'] as String?;
                                  final timeStr = _parseTime(ts);
                                  return '+${fmt.format(qty)} kgs'
                                      '${timeStr.isNotEmpty ? '  •  $timeStr' : ''}';
                                }).toList(),
                              ),
                            ],

                            // OUT entries
                            if (outEntries.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildEntriesSection(
                                'Stock OUT',
                                Icons.remove_circle_outline,
                                Colors.orange[700]!,
                                Colors.orange[50]!,
                                Colors.orange[200]!,
                                outEntries.map((e) {
                                  final totalQty =
                                      (e['totalQty'] as num?)?.toDouble() ??
                                          0;
                                  final bags =
                                      e['bags'] as List<dynamic>? ?? [];
                                  final ts = e['timestamp'] as String?;
                                  final timeStr = _parseTime(ts);
                                  final bagStr = bags
                                      .map((b) =>
                                          '${b['bagSize']}kg×${b['bags']}')
                                      .join(', ');
                                  return '-${fmt.format(totalQty)} kgs  ($bagStr)'
                                      '${timeStr.isNotEmpty ? '  •  $timeStr' : ''}';
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _parseTime(String? ts) {
    if (ts == null) return '';
    try {
      return DateFormat('hh:mm a').format(DateTime.parse(ts).toLocal());
    } catch (_) {
      return '';
    }
  }

  Widget _buildEntriesSection(
    String title,
    IconData icon,
    Color color,
    Color bgColor,
    Color borderColor,
    List<String> entries,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...entries.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e.key + 1}.  ',
                          style: TextStyle(
                              fontSize: 12,
                              color: color,
                              fontWeight: FontWeight.w600)),
                      Expanded(
                        child: Text(e.value,
                            style: TextStyle(fontSize: 12, color: color)),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _statCell(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
