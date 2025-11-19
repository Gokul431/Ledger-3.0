import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _selectedShopId;
  String _selectedShopName = '';
  List<Map<String, String>> _availableShops = [];

  // Analytics Data
  Map<String, dynamic> _ledgerStats = {};
  Map<String, dynamic> _customerStats = {};
  Map<String, dynamic> _transactionStats = {};
  List<Map<String, dynamic>> _recentTransactions = [];
  List<Map<String, dynamic>> _dailyBalances = [];
  List<Map<String, dynamic>> _topCustomers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAvailableShops();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableShops() async {
    try {
      setState(() => _isLoading = true);

      // Fetch shops from shop_list collection in Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection('shop_list')
          .get();

      List<Map<String, String>> shops = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final collectionName = data['collectionName'] ?? '';

        // ✅ Fetch shop name from the actual shop collection's Credentials document
        try {
          final credentialsDoc = await FirebaseFirestore.instance
              .collection(collectionName)
              .doc('Credentials')
              .get();

          if (credentialsDoc.exists) {
            final credentialsData = credentialsDoc.data() ?? {};
            final actualShopName =
                credentialsData['shopName'] ?? 'Unknown Shop';

            shops.add({
              'id': collectionName,
              'name': actualShopName.toUpperCase(),
            });

            debugPrint('✅ Shop loaded: $collectionName → $actualShopName');
          } else {
            debugPrint('❌ No Credentials document for $collectionName');
          }
        } catch (e) {
          debugPrint('❌ Shop $collectionName not accessible: $e');
        }
      }

      setState(() {
        _availableShops = shops;
        if (shops.isNotEmpty) {
          _selectedShopId = shops.first['id'];
          _selectedShopName = shops.first['name']!;
        }
      });

      if (_selectedShopId != null) {
        _loadAnalyticsData();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading shops: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAnalyticsData() async {
    if (_selectedShopId == null) return;

    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _loadLedgerAnalytics(),
        _loadCustomerAnalytics(),
        _loadTransactionAnalytics(),
        _loadRecentTransactions(),
        _loadDailyBalances(),
      ]);
    } catch (e) {
      debugPrint('Error loading analytics: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLedgerAnalytics() async {
    try {
      final now = DateTime.now();
      final thisMonth = DateTime(now.year, now.month, 1);
      final todayString = DateFormat('dd-MMM-yyyy').format(now);

      final datesSnapshot = await FirebaseFirestore.instance
          .collection(_selectedShopId!)
          .doc('ledgers')
          .collection('dates')
          .orderBy('createdAt', descending: true)
          .get();

      double totalClosingBalance = 0;
      double todayBalance = 0;
      double totalOpeningBalance = 0;
      int totalDays = datesSnapshot.docs.length;
      int thisMonthDays = 0;
      double thisMonthBalance = 0;
      int openLedgers = 0;
      int closedLedgers = 0;

      for (var doc in datesSnapshot.docs) {
        final data = doc.data();
        final closingBalance = (data['closingBalance'] ?? 0).toDouble();
        final openingBalance = (data['openingBalance'] ?? 0).toDouble();
        final status = data['status'] ?? '';
        final ledgerDate = data['ledgerDate'] ?? '';

        totalClosingBalance += closingBalance;
        totalOpeningBalance += openingBalance;

        if (status == 'Open') openLedgers++;
        if (status == 'Closed') closedLedgers++;

        if (ledgerDate == todayString) {
          todayBalance = closingBalance;
        }

        try {
          final parsedDate = DateFormat('dd-MMM-yyyy').parse(ledgerDate);
          if (parsedDate.isAfter(thisMonth)) {
            thisMonthDays++;
            thisMonthBalance += closingBalance;
          }
        } catch (e) {
          debugPrint('Error parsing date: $ledgerDate');
        }
      }

      setState(() {
        _ledgerStats = {
          'currentBalance': todayBalance,
          'totalClosingBalance': totalClosingBalance,
          'totalOpeningBalance': totalOpeningBalance,
          'totalDays': totalDays,
          'thisMonthDays': thisMonthDays,
          'thisMonthBalance': thisMonthBalance,
          'avgDailyBalance': totalDays > 0
              ? totalClosingBalance / totalDays
              : 0,
          'profitLoss': totalClosingBalance - totalOpeningBalance,
          'openLedgers': openLedgers,
          'closedLedgers': closedLedgers,
        };
      });
    } catch (e) {
      debugPrint('Error loading ledger analytics: $e');
    }
  }

  Future<void> _loadCustomerAnalytics() async {
    try {
      final customerSnapshot = await FirebaseFirestore.instance
          .collection(_selectedShopId!)
          .doc('customers')
          .collection('list')
          .where('status', isEqualTo: 'Active')
          .get();

      int totalCustomers = customerSnapshot.docs.length;
      int retailCustomers = 0;
      int wholesaleCustomers = 0;
      double totalOpeningAmount = 0;
      List<Map<String, dynamic>> customers = [];

      for (var doc in customerSnapshot.docs) {
        final data = doc.data();
        final customerType = data['customerType'] ?? '';
        final openingAmount = (data['openingAmount'] ?? 0).toDouble();
        final customerName = data['customerName'] ?? 'Unknown';

        totalOpeningAmount += openingAmount;

        if (customerType == 'Retail') retailCustomers++;
        if (customerType == 'Wholesale') wholesaleCustomers++;

        customers.add({
          'id': doc.id,
          'name': customerName,
          'type': customerType,
          'openingAmount': openingAmount,
          'mobile': data['mobile'] ?? '',
          'openingDate': data['openingDate'] ?? '',
        });
      }

      customers.sort(
        (a, b) => (b['openingAmount'] as double).compareTo(
          a['openingAmount'] as double,
        ),
      );

      setState(() {
        _customerStats = {
          'totalCustomers': totalCustomers,
          'retailCustomers': retailCustomers,
          'wholesaleCustomers': wholesaleCustomers,
          'totalOpeningAmount': totalOpeningAmount,
          'avgOpeningAmount': totalCustomers > 0
              ? totalOpeningAmount / totalCustomers
              : 0,
        };
        _topCustomers = customers.take(5).toList();
      });
    } catch (e) {
      debugPrint('Error loading customer analytics: $e');
    }
  }

  Future<void> _loadTransactionAnalytics() async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));

      final transactionSnapshot = await FirebaseFirestore.instance
          .collection(_selectedShopId!)
          .doc('ledgers')
          .collection('transactions')
          .orderBy('createdAt', descending: true)
          .get();

      double totalCredit = 0;
      double totalDebit = 0;
      double monthCredit = 0;
      double monthDebit = 0;
      double weekCredit = 0;
      double weekDebit = 0;
      int totalTransactions = transactionSnapshot.docs.length;
      int monthTransactions = 0;
      int weekTransactions = 0;

      Map<String, int> transactionTypes = {};

      for (var doc in transactionSnapshot.docs) {
        final data = doc.data();
        final amount = (data['amount'] ?? 0).toDouble();
        final isCredit = data['isCredit'] ?? false;
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
        final transactionType = data['transactionType'] ?? 'General';

        transactionTypes[transactionType] =
            (transactionTypes[transactionType] ?? 0) + 1;

        if (isCredit) {
          totalCredit += amount;
        } else {
          totalDebit += amount;
        }

        if (createdAt != null) {
          if (createdAt.isAfter(startOfMonth)) {
            monthTransactions++;
            if (isCredit) {
              monthCredit += amount;
            } else {
              monthDebit += amount;
            }
          }

          if (createdAt.isAfter(startOfWeek)) {
            weekTransactions++;
            if (isCredit) {
              weekCredit += amount;
            } else {
              weekDebit += amount;
            }
          }
        }
      }

      setState(() {
        _transactionStats = {
          'totalCredit': totalCredit,
          'totalDebit': totalDebit,
          'monthCredit': monthCredit,
          'monthDebit': monthDebit,
          'weekCredit': weekCredit,
          'weekDebit': weekDebit,
          'totalTransactions': totalTransactions,
          'monthTransactions': monthTransactions,
          'weekTransactions': weekTransactions,
          'netFlow': totalCredit - totalDebit,
          'monthNetFlow': monthCredit - monthDebit,
          'transactionTypes': transactionTypes,
        };
      });
    } catch (e) {
      debugPrint('Error loading transaction analytics: $e');
    }
  }

  Future<void> _loadRecentTransactions() async {
    try {
      final transactionSnapshot = await FirebaseFirestore.instance
          .collection(_selectedShopId!)
          .doc('ledgers')
          .collection('transactions')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      List<Map<String, dynamic>> transactions = [];

      for (var doc in transactionSnapshot.docs) {
        final data = doc.data();
        transactions.add({
          'id': doc.id,
          'amount': data['amount'] ?? 0,
          'isCredit': data['isCredit'] ?? false,
          'transactionType': data['transactionType'] ?? 'General',
          'ledgerName': data['ledgerName'] ?? '',
          'description': data['description'] ?? '',
          'ledgerDate': data['ledgerDate'] ?? '',
          'createdAt': data['createdAt'],
        });
      }

      setState(() {
        _recentTransactions = transactions;
      });
    } catch (e) {
      debugPrint('Error loading recent transactions: $e');
    }
  }

  Future<void> _loadDailyBalances() async {
    try {
      final datesSnapshot = await FirebaseFirestore.instance
          .collection(_selectedShopId!)
          .doc('ledgers')
          .collection('dates')
          .orderBy('createdAt', descending: true)
          .limit(7)
          .get();

      List<Map<String, dynamic>> balances = [];

      for (var doc in datesSnapshot.docs) {
        final data = doc.data();
        balances.add({
          'date': data['ledgerDate'] ?? doc.id,
          'opening': data['openingBalance'] ?? 0,
          'closing': data['closingBalance'] ?? 0,
          'status': data['status'] ?? 'Open',
          'saleValue': data['saleValue'] ?? 0,
          'note': data['note'] ?? '',
          'createdBy': data['createdBy'] ?? '',
          'closedAt': data['closedAt'],
        });
      }

      setState(() {
        _dailyBalances = balances;
      });
    } catch (e) {
      debugPrint('Error loading daily balances: $e');
    }
  }

  String _formatCurrency(double amount) {
    return '₹${NumberFormat('#,##,##0').format(amount.abs())}';
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1976D2)),
      );
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<String>(
            value: _selectedShopId,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF1976D2),
                  width: 2,
                ),
              ),
              prefixIcon: Icon(Icons.store, color: Colors.grey[600], size: 20),
            ),
            items: _availableShops.map((shop) {
              return DropdownMenuItem<String>(
                value: shop['id'],
                child: Text(shop['name']!),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedShopId = value;
                  _selectedShopName = _availableShops.firstWhere(
                    (shop) => shop['id'] == value,
                  )['name']!;
                });
                _loadAnalyticsData();
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Current Balance',
          value: _formatCurrency(_ledgerStats['currentBalance'] ?? 0),
          subtitle: 'Latest ledger balance',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Total Profit/Loss',
          value: (_ledgerStats['profitLoss'] ?? 0) >= 0
              ? '+${_formatCurrency(_ledgerStats['profitLoss'] ?? 0)}'
              : '-${_formatCurrency((_ledgerStats['profitLoss'] ?? 0).abs())}',
          subtitle: 'Total closing - opening balance',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Total Customers',
          value: '${_customerStats['totalCustomers'] ?? 0}',
          subtitle: 'Active customers',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Active Ledger Days',
          value: '${_ledgerStats['totalDays'] ?? 0}',
          subtitle:
              '${_ledgerStats['openLedgers'] ?? 0} open, ${_ledgerStats['closedLedgers'] ?? 0} closed',
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCustomersTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1976D2)),
      );
    }

    return ListView(
      children: [
        _buildMetricCard(
          label: 'Total Active Customers',
          value: '${_customerStats['totalCustomers'] ?? 0}',
          subtitle: 'Active customers in system',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Retail vs Wholesale',
          value:
              '${_customerStats['retailCustomers'] ?? 0} : ${_customerStats['wholesaleCustomers'] ?? 0}',
          subtitle: 'Retail to wholesale ratio',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Total Opening Amounts',
          value: _formatCurrency(_customerStats['totalOpeningAmount'] ?? 0),
          subtitle: 'Sum of all customer opening amounts',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Average Opening Amount',
          value: _formatCurrency(_customerStats['avgOpeningAmount'] ?? 0),
          subtitle: 'Per customer average',
        ),
        if (_topCustomers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Top Customers by Opening Amount',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ..._topCustomers.asMap().entries.map((entry) {
            final customer = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: customer['type'] == 'Retail'
                          ? const Color(0xFF1976D2).withOpacity(0.1)
                          : const Color(0xFF388E3C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(
                        customer['type'] == 'Retail'
                            ? Icons.person
                            : Icons.business,
                        color: customer['type'] == 'Retail'
                            ? const Color(0xFF1976D2)
                            : const Color(0xFF388E3C),
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer['name'],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          customer['type'],
                          style: TextStyle(
                            fontSize: 12,
                            color: customer['type'] == 'Retail'
                                ? const Color(0xFF1976D2)
                                : const Color(0xFF388E3C),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatCurrency(customer['openingAmount']),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTransactionsTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1976D2)),
      );
    }

    return ListView(
      children: [
        _buildMetricCard(
          label: 'This Month Credits',
          value: _formatCurrency(_transactionStats['monthCredit'] ?? 0),
          subtitle:
              '${_transactionStats['monthTransactions'] ?? 0} transactions',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'This Month Debits',
          value: _formatCurrency(_transactionStats['monthDebit'] ?? 0),
          subtitle: 'Monthly outflows',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Monthly Net Flow',
          value: (_transactionStats['monthNetFlow'] ?? 0) >= 0
              ? '+${_formatCurrency(_transactionStats['monthNetFlow'] ?? 0)}'
              : '-${_formatCurrency((_transactionStats['monthNetFlow'] ?? 0).abs())}',
          subtitle: 'This month performance',
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Recent Transactions',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_recentTransactions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No transactions found',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ),
          )
        else
          ..._recentTransactions.asMap().entries.map((entry) {
            final transaction = entry.value;
            final isCredit = transaction['isCredit'] as bool;
            final amount = transaction['amount'] as num;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isCredit
                          ? const Color(0xFF388E3C).withOpacity(0.1)
                          : const Color(0xFFD32F2F).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(
                        isCredit ? Icons.add : Icons.remove,
                        color: isCredit
                            ? const Color(0xFF388E3C)
                            : const Color(0xFFD32F2F),
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          transaction['ledgerName'] ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          transaction['transactionType'] ?? 'General',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${isCredit ? '+' : '-'}${_formatCurrency(amount.toDouble())}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isCredit
                          ? const Color(0xFF388E3C)
                          : const Color(0xFFD32F2F),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPerformanceTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1976D2)),
      );
    }

    return ListView(
      children: [
        _buildMetricCard(
          label: 'Average Daily Balance',
          value: _formatCurrency(_ledgerStats['avgDailyBalance'] ?? 0),
          subtitle: 'Per day average closing balance',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'This Month Activity',
          value: '${_ledgerStats['thisMonthDays'] ?? 0} Days',
          subtitle: _formatCurrency(_ledgerStats['thisMonthBalance'] ?? 0),
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Transaction Types',
          value:
              '${(_transactionStats['transactionTypes'] as Map<String, int>?)?.length ?? 0}',
          subtitle: 'Different transaction categories',
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Recent Daily Balances',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_dailyBalances.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No balance data available',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ),
          )
        else
          ..._dailyBalances.asMap().entries.map((entry) {
            final balance = entry.value;
            final opening = balance['opening'] as num;
            final closing = balance['closing'] as num;
            final difference = closing - opening;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: balance['status'] == 'Closed'
                          ? const Color(0xFF388E3C).withOpacity(0.1)
                          : const Color(0xFFF57C00).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(
                        balance['status'] == 'Closed'
                            ? Icons.check_circle
                            : Icons.schedule,
                        color: balance['status'] == 'Closed'
                            ? const Color(0xFF388E3C)
                            : const Color(0xFFF57C00),
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          balance['date'],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Open: ${_formatCurrency(opening.toDouble())} • Close: ${_formatCurrency(closing.toDouble())}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    difference >= 0
                        ? '+${_formatCurrency(difference.toDouble())}'
                        : '-${_formatCurrency(difference.abs().toDouble())}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: difference >= 0
                          ? const Color(0xFF388E3C)
                          : const Color(0xFFD32F2F),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analytics Dashboard',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalyticsData,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: const Color(0xFF1976D2),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Tab(text: 'OVERVIEW'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Tab(text: 'CUSTOMERS'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Tab(text: 'TRANSACTIONS'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Tab(text: 'PERFORMANCE'),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildCustomersTab(),
          _buildTransactionsTab(),
          _buildPerformanceTab(),
        ],
      ),
    );
  }
}
