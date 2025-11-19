import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'dart:typed_data';

class PDFExportService {
  static late pw.Font tamilFont;
  static late pw.Font tamilBoldFont;

  /// Initialize Tamil fonts - call this once during app startup
  static Future<void> initializeTamilFonts(
    Uint8List tamilFontData,
    Uint8List tamilBoldFontData,
  ) async {
    tamilFont = pw.Font.ttf(ByteData.view(tamilFontData.buffer));
    tamilBoldFont = pw.Font.ttf(ByteData.view(tamilBoldFontData.buffer));
  }

  static pw.Document generateLedgerPDF({
    required DateTime date,
    required String shopName,
    required double openingBalance,
    required double closingBalance,
    required double saleValue,
    required List<Map<String, dynamic>> transactions,
    required bool isLedgerClosed,
  }) {
    final pdf = pw.Document();
    final ledgerDate = DateFormat('dd-MMM-yyyy').format(date);

    // ✅ If ledger is NOT closed, set closing balance and sales value to 0
    final double finalClosingBalance = isLedgerClosed ? closingBalance : 0.0;
    final double finalSaleValue = isLedgerClosed ? saleValue : 0.0;

    // ✅ Create transaction list with opening balance as first row
    final List<Map<String, dynamic>> allTransactions = [
      // Opening balance row (first entry)
      {
        'date': DateFormat('dd-MM-yyyy').format(date),
        'time': '', // ✅ Add empty time for opening balance
        'particulars': 'Opening Balance',
        'type': '',
        'debit': openingBalance,
        'credit': 0.0,
      },
      // ✅ Add all actual transactions with CORRECT TRANSACTION DATE in chronological order
      ...transactions.map((t) {
        final amount = (t['amount'] ?? 0).toDouble();
        final isCredit = t['isCredit'] == true;
        final time = _getTransactionTime(t); // ✅ Get transaction time

        return {
          'date': _getCorrectTransactionDate(t, ledgerDate),
          'time': time, // ✅ Add time field
          'particulars': _getParticulars(t),
          'type': _getTransactionTypeDisplay(t),
          'debit': !isCredit ? amount : 0.0,
          'credit': isCredit ? amount : 0.0,
        };
      }).toList(),
    ];

    // ✅ Calculate totals (including opening balance)
    double totalDebit = allTransactions.fold(
      0.0,
      (sum, t) => sum + (t['debit'] as double),
    );
    double totalCredit = allTransactions.fold(
      0.0,
      (sum, t) => sum + (t['credit'] as double),
    );

    // ✅ CONDITIONAL: Add SALES VALUE ROW only if finalSaleValue > 0
    if (finalSaleValue > 0) {
      allTransactions.add({
        'date': '',
        'time': '', // ✅ Add empty time
        'particulars': 'SALES VALUE',
        'type': '',
        'debit': finalSaleValue,
        'credit': 0.0,
      });

      // ✅ Add SALES VALUE to totals
      totalDebit += finalSaleValue;
    }

    // ✅ Add CLOSING BALANCE row (in CREDIT column) - BEFORE GRAND TOTAL
    // Show 0 if ledger not closed, else show actual closing balance
    allTransactions.add({
      'date': '',
      'time': '', // ✅ Add empty time
      'particulars': 'CLOSING BALANCE',
      'type': '',
      'debit': 0.0,
      'credit': finalClosingBalance,
    });

    // ✅ ADD CLOSING BALANCE TO TOTAL CREDIT FOR GRAND TOTAL CALCULATION
    double grandTotalCredit = totalCredit + finalClosingBalance;

    // ✅ Add GRAND TOTAL row (AFTER CLOSING BALANCE)
    // Grand Total Debit stays the same
    // Grand Total Credit NOW INCLUDES Closing Balance
    allTransactions.add({
      'date': '',
      'time': '', // ✅ Add empty time
      'particulars': 'GRAND TOTAL',
      'type': '',
      'debit': totalDebit,
      'credit': grandTotalCredit,
    });

    // ✅ FORMULA: Balance Difference = Credit - Debit (per client request)
    // This uses the Grand Total Credit which includes Closing Balance
    double balanceDifference = grandTotalCredit - totalDebit;

    // ✅ Add BALANCE DIFFERENCE row (AFTER GRAND TOTAL, in DEBIT column)
    allTransactions.add({
      'date': '',
      'time': '', // ✅ Add empty time
      'particulars': 'BALANCE DIFFERENCE',
      'type': '',
      'debit': balanceDifference,
      'credit': 0.0,
    });

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      shopName.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Ledger Report - Date: $ledgerDate | Time: ${DateFormat('HH:mm').format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Transaction Details title
              pw.Text(
                'Transaction Details',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),

              // ✅ Transaction table
              pw.Table(
                border: pw.TableBorder(
                  top: pw.BorderSide(color: PdfColors.black, width: 0.8),
                  bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
                  horizontalInside: pw.BorderSide(
                    color: PdfColors.grey400,
                    width: 0.3,
                  ),
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(
                    1.8,
                  ), // ✅ Increased from 1.2 to fit AM/PM
                  1: const pw.FlexColumnWidth(2.5),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                  4: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    children: [
                      _buildPDFCell(
                        'Date',
                        bold: true,
                        align: pw.TextAlign.center,
                      ),
                      _buildPDFCell(
                        'Particulars',
                        bold: true,
                        align: pw.TextAlign.center,
                      ),
                      _buildPDFCell(
                        'Type',
                        bold: true,
                        align: pw.TextAlign.center,
                      ),
                      _buildPDFCell(
                        'Credit (Rs)',
                        bold: true,
                        align: pw.TextAlign.center,
                      ),
                      _buildPDFCell(
                        'Debit (Rs)',
                        bold: true,
                        align: pw.TextAlign.center,
                      ),
                    ],
                  ),

                  // Transaction rows
                  ...allTransactions.map((tx) {
                    final debitAmount = tx['debit'] as double;
                    final creditAmount = tx['credit'] as double;
                    final isGrandTotal = tx['particulars'] == 'GRAND TOTAL';
                    final isSalesValue = tx['particulars'] == 'SALES VALUE';
                    final isOpeningBalance =
                        tx['particulars'] == 'Opening Balance';
                    final isBalanceDifference =
                        tx['particulars'] == 'BALANCE DIFFERENCE';
                    final isClosingBalance =
                        tx['particulars'] == 'CLOSING BALANCE';
                    final particulars = tx['particulars'] as String;
                    final txDate = tx['date'] as String;
                    final time = tx['time'] as String; // ✅ Get time

                    return pw.TableRow(
                      decoration:
                          (isGrandTotal ||
                              isSalesValue ||
                              isOpeningBalance ||
                              isBalanceDifference ||
                              isClosingBalance)
                          ? const pw.BoxDecoration(color: PdfColors.grey100)
                          : null,
                      children: [
                        // ✅ DATE COLUMN WITH TIME ON SAME LINE (with AM/PM)
                        pw.Container(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            time.isNotEmpty ? '${txDate} | $time' : txDate,
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight:
                                  (isGrandTotal ||
                                      isSalesValue ||
                                      isBalanceDifference ||
                                      isClosingBalance)
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight.normal,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        _buildPDFCellWithTamil(
                          particulars,
                          align: pw.TextAlign.left,
                          maxLines: 2,
                          bold:
                              isGrandTotal ||
                              isSalesValue ||
                              isOpeningBalance ||
                              isBalanceDifference ||
                              isClosingBalance,
                        ),
                        _buildPDFCell(
                          tx['type'],
                          align: pw.TextAlign.center,
                          bold:
                              isGrandTotal ||
                              isSalesValue ||
                              isBalanceDifference ||
                              isClosingBalance,
                        ),
                        // ✅ CREDIT COLUMN
                        isClosingBalance
                            ? pw.Container(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(
                                  creditAmount != 0
                                      ? 'Rs ${NumberFormat('#,##,##0.00').format(creditAmount)}'
                                      : 'Rs 0.00',
                                  style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              )
                            : _buildPDFCell(
                                creditAmount > 0
                                    ? 'Rs ${NumberFormat('#,##,##0.00').format(creditAmount)}'
                                    : '',
                                align: pw.TextAlign.center,
                                bold: isGrandTotal || isSalesValue,
                              ),
                        // ✅ DEBIT COLUMN - Balance Difference with color coding
                        isBalanceDifference
                            ? pw.Container(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(
                                  debitAmount != 0
                                      ? 'Rs ${debitAmount < 0 ? '-' : ''}${NumberFormat('#,##,##0.00').format(debitAmount.abs())}'
                                      : 'Rs 0.00',
                                  style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                    color: debitAmount > 0
                                        ? PdfColors
                                              .green // ✅ GREEN if positive
                                        : debitAmount < 0
                                        ? PdfColors
                                              .red // ✅ RED if negative
                                        : PdfColors.black, // ✅ BLACK if zero
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              )
                            : _buildPDFCell(
                                debitAmount > 0
                                    ? 'Rs ${NumberFormat('#,##,##0.00').format(debitAmount)}'
                                    : '',
                                align: pw.TextAlign.center,
                                bold:
                                    isGrandTotal ||
                                    isSalesValue ||
                                    isClosingBalance ||
                                    isOpeningBalance,
                              ),
                      ],
                    );
                  }).toList(),
                ],
              ),

              pw.Spacer(),

              // ✅ Footer
              pw.Container(
                alignment: pw.Alignment.center,
                margin: const pw.EdgeInsets.only(top: 15),
                child: pw.Column(
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 8),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: PdfColors.grey300),
                          bottom: pw.BorderSide(color: PdfColors.grey300),
                        ),
                      ),
                      child: pw.Text(
                        '"Financial stability is the foundation of success. Track every rupee, plan every expense, grow exponentially."',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                          fontStyle: pw.FontStyle.italic,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'Powered by Ledger System',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // Helper functions

  /// ✅ Get transaction time professionally formatted (with AM/PM)
  static String _getTransactionTime(Map<String, dynamic> transaction) {
    try {
      if (transaction.containsKey('createdAt') &&
          transaction['createdAt'] != null) {
        final createdAt = transaction['createdAt'].toDate();
        return DateFormat('h:mm a').format(createdAt); // Example: 2:30 PM
      }
    } catch (e) {
      // Handle error silently
    }
    return ''; // Return empty string if time not available
  }

  /// ✅ Build PDF cell with Tamil font support
  static pw.Widget _buildPDFCellWithTamil(
    String text, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
    int maxLines = 1,
  }) {
    final isTamil = _containsTamilCharacters(text);
    final font = isTamil ? (bold ? tamilBoldFont : tamilFont) : null;

    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          font: font,
        ),
        textAlign: align,
        maxLines: maxLines,
      ),
    );
  }

  /// ✅ Check if text contains Tamil Unicode characters
  static bool _containsTamilCharacters(String text) {
    final tamilRegex = RegExp(r'[\u0B80-\u0BFF]');
    return tamilRegex.hasMatch(text);
  }

  static pw.Widget _buildPDFCell(
    String text, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
    int maxLines = 1,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: align,
        maxLines: maxLines,
      ),
    );
  }

  static String _getCorrectTransactionDate(
    Map<String, dynamic> transaction,
    String fallbackLedgerDate,
  ) {
    String? transactionDateStr;

    if (transaction.containsKey('transactionDate')) {
      transactionDateStr = transaction['transactionDate']?.toString();
    } else if (transaction.containsKey('date')) {
      transactionDateStr = transaction['date']?.toString();
    } else if (transaction.containsKey('createdAt') &&
        transaction['createdAt'] != null) {
      try {
        final createdAt = transaction['createdAt'].toDate();
        return DateFormat('dd-MM-yyyy').format(createdAt);
      } catch (e) {}
    }

    if (transactionDateStr != null && transactionDateStr.isNotEmpty) {
      try {
        final date = DateFormat('dd-MMM-yyyy').parse(transactionDateStr);
        return DateFormat('dd-MM-yyyy').format(date);
      } catch (e) {
        try {
          final date = DateFormat('dd-MM-yyyy').parse(transactionDateStr);
          return DateFormat('dd-MM-yyyy').format(date);
        } catch (e) {}
      }
    }

    try {
      final date = DateFormat('dd-MMM-yyyy').parse(fallbackLedgerDate);
      return DateFormat('dd-MM-yyyy').format(date);
    } catch (e) {
      return fallbackLedgerDate;
    }
  }

  static String _getParticulars(Map<String, dynamic> transaction) {
    final customerName = transaction['customerName']?.toString() ?? '';
    final ledgerName = transaction['ledgerName']?.toString() ?? '';

    if (customerName.isNotEmpty) return customerName;
    if (ledgerName.isNotEmpty) return ledgerName;
    return 'Transaction';
  }

  static String _getTransactionTypeDisplay(Map<String, dynamic> transaction) {
    final isCredit = transaction['isCredit'] == true;
    return isCredit ? 'Payment In' : 'Payment Out';
  }
}
