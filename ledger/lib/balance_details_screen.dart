import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 🔹 Full-screen balance details screen with rich UI, matching app style
class BalanceDetailsScreen extends StatefulWidget {
  final String shopCollection;
  final String customerId;

  const BalanceDetailsScreen({
    super.key,
    required this.shopCollection,
    required this.customerId,
  });

  @override
  State<BalanceDetailsScreen> createState() => _BalanceDetailsScreenState();
}

/// Stateful purely so the Firestore work below can be started once in
/// [initState]. As a StatelessWidget the future was built inline in `build()`,
/// so any rebuild — a rotation, the keyboard opening — refetched the customer
/// and every one of their transactions and threw the screen back to a spinner.
class _BalanceDetailsScreenState extends State<BalanceDetailsScreen> {
  late final Future<Map<String, dynamic>> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _loadDetails();
  }

  String _formatAmount(double amount) {
    return NumberFormat('#,##,##0.00').format(amount);
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return DateFormat('dd-MMM-yyyy').format(date);
  }

  /// Loads the customer's opening amount and walks their transactions to build
  /// the running-balance rows.
  Future<Map<String, dynamic>> _loadDetails() async {
    final customerSnapshot = await FirebaseFirestore.instance
        .collection(widget.shopCollection)
        .doc('customers')
        .collection('list')
        .doc(widget.customerId)
        .get();

    final customerData = (customerSnapshot.data() ?? <String, dynamic>{});
    final openingAmount = (customerData['openingAmount'] ?? 0).toDouble();

    final txSnapshot = await FirebaseFirestore.instance
        .collection(widget.shopCollection)
        .doc('customers')
        .collection('list')
        .doc(widget.customerId)
        .collection('transactions')
        .orderBy('createdAt')
        .get();

    double balance = openingAmount;
    double totalIn = 0;
    double totalOut = 0;

    final List<Map<String, dynamic>> rows = [];

    for (final doc in txSnapshot.docs) {
      final data = doc.data();
      final amount = (data['amount'] ?? 0).toDouble();
      final isCredit = data['isCredit'] == true;
      final createdAt = data['createdAt'] as Timestamp?;
      final start = balance;

      if (isCredit) {
        balance += amount;
        totalOut += amount;
      } else {
        balance -= amount;
        totalIn += amount;
      }

      rows.add({
        'date': createdAt != null ? _formatDate(createdAt) : 'N/A',
        'type': isCredit ? 'Given on credit' : 'Received from customer',
        'amount': amount,
        'start': start,
        'end': balance,
      });
    }

    return {
      'opening': openingAmount,
      'current': balance,
      'totalIn': totalIn,
      'totalOut': totalOut,
      'rows': rows,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
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
          'Balance details',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: Text(
                'Unable to load balance details.',
                style: TextStyle(fontSize: 14),
              ),
            );
          }

          final data = snapshot.data!;
          final opening = data['opening'] as double;
          final current = data['current'] as double;
          final totalIn = data['totalIn'] as double;
          final totalOut = data['totalOut'] as double;
          final rows = (data['rows'] as List).cast<Map<String, dynamic>>();

          return SingleChildScrollView(
            // Extra bottom space so the last entry clears the iPhone home bar.
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Simple calculation: opening + credit − received = now ──
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How the balance is calculated',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _calcRow(
                        'Old pending amount (opening)',
                        '₹${_formatAmount(opening)}',
                        Colors.grey[900]!,
                      ),
                      _calcRow(
                        '+ Given on credit',
                        '₹${_formatAmount(totalOut)}',
                        Colors.red[700]!,
                      ),
                      _calcRow(
                        '− Received from customer',
                        '₹${_formatAmount(totalIn)}',
                        Colors.green[700]!,
                      ),
                      const Divider(height: 18),
                      _statusRow(current),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // ── Short help, collapsed by default ──
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                      childrenPadding:
                          const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      leading: Icon(
                        Icons.help_outline,
                        color: Colors.orange[800],
                        size: 20,
                      ),
                      title: const Text(
                        'How to read this',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      children: const [
                        _HelpLine(
                          icon: Icons.arrow_downward,
                          color: Colors.green,
                          text:
                              'Received from customer: customer paid money. Balance goes DOWN.',
                        ),
                        _HelpLine(
                          icon: Icons.arrow_upward,
                          color: Colors.red,
                          text:
                              'Given on credit: customer took goods/money without paying. Balance goes UP.',
                        ),
                        _HelpLine(
                          icon: Icons.circle,
                          color: Colors.red,
                          text: 'Red balance: customer still owes the shop.',
                        ),
                        _HelpLine(
                          icon: Icons.circle,
                          color: Colors.green,
                          text:
                              'Green "Advance": customer paid extra. Check for a payment entered twice.',
                        ),
                        _HelpLine(
                          icon: Icons.circle,
                          color: Colors.grey,
                          text: 'Settled: nothing pending.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Entry by entry',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  child: rows.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 56,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'No transactions yet',
                                style:
                                    theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Transactions will appear here once added.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[500],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final r = rows[index];
                            final amount = r['amount'] as double;
                            final isCredit =
                                (r['type'] as String) == 'Given on credit';
                            final Color txColor = isCredit
                                ? Colors.red[700]!
                                : Colors.green[700]!;

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 5,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Expanded so a long label never
                                      // pushes into the amount on small
                                      // phones.
                                      Expanded(
                                        child: Row(
                                        children: [
                                          Container(
                                            width: 30,
                                            height: 30,
                                            decoration: BoxDecoration(
                                              color:
                                                  txColor.withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              isCredit
                                                  ? Icons.arrow_upward
                                                  : Icons.arrow_downward,
                                              size: 18,
                                              color: txColor,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                r['type'] as String,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                r['date'] as String,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                          ),
                                        ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '₹${_formatAmount(amount)}',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: txColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Balance before: ${_balanceText(r['start'] as double)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${isCredit ? '+' : '−'} ₹${_formatAmount(amount)}  →  Balance after: ${_balanceText(r['end'] as double)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// "₹26,160.00 (owes)", "₹2,340.00 advance" or "₹0.00 (settled)".
  String _balanceText(double v) {
    final r = (v * 100).roundToDouble() / 100;
    if (r > 0) return '₹${_formatAmount(r)} (owes)';
    if (r < 0) return '₹${_formatAmount(r.abs())} advance';
    return '₹0.00 (settled)';
  }

  Widget _calcRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(double current) {
    final r = (current * 100).roundToDouble() / 100;
    final String label;
    final String note;
    final Color color;
    if (r > 0) {
      label = 'Balance now: customer owes';
      note = 'Customer has to pay this amount.';
      color = Colors.red[700]!;
    } else if (r < 0) {
      label = 'Balance now: Advance (extra paid)';
      note = 'Customer paid more than owed. Check for a payment entered twice.';
      color = Colors.green[700]!;
    } else {
      label = 'Balance now: Settled';
      note = 'Nothing pending.';
      color = Colors.grey[700]!;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            Text(
              '₹${_formatAmount(r.abs())}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(note, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

class _HelpLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _HelpLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}


