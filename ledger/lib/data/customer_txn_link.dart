import 'package:cloud_firestore/cloud_firestore.dart';

/// A customer transaction is stored twice: in the day's ledger
/// (`<shop>/ledgers/transactions`) and in the customer's own account
/// (`<shop>/customers/list/<customerId>/transactions`). Edits and deletes made
/// from the ledger must reach the customer's copy too, or the customer's
/// balance goes wrong.
///
/// Returns the customer's copy of [ledgerDoc], or null if the ledger entry is
/// not a customer transaction or no matching copy exists.
///
/// Lookup order:
///  1. `customerTxnId` stored on the ledger entry (new entries).
///  2. A customer entry with the same document id (new entries use one id).
///  3. Older entries without a link: same ledger date, amount and type,
///     choosing the one created closest in time to the ledger entry.
Future<DocumentReference<Map<String, dynamic>>?> findLinkedCustomerTxn({
  required String shopCollection,
  required DocumentSnapshot ledgerDoc,
  Map<String, dynamic>? ledgerData,
}) async {
  final data = ledgerData ?? (ledgerDoc.data() as Map<String, dynamic>? ?? {});
  final customerId = (data['customerId'] ?? '').toString();
  if (data['transactionType'] != 'Customer' || customerId.isEmpty) {
    return null;
  }

  final customerTxns = FirebaseFirestore.instance
      .collection(shopCollection)
      .doc('customers')
      .collection('list')
      .doc(customerId)
      .collection('transactions');

  // 1 + 2: direct link.
  final linkedId = (data['customerTxnId'] ?? ledgerDoc.id).toString();
  final direct = await customerTxns.doc(linkedId).get();
  if (direct.exists) return direct.reference;

  // 3: older entries — match by date, amount and type.
  final ledgerDate = data['ledgerDate'];
  if (ledgerDate == null) return null;
  final amount = (data['amount'] ?? 0).toDouble();
  final isCredit = data['isCredit'] == true;
  final ledgerCreatedAt = data['createdAt'] is Timestamp
      ? (data['createdAt'] as Timestamp).toDate()
      : null;

  final sameDay =
      await customerTxns.where('ledgerDate', isEqualTo: ledgerDate).get();
  DocumentReference<Map<String, dynamic>>? best;
  Duration? bestGap;
  for (final doc in sameDay.docs) {
    final d = doc.data();
    if ((d['amount'] ?? 0).toDouble() != amount) continue;
    if ((d['isCredit'] == true) != isCredit) continue;
    final created =
        d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null;
    final gap = (ledgerCreatedAt != null && created != null)
        ? ledgerCreatedAt.difference(created).abs()
        : const Duration(days: 365);
    if (bestGap == null || gap < bestGap) {
      best = doc.reference;
      bestGap = gap;
    }
  }
  return best;
}

/// Reference to the customer's main document, used to signal that their
/// transactions changed so the Customer list recalculates the balance.
DocumentReference<Map<String, dynamic>>? customerDocFor(
  String shopCollection,
  Map<String, dynamic> ledgerData,
) {
  final customerId = (ledgerData['customerId'] ?? '').toString();
  if (ledgerData['transactionType'] != 'Customer' || customerId.isEmpty) {
    return null;
  }
  return FirebaseFirestore.instance
      .collection(shopCollection)
      .doc('customers')
      .collection('list')
      .doc(customerId);
}
