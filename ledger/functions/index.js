const functions = require('firebase-functions');
const admin = require('firebase-admin');
const PDFDocument = require('pdfkit');
const moment = require('moment');
const fs = require('fs');
const path = require('path');

admin.initializeApp();

// Tamil Unicode block: U+0B80–U+0BFF
function containsTamil(text) {
  if (!text || text.length === 0) return false;
  return /[஀-௿]/.test(text);
}

function formatCurrency(amount) {
  const absAmount = Math.abs(amount);
  const parts = absAmount.toFixed(2).split('.');
  let integer = parts[0];
  if (integer.length > 3) integer = integer.slice(0, -3) + ',' + integer.slice(-3);
  if (integer.length > 5) integer = integer.slice(0, -5) + ',' + integer.slice(-5, -3) + ',' + integer.slice(-3);
  return integer + '.' + parts[1];
}

function getTransactionTime(transaction) {
  try {
    if (transaction.createdAt) {
      let date;
      if (transaction.createdAt.toDate) date = transaction.createdAt.toDate();
      else if (transaction.createdAt._seconds) date = new Date(transaction.createdAt._seconds * 1000);
      else if (transaction.createdAt.seconds) date = new Date(transaction.createdAt.seconds * 1000);
      else date = new Date(transaction.createdAt);
      return moment(date).utcOffset(330).format('h:mm A');
    }
  } catch (e) { /* silent */ }
  return '';
}

function getCorrectTransactionDate(transaction, fallbackLedgerDate) {
  let dateStr = null;
  if (transaction.transactionDate) dateStr = transaction.transactionDate.toString();
  else if (transaction.date) dateStr = transaction.date.toString();
  else if (transaction.createdAt) {
    try {
      let date;
      if (transaction.createdAt.toDate) date = transaction.createdAt.toDate();
      else if (transaction.createdAt._seconds) date = new Date(transaction.createdAt._seconds * 1000);
      else if (transaction.createdAt.seconds) date = new Date(transaction.createdAt.seconds * 1000);
      else date = new Date(transaction.createdAt);
      return moment(date).format('DD-MM-YYYY');
    } catch (e) { /* continue */ }
  }

  if (dateStr) {
    try {
      const d1 = moment(dateStr, 'DD-MMM-YYYY');
      if (d1.isValid()) return d1.format('DD-MM-YYYY');
      const d2 = moment(dateStr, 'DD-MM-YYYY');
      if (d2.isValid()) return d2.format('DD-MM-YYYY');
    } catch (e) { /* continue */ }
  }

  try {
    const d = moment(fallbackLedgerDate, 'DD-MMM-YYYY');
    if (d.isValid()) return d.format('DD-MM-YYYY');
  } catch (e) { /* continue */ }

  return fallbackLedgerDate;
}

function getParticulars(transaction) {
  const customerName = transaction.customerName?.toString() || '';
  const ledgerName = transaction.ledgerName?.toString() || '';
  if (customerName.length > 0) return customerName;
  if (ledgerName.length > 0) return ledgerName;
  return 'Transaction';
}

function getTransactionTypeDisplay(transaction) {
  return transaction.isCredit === true ? 'Payment Out' : 'Payment In';
}

function findFontPath(filename) {
  const candidates = [
    path.join(__dirname, 'fonts', filename),
    path.join(__dirname, '..', 'assets', 'icon', 'fonts', filename),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return null;
}

/**
 * Generate PDF using PDFKit directly.
 *
 * pdfmake measures characters individually before rendering, which breaks the
 * GSUB substitution sequence that Tamil vowel marks require.  PDFKit passes
 * the complete string to fontkit's layout engine, which applies the full
 * OpenType GSUB chain so combining vowel marks (ி ீ ு ூ …) attach correctly.
 */
function generatePDFWithPDFKit(shopName, ledgerDate, allTransactions) {
  return new Promise((resolve, reject) => {
    try {
      const MARGIN  = 20;
      const doc = new PDFDocument({
        size: 'A4',
        margins: {top: MARGIN, bottom: MARGIN, left: MARGIN, right: MARGIN},
        autoFirstPage: true,
        info: {Title: `Ledger Report - ${ledgerDate}`},
      });

      // Register Tamil fonts — fontkit reads GSUB tables and applies Tamil
      // shaping (pref / pstf / blwf lookups) so vowel marks render correctly.
      const tamilRegularPath = findFontPath('NotoSansTamil-Regular.ttf');
      const tamilBoldPath    = findFontPath('NotoSansTamil-Bold.ttf');

      if (tamilRegularPath) {
        doc.registerFont('Tamil', tamilRegularPath);
        console.log('✅ Tamil Regular registered:', tamilRegularPath);
      } else {
        doc.registerFont('Tamil', 'Helvetica');
        console.warn('⚠️ NotoSansTamil-Regular.ttf not found, falling back to Helvetica');
      }
      if (tamilBoldPath) {
        doc.registerFont('Tamil-Bold', tamilBoldPath);
        console.log('✅ Tamil Bold registered:', tamilBoldPath);
      } else {
        doc.registerFont('Tamil-Bold', 'Helvetica-Bold');
        console.warn('⚠️ NotoSansTamil-Bold.ttf not found, falling back to Helvetica-Bold');
      }

      // ── Layout constants ────────────────────────────────────────────────
      const PW = doc.page.width;   // 595.28 pt  (A4)
      const PH = doc.page.height;  // 841.89 pt  (A4)
      const CW = PW - MARGIN * 2;  // ~555 pt content width

      // Column widths matching Flutter's FlexColumnWidth ratios: 1.8 2.5 1.5 1.5 1.5
      const RATIOS  = [1.8, 2.5, 1.5, 1.5, 1.5];
      const TOTAL_R = RATIOS.reduce((a, b) => a + b, 0); // 8.8
      const COL_W   = RATIOS.map(r => (r / TOTAL_R) * CW);

      // X start of each column
      const COL_X = [];
      COL_W.forEach((w, i) => COL_X.push(i === 0 ? MARGIN : COL_X[i - 1] + COL_W[i - 1]));

      const ROW_H    = 18;  // row height (pt)
      const PAD_X    = 4;   // horizontal cell padding
      const PAD_Y    = 5;   // vertical: row-top → text-top
      const FOOTER_H = 55;  // space reserved at page bottom for footer

      // Choose PDFKit font name based on text content.
      // NotoSansTamil includes Basic Latin so ASCII chars in Tamil strings render fine.
      const fontFor = (text, bold = false) =>
        containsTamil(text) ? (bold ? 'Tamil-Bold' : 'Tamil')
                             : (bold ? 'Helvetica-Bold' : 'Helvetica');

      // Render text inside a table cell
      const cellText = (text, colIdx, rowY, {align = 'left', bold = false, size = 8, color = 'black'} = {}) => {
        if (!text) return;
        doc.font(fontFor(text, bold)).fontSize(size).fillColor(color);
        doc.text(text, COL_X[colIdx] + PAD_X, rowY + PAD_Y, {
          width: COL_W[colIdx] - PAD_X * 2,
          align,
          lineBreak: false,
        });
        doc.fillColor('black');
      };

      // Draw table header row; returns Y of first data row
      const drawHeader = (y) => {
        doc.rect(MARGIN, y, CW, ROW_H).fill('#E5E5E5');
        doc.fillColor('black').font('Helvetica-Bold').fontSize(9);
        ['Date', 'Particulars', 'Type', 'Credit (Rs)', 'Debit (Rs)'].forEach((h, i) => {
          doc.text(h, COL_X[i] + PAD_X, y + PAD_Y, {
            width: COL_W[i] - PAD_X * 2,
            align: 'center',
            lineBreak: false,
          });
        });
        // Top border
        doc.moveTo(MARGIN, y).lineTo(MARGIN + CW, y).strokeColor('black').lineWidth(0.8).stroke();
        return y + ROW_H;
      };

      // ── Page header ─────────────────────────────────────────────────────
      doc.font(fontFor(shopName, true)).fontSize(16).fillColor('black');
      doc.text(shopName, MARGIN, MARGIN, {width: CW, align: 'center'});
      doc.font('Helvetica').fontSize(12);
      doc.text(`Ledger Report - Date: ${ledgerDate}`, {align: 'center'});
      doc.moveDown(0.8);
      doc.font('Helvetica-Bold').fontSize(11);
      doc.text('Transaction Details');
      doc.moveDown(0.4);

      let y = doc.y;
      y = drawHeader(y);

      // ── Transaction rows ─────────────────────────────────────────────────
      const SPECIAL = new Set([
        'Opening Balance', 'SALES VALUE', 'CASH OUT',
        'CLOSING BALANCE', 'GRAND TOTAL', 'BALANCE DIFFERENCE',
      ]);

      for (const tx of allTransactions) {
        const special    = SPECIAL.has(tx.particulars);
        const isBalDiff  = tx.particulars === 'BALANCE DIFFERENCE';
        const isClosing  = tx.particulars === 'CLOSING BALANCE';
        const isCashOut  = tx.particulars === 'CASH OUT';

        // Paginate when the next row won't fit above the footer zone
        if (y + ROW_H > PH - MARGIN - FOOTER_H) {
          doc.moveTo(MARGIN, y).lineTo(MARGIN + CW, y).strokeColor('black').lineWidth(0.8).stroke();
          doc.addPage();
          y = MARGIN;
          y = drawHeader(y);
        }

        if (special) {
          doc.rect(MARGIN, y, CW, ROW_H).fill('#F5F5F5');
        }

        // Col 0 — Date
        const dateStr = tx.time ? `${tx.date} | ${tx.time}` : (tx.date || '');
        doc.font(special ? 'Helvetica-Bold' : 'Helvetica').fontSize(7).fillColor('black');
        doc.text(dateStr, COL_X[0] + PAD_X, y + PAD_Y, {
          width: COL_W[0] - PAD_X * 2,
          align: 'left',
          lineBreak: false,
        });

        // Col 1 — Particulars (Tamil or English, fontkit shapes it correctly)
        cellText(tx.particulars || '', 1, y, {align: 'left', bold: special, size: 9});

        // Col 2 — Type
        doc.font(special ? 'Helvetica-Bold' : 'Helvetica').fontSize(8).fillColor('black');
        doc.text(tx.type || '', COL_X[2] + PAD_X, y + PAD_Y, {
          width: COL_W[2] - PAD_X * 2,
          align: 'center',
          lineBreak: false,
        });

        // Col 3 — Credit
        const showCredit = tx.credit > 0 || isClosing || isCashOut;
        const creditStr  = showCredit ? `Rs ${formatCurrency(tx.credit)}` : '';
        doc.font(special ? 'Helvetica-Bold' : 'Helvetica').fontSize(8).fillColor('black');
        doc.text(creditStr, COL_X[3] + PAD_X, y + PAD_Y, {
          width: COL_W[3] - PAD_X * 2,
          align: 'center',
          lineBreak: false,
        });

        // Col 4 — Debit
        let debitStr   = '';
        let debitColor = 'black';
        if (isBalDiff) {
          debitStr   = tx.debit !== 0
            ? (tx.debit < 0 ? `Rs -${formatCurrency(Math.abs(tx.debit))}` : `Rs ${formatCurrency(tx.debit)}`)
            : 'Rs 0.00';
          debitColor = tx.debit > 0 ? '#006600' : tx.debit < 0 ? '#CC0000' : 'black';
        } else if (tx.debit > 0) {
          debitStr = `Rs ${formatCurrency(tx.debit)}`;
        }
        doc.font(special ? 'Helvetica-Bold' : 'Helvetica').fontSize(8).fillColor(debitColor);
        doc.text(debitStr, COL_X[4] + PAD_X, y + PAD_Y, {
          width: COL_W[4] - PAD_X * 2,
          align: 'center',
          lineBreak: false,
        });
        doc.fillColor('black');

        // Row separator
        doc.moveTo(MARGIN, y + ROW_H).lineTo(MARGIN + CW, y + ROW_H)
           .strokeColor('#CCCCCC').lineWidth(0.3).stroke();

        y += ROW_H;
      }

      // Table bottom border
      doc.moveTo(MARGIN, y).lineTo(MARGIN + CW, y).strokeColor('black').lineWidth(0.8).stroke();

      // ── Footer (fixed at page bottom) ────────────────────────────────────
      const footerY = PH - MARGIN - 40;
      doc.moveTo(MARGIN, footerY - 8).lineTo(MARGIN + CW, footerY - 8)
         .strokeColor('#CCCCCC').lineWidth(0.5).stroke();
      doc.font('Helvetica-Oblique').fontSize(9).fillColor('#666666');
      doc.text(
        '"Financial stability is the foundation of success. Track every rupee, plan every expense, grow exponentially."',
        MARGIN, footerY, {width: CW, align: 'center'},
      );
      doc.font('Helvetica').fontSize(8);
      doc.text('Powered by Ledger System', {align: 'center'});

      // Collect and resolve
      const chunks = [];
      doc.on('data', chunk => chunks.push(chunk));
      doc.on('end', () => {
        const pdfBase64 = Buffer.concat(chunks).toString('base64');
        resolve({success: true, pdfBase64, message: 'PDF generated successfully'});
      });
      doc.on('error', reject);
      doc.end();

    } catch (err) {
      reject(err);
    }
  });
}

exports.generateLedgerPDF = functions.https.onCall(async (data, context) => {
  try {
    if (context.auth) {
      console.log('PDF generation requested by user:', context.auth.uid);
    } else {
      console.log('PDF generation requested (unauthenticated)');
    }

    const {date, shopName, openingBalance, closingBalance, saleValue, cashOut, transactions, isLedgerClosed} = data;

    if (!date || !shopName || openingBalance === undefined || !transactions) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters');
    }

    const ledgerDate      = moment(date).format('DD-MMM-YYYY');
    const ledgerDateShort = moment(date).format('DD-MM-YYYY');

    const finalClosingBalance = isLedgerClosed ? (closingBalance || 0) : 0.0;
    const finalSaleValue      = isLedgerClosed ? (saleValue      || 0) : 0.0;
    const finalCashOut        = isLedgerClosed ? (cashOut        || 0) : 0.0;

    // Build the sorted transaction list (matches Flutter's _downloadPDF logic)
    const allTransactions = [
      {date: ledgerDateShort, time: '', particulars: 'Opening Balance', type: '', debit: openingBalance, credit: 0.0},
      ...transactions.map(t => {
        const amount   = parseFloat(t.amount || 0);
        const isCredit = t.isCredit === true;
        return {
          date:        getCorrectTransactionDate(t, ledgerDate),
          time:        getTransactionTime(t),
          particulars: getParticulars(t),
          type:        getTransactionTypeDisplay(t),
          debit:       !isCredit ? amount : 0.0,
          credit:      isCredit  ? amount : 0.0,
        };
      }),
    ];

    let totalDebit  = allTransactions.reduce((s, t) => s + (t.debit  || 0), 0);
    let totalCredit = allTransactions.reduce((s, t) => s + (t.credit || 0), 0);

    if (finalSaleValue > 0) {
      allTransactions.push({date: '', time: '', particulars: 'SALES VALUE', type: '', debit: finalSaleValue, credit: 0.0});
      totalDebit += finalSaleValue;
    }
    if (finalCashOut > 0) {
      allTransactions.push({date: '', time: '', particulars: 'CASH OUT', type: '', debit: 0.0, credit: finalCashOut});
      totalCredit += finalCashOut;
    }

    allTransactions.push({date: '', time: '', particulars: 'CLOSING BALANCE', type: '', debit: 0.0, credit: finalClosingBalance});
    const grandTotalCredit = totalCredit + finalClosingBalance;
    allTransactions.push({date: '', time: '', particulars: 'GRAND TOTAL', type: '', debit: totalDebit, credit: grandTotalCredit});
    const balanceDifference = grandTotalCredit - totalDebit;
    allTransactions.push({date: '', time: '', particulars: 'BALANCE DIFFERENCE', type: '', debit: balanceDifference, credit: 0.0});

    return await generatePDFWithPDFKit(shopName, ledgerDate, allTransactions);

  } catch (error) {
    console.error('Error in generateLedgerPDF:', error);
    throw new functions.https.HttpsError('internal', 'Error generating PDF: ' + error.message);
  }
});

const otpFunctions = require('./otp');
exports.sendOTP      = otpFunctions.sendOTP;
exports.verifyOTP    = otpFunctions.verifyOTP;
exports.resendOTP    = otpFunctions.resendOTP;
exports.sendEmailOTP = otpFunctions.sendEmailOTP;
