import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class StockAnalyticsPage extends StatefulWidget {
  final String shopCollection;
  final String shopName;

  const StockAnalyticsPage({
    super.key,
    required this.shopCollection,
    required this.shopName,
  });

  @override
  State<StockAnalyticsPage> createState() => _StockAnalyticsPageState();
}

class _StockAnalyticsPageState extends State<StockAnalyticsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // Raw data
  List<_ItemMeta> _items = [];
  // itemId -> dateStr -> entry map
  Map<String, Map<String, Map<String, dynamic>>> _history = {};

  static const _kPrimary = Color(0xFF455A64);
  static const int _lookback = 30;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch all items
      final itemSnap = await FirebaseFirestore.instance
          .collection(widget.shopCollection)
          .doc('items')
          .collection('list')
          .get();

      // Dedupe by stock key: two item docs can share the same 'itemId' (e.g.
      // a typo'd duplicate entry). They'd point at the same stock-ledger
      // history, so keeping both would double-count sales/qty and also
      // crash the Trend tab's dropdown (two entries with an equal value).
      final byKey = <String, _ItemMeta>{};
      for (final d in itemSnap.docs) {
        final data = d.data();
        final name = (data['itemName'] ?? '') as String;
        if (name.isEmpty) continue;
        // Stock ledger entries are keyed by the item's 'itemId' field
        // (set by the user, e.g. "DLX.OLD"), not this Firestore doc ID —
        // mirrors StockTab's _itemStockKey. Falls back to doc.id only
        // when itemId wasn't set.
        final key = (data['itemId'] ?? '').toString().trim();
        final id = key.isNotEmpty ? key : d.id;
        byKey.putIfAbsent(
            id,
            () => _ItemMeta(
                  id: id,
                  name: name,
                  price: (data['price'] ?? 0).toDouble(),
                  isActive: data['isActive'] ?? true,
                ));
      }
      final items = byKey.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      // 2. Build last-30-days date strings
      final today = DateTime.now();
      final dates = List.generate(_lookback, (i) {
        final d = today.subtract(Duration(days: i));
        return (date: d, str: DateFormat('dd-MMM-yyyy').format(d));
      });

      // 3. One query per DAY (all items for that day) instead of one document
      //    read per item per day — e.g. 30 requests instead of 20 × 30 = 600.
      final Map<String, Map<String, Map<String, dynamic>>> history = {
        for (final item in items) item.id: <String, Map<String, dynamic>>{},
      };

      final daySnaps = await Future.wait(dates.map((d) => FirebaseFirestore
          .instance
          .collection(widget.shopCollection)
          .doc('stockLedger')
          .collection('dates')
          .doc(d.str)
          .collection('items')
          .get()
          .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s)
          .catchError((_) => null)));

      for (int i = 0; i < dates.length; i++) {
        final snap = daySnaps[i];
        if (snap == null) continue;
        for (final doc in snap.docs) {
          // Entries are keyed by the item's stock key (doc id); ignore any
          // entry whose item no longer exists, as before.
          history[doc.id]?[dates[i].str] = doc.data();
        }
      }

      if (mounted) {
        setState(() {
          _items = items;
          _history = history;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Analytics load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Derived helpers ───────────────────────────────────────────────────────

  /// Total sales value for an item in the last N days
  double _salesForItem(String itemId, {int days = 30}) {
    final entries = _history[itemId] ?? {};
    final cutoff = DateTime.now().subtract(Duration(days: days));
    double total = 0;
    entries.forEach((dateStr, data) {
      try {
        final date = DateFormat('dd-MMM-yyyy').parse(dateStr);
        if (!date.isBefore(cutoff)) {
          total += (data['salesValue'] ?? 0).toDouble();
        }
      } catch (_) {}
    });
    return total;
  }

  double _outForItem(String itemId, {int days = 30}) {
    final entries = _history[itemId] ?? {};
    final cutoff = DateTime.now().subtract(Duration(days: days));
    double total = 0;
    entries.forEach((dateStr, data) {
      try {
        final date = DateFormat('dd-MMM-yyyy').parse(dateStr);
        if (!date.isBefore(cutoff)) {
          total += (data['totalOut'] ?? 0).toDouble();
        }
      } catch (_) {}
    });
    return total;
  }

  /// Current closing stock for an item (latest entry)
  double _currentStock(String itemId) {
    final entries = _history[itemId] ?? {};
    if (entries.isEmpty) return 0;
    // Find latest date
    String? latestStr;
    DateTime? latestDate;
    for (final key in entries.keys) {
      try {
        final d = DateFormat('dd-MMM-yyyy').parse(key);
        if (latestDate == null || d.isAfter(latestDate)) {
          latestDate = d;
          latestStr = key;
        }
      } catch (_) {}
    }
    if (latestStr == null) return 0;
    return (entries[latestStr]!['closingStock'] ?? 0).toDouble();
  }

  /// Daily OUT qty for chart — returns list ordered oldest→newest (30 days)
  List<double> _dailyOut(String itemId) {
    final today = DateTime.now();
    return List.generate(_lookback, (i) {
      final d = today.subtract(Duration(days: _lookback - 1 - i));
      final key = DateFormat('dd-MMM-yyyy').format(d);
      final data = (_history[itemId] ?? {})[key];
      return (data?['totalOut'] ?? 0).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Analytics & Reports',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: Color(0xFF1A1A2E))),
            Text(widget.shopName,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _kPrimary,
          indicatorWeight: 2.5,
          labelColor: _kPrimary,
          unselectedLabelColor: Colors.grey[400],
          dividerColor: const Color(0xFFE8EAED),
          labelStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'SUMMARY'),
            Tab(text: 'BEST SELLERS'),
            Tab(text: 'TREND'),
            Tab(text: 'LOW STOCK'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: _kPrimary, strokeWidth: 2))
          : _items.isEmpty
              ? _emptyState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _SummaryTab(
                        items: _items,
                        salesFn: _salesForItem,
                        outFn: _outForItem),
                    _BestSellersTab(
                        items: _items,
                        salesFn: _salesForItem,
                        outFn: _outForItem),
                    _TrendTab(
                        items: _items,
                        dailyOutFn: _dailyOut,
                        lookback: _lookback),
                    _LowStockTab(
                        items: _items,
                        currentStockFn: _currentStock),
                  ],
                ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_outlined, size: 52, color: Colors.grey[300]),
          const SizedBox(height: 14),
          Text('No data available',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500])),
          const SizedBox(height: 6),
          Text('Add items and record stock entries first',
              style: TextStyle(fontSize: 13, color: Colors.grey[400])),
        ],
      ),
    );
  }
}

// ─── Item metadata ────────────────────────────────────────────────────────────

class _ItemMeta {
  final String id;
  final String name;
  final double price;
  final bool isActive;
  const _ItemMeta(
      {required this.id,
      required this.name,
      required this.price,
      required this.isActive});
}

// ─── TAB 1: Sales Summary ─────────────────────────────────────────────────────

class _SummaryTab extends StatefulWidget {
  final List<_ItemMeta> items;
  final double Function(String, {int days}) salesFn;
  final double Function(String, {int days}) outFn;

  const _SummaryTab(
      {required this.items,
      required this.salesFn,
      required this.outFn});

  @override
  State<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<_SummaryTab> {
  int _period = 30; // 1, 7, 30

  @override
  Widget build(BuildContext context) {
    final fmtMoney = NumberFormat('#,##,##0.00');
    final fmt = NumberFormat('#,##0.##');

    double grandSales = 0;
    double grandOut = 0;
    for (final item in widget.items) {
      grandSales += widget.salesFn(item.id, days: _period);
      grandOut += widget.outFn(item.id, days: _period);
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
      children: [
        // ── Period selector ──
        _PeriodSelector(
          selected: _period,
          onChanged: (v) => setState(() => _period = v),
        ),
        const SizedBox(height: 16),

        // ── Grand totals ──
        Row(
          children: [
            Expanded(
              child: _SummaryKpi(
                label: 'Total Sales',
                value: '₹${fmtMoney.format(grandSales)}',
                icon: Icons.currency_rupee_rounded,
                color: const Color(0xFF455A64),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryKpi(
                label: 'Total Qty Sold',
                value: '${fmt.format(grandOut)} kg',
                icon: Icons.scale_outlined,
                color: Colors.green[700]!,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Per-item breakdown ──
        _sectionHeader('Per Item Breakdown'),
        const SizedBox(height: 10),
        ...widget.items.map((item) {
          final sales = widget.salesFn(item.id, days: _period);
          final out = widget.outFn(item.id, days: _period);
          if (sales == 0 && out == 0) return const SizedBox.shrink();
          return _ItemSummaryRow(
            name: item.name,
            sales: sales,
            out: out,
            grandSales: grandSales,
          );
        }),
      ],
    );
  }
}

// ─── TAB 2: Best Sellers ──────────────────────────────────────────────────────

class _BestSellersTab extends StatefulWidget {
  final List<_ItemMeta> items;
  final double Function(String, {int days}) salesFn;
  final double Function(String, {int days}) outFn;

  const _BestSellersTab(
      {required this.items,
      required this.salesFn,
      required this.outFn});

  @override
  State<_BestSellersTab> createState() => _BestSellersTabState();
}

class _BestSellersTabState extends State<_BestSellersTab> {
  int _period = 30;

  @override
  Widget build(BuildContext context) {
    final fmtMoney = NumberFormat('#,##,##0.00');
    final fmt = NumberFormat('#,##0.##');

    final ranked = widget.items.map((item) {
      return (
        item: item,
        sales: widget.salesFn(item.id, days: _period),
        out: widget.outFn(item.id, days: _period),
      );
    }).toList()
      ..sort((a, b) => b.sales.compareTo(a.sales));

    final maxSales =
        ranked.isNotEmpty ? ranked.first.sales : 1.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
      children: [
        _PeriodSelector(
          selected: _period,
          onChanged: (v) => setState(() => _period = v),
        ),
        const SizedBox(height: 16),
        _sectionHeader('Ranked by Sales Value'),
        const SizedBox(height: 10),
        ...ranked.asMap().entries.map((e) {
          final rank = e.key + 1;
          final r = e.value;
          if (r.sales == 0) return const SizedBox.shrink();
          final barFraction =
              maxSales > 0 ? (r.sales / maxSales) : 0.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rank badge
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rank == 1
                        ? const Color(0xFFFFC107)
                        : rank == 2
                            ? const Color(0xFFB0BEC5)
                            : rank == 3
                                ? const Color(0xFFBCAAA4)
                                : Colors.grey[100]!,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: rank <= 3
                          ? Colors.white
                          : Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.item.name,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87)),
                      const SizedBox(height: 6),
                      // Progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: barFraction,
                          minHeight: 6,
                          backgroundColor: Colors.grey[100],
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF455A64)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('₹${fmtMoney.format(r.sales)}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF455A64))),
                          const Spacer(),
                          Text('${fmt.format(r.out)} kg sold',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500])),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─── TAB 3: Trend Chart ───────────────────────────────────────────────────────

class _TrendTab extends StatefulWidget {
  final List<_ItemMeta> items;
  final List<double> Function(String) dailyOutFn;
  final int lookback;

  const _TrendTab(
      {required this.items,
      required this.dailyOutFn,
      required this.lookback});

  @override
  State<_TrendTab> createState() => _TrendTabState();
}

class _TrendTabState extends State<_TrendTab> {
  late String _selectedItemId;

  @override
  void initState() {
    super.initState();
    _selectedItemId = widget.items.first.id;
  }

  @override
  void didUpdateWidget(_TrendTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Guard against a refresh changing the item list (rename/delete) and
    // leaving _selectedItemId pointing at something no longer in it — the
    // dropdown requires its value to match exactly one item.
    if (!widget.items.any((i) => i.id == _selectedItemId)) {
      _selectedItemId = widget.items.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dailyOut = widget.dailyOutFn(_selectedItemId);
    final maxY = dailyOut.isEmpty
        ? 10.0
        : (dailyOut.reduce((a, b) => a > b ? a : b) * 1.3)
            .clamp(1.0, double.infinity);

    final spots = dailyOut.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value);
    }).toList();

    final totalOut = dailyOut.fold(0.0, (s, v) => s + v);
    final avgOut = dailyOut.where((v) => v > 0).isEmpty
        ? 0.0
        : totalOut /
            dailyOut.where((v) => v > 0).length;
    final fmt = NumberFormat('#,##0.##');

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
      children: [
        // ── Item selector ──
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedItemId,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey[500], size: 20),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
              onChanged: (val) {
                if (val != null) setState(() => _selectedItemId = val);
              },
              items: widget.items
                  .map((i) => DropdownMenuItem<String>(
                        value: i.id,
                        child: Text(i.name,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── KPI strip ──
        Row(
          children: [
            Expanded(
              child: _SummaryKpi(
                label: '30-Day Total',
                value: '${fmt.format(totalOut)} kg',
                icon: Icons.trending_up_rounded,
                color: const Color(0xFF455A64),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryKpi(
                label: 'Avg / Active Day',
                value: '${fmt.format(avgOut)} kg',
                icon: Icons.analytics_outlined,
                color: Colors.green[700]!,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Chart ──
        Container(
          padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 16),
                child: Text('Daily Stock OUT — Last 30 Days',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600])),
              ),
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: maxY,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: maxY / 4,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: Colors.grey[200]!,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          interval: maxY / 4,
                          getTitlesWidget: (val, _) => Text(
                            fmt.format(val),
                            style: TextStyle(
                                fontSize: 9, color: Colors.grey[400]),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 7,
                          getTitlesWidget: (val, _) {
                            final idx = val.toInt();
                            if (idx < 0 ||
                                idx >= widget.lookback) {
                              return const SizedBox.shrink();
                            }
                            final d = today.subtract(Duration(
                                days: widget.lookback - 1 - idx));
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                DateFormat('d/M').format(d),
                                style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey[400]),
                              ),
                            );
                          },
                        ),
                      ),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.3,
                        color: const Color(0xFF455A64),
                        barWidth: 2,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, _, __, ___) {
                            if (spot.y == 0) {
                              return FlDotCirclePainter(
                                  radius: 0,
                                  color: Colors.transparent,
                                  strokeColor: Colors.transparent);
                            }
                            return FlDotCirclePainter(
                              radius: 3,
                              color: Colors.white,
                              strokeWidth: 2,
                              strokeColor: const Color(0xFF455A64),
                            );
                          },
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: const Color(0xFF455A64)
                              .withValues(alpha: 0.07),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => Colors.black87,
                        getTooltipItems: (spots) => spots
                            .map((s) => LineTooltipItem(
                                  '${fmt.format(s.y)} kg',
                                  const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── TAB 4: Low Stock Alert ───────────────────────────────────────────────────

class _LowStockTab extends StatefulWidget {
  final List<_ItemMeta> items;
  final double Function(String) currentStockFn;

  const _LowStockTab(
      {required this.items, required this.currentStockFn});

  @override
  State<_LowStockTab> createState() => _LowStockTabState();
}

class _LowStockTabState extends State<_LowStockTab> {
  double _threshold = 30;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');

    final stockList = widget.items.map((item) {
      return (item: item, stock: widget.currentStockFn(item.id));
    }).toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));

    final outOfStock =
        stockList.where((r) => r.stock <= 0).toList();
    final lowStock = stockList
        .where((r) => r.stock > 0 && r.stock < _threshold)
        .toList();
    final healthy =
        stockList.where((r) => r.stock >= _threshold).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
      children: [
        // ── Threshold slider ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Low stock threshold',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
                  const Spacer(),
                  Text('${fmt.format(_threshold)} kg',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF455A64))),
                ],
              ),
              Slider(
                value: _threshold,
                min: 5,
                max: 200,
                divisions: 39,
                activeColor: const Color(0xFF455A64),
                inactiveColor: Colors.grey[200],
                onChanged: (v) =>
                    setState(() => _threshold = v.roundToDouble()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Summary chips ──
        Row(
          children: [
            Expanded(
              child: _AlertKpi(
                  label: 'Out of Stock',
                  count: outOfStock.length,
                  color: Colors.red[600]!),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AlertKpi(
                  label: 'Low Stock',
                  count: lowStock.length,
                  color: Colors.orange[700]!),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AlertKpi(
                  label: 'Healthy',
                  count: healthy.length,
                  color: Colors.green[700]!),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Out of stock ──
        if (outOfStock.isNotEmpty) ...[
          _sectionHeader('Out of Stock', color: Colors.red[700]!),
          const SizedBox(height: 8),
          ...outOfStock.map((r) => _StockAlertRow(
                name: r.item.name,
                stock: r.stock,
                status: _StockStatus.outOfStock,
              )),
          const SizedBox(height: 16),
        ],

        // ── Low stock ──
        if (lowStock.isNotEmpty) ...[
          _sectionHeader('Low Stock', color: Colors.orange[700]!),
          const SizedBox(height: 8),
          ...lowStock.map((r) => _StockAlertRow(
                name: r.item.name,
                stock: r.stock,
                status: _StockStatus.low,
              )),
          const SizedBox(height: 16),
        ],

        // ── Healthy ──
        if (healthy.isNotEmpty) ...[
          _sectionHeader('Healthy Stock', color: Colors.green[700]!),
          const SizedBox(height: 8),
          ...healthy.map((r) => _StockAlertRow(
                name: r.item.name,
                stock: r.stock,
                status: _StockStatus.healthy,
              )),
        ],
      ],
    );
  }
}

// ─── Shared small widgets ─────────────────────────────────────────────────────

enum _StockStatus { outOfStock, low, healthy }

Widget _sectionHeader(String title, {Color? color}) => Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color ?? Colors.grey[500],
        letterSpacing: 0.6,
      ),
    );

class _PeriodSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _PeriodSelector(
      {required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip('Today', 1),
        const SizedBox(width: 8),
        _chip('7 Days', 7),
        const SizedBox(width: 8),
        _chip('30 Days', 30),
      ],
    );
  }

  Widget _chip(String label, int days) {
    final isSelected = selected == days;
    return GestureDetector(
      onTap: () => onChanged(days),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color:
              isSelected ? const Color(0xFF455A64) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }
}

class _SummaryKpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryKpi(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }
}

class _ItemSummaryRow extends StatelessWidget {
  final String name;
  final double sales;
  final double out;
  final double grandSales;

  const _ItemSummaryRow(
      {required this.name,
      required this.sales,
      required this.out,
      required this.grandSales});

  @override
  Widget build(BuildContext context) {
    final fmtMoney = NumberFormat('#,##,##0.00');
    final fmt = NumberFormat('#,##0.##');
    final share = grandSales > 0 ? (sales / grandSales) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87)),
              ),
              Text('₹${fmtMoney.format(sales)}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF455A64))),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 5,
              backgroundColor: Colors.grey[100],
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF455A64)),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('${(share * 100).toStringAsFixed(1)}% of total',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey[400])),
              const Spacer(),
              Text('${fmt.format(out)} kg',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertKpi extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _AlertKpi(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }
}

class _StockAlertRow extends StatelessWidget {
  final String name;
  final double stock;
  final _StockStatus status;

  const _StockAlertRow(
      {required this.name, required this.stock, required this.status});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final Color dotColor;
    final String stockLabel;

    switch (status) {
      case _StockStatus.outOfStock:
        dotColor = Colors.red[600]!;
        stockLabel = 'Out of stock';
        break;
      case _StockStatus.low:
        dotColor = Colors.orange[700]!;
        stockLabel = '${fmt.format(stock)} kg';
        break;
      case _StockStatus.healthy:
        dotColor = Colors.green[600]!;
        stockLabel = '${fmt.format(stock)} kg';
        break;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
              ),
              Text(stockLabel,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: dotColor)),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.grey[100]),
      ],
    );
  }
}
