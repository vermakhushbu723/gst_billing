import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pdf/invoice_pdf.dart';
import '../widgets/common.dart';
import 'api.dart';
import 'companies.dart';
import 'docs.dart';
import 'format.dart';
import 'save_file_io.dart' if (dart.library.js_interop) 'save_file_web.dart' as saver;

/// Print, download and WhatsApp for one invoice.
class InvoiceActions {
  static Future<Uint8List> pdf(Map inv, {String copy = 'ORIGINAL'}) async {
    final company = await Companies.instance.full('${inv['company']}');
    return InvoicePdf.build(inv, company, copy: copy);
  }

  static String message(Map inv, {String? link}) {
    final b = StringBuffer()
      ..writeln('Dear ${inv['billTo']?['name'] ?? 'Customer'},')
      ..writeln()
      ..writeln('Please find the ${DocType.of(inv['docType']).labelFor(isGstDoc(inv))} No. ${invNo(inv)} dated ${dmy(inv['invoiceDate'])} '
          'from ${inv['companySnapshot']?['name'] ?? ''}.')
      ..writeln('Amount: ${rupee(inv['total'])}');
    if (toD(inv['balance']) > 0 && toD(inv['balance']) != toD(inv['total'])) {
      b.writeln('Balance Due: ${rupee(inv['balance'])}');
    }
    if ('${inv['dueDate'] ?? ''}'.isNotEmpty && toD(inv['balance']) > 0) b.writeln('Due Date: ${dmy(inv['dueDate'])}');
    if (link != null) {
      b
        ..writeln()
        ..writeln('Download PDF: $link');
    }
    b
      ..writeln()
      ..write('Thank you.');
    return b.toString();
  }

  static Future<void> printPdf(Map inv, Uint8List bytes) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: invoiceFileName(inv));

  static Future<void> download(Map inv, Uint8List bytes) =>
      saver.saveBytes(bytes, invoiceFileName(inv), 'application/pdf');

  /// Shares the PDF file itself (phone share sheet -> WhatsApp sends the file).
  static Future<void> shareFile(Map inv, Uint8List bytes) async {
    final name = invoiceFileName(inv);
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
      fileNameOverrides: [name],
      text: message(inv),
      subject: '${DocType.of(inv['docType']).labelFor(isGstDoc(inv))} ${invNo(inv)}',
    ));
  }

  /// Uploads the PDF and opens WhatsApp chat of [phone] with the PDF link.
  static Future<void> whatsappLink(BuildContext context, Map inv, Uint8List bytes, String phone) async {
    final url = await Api.instance.uploadInvoicePdf('${inv['_id']}', bytes, invoiceFileName(inv));
    final text = message(inv, link: url);
    final p = waPhone(phone);
    final wa = Uri.parse('https://wa.me/${p.isEmpty ? '' : p}?text=${Uri.encodeComponent(text)}');
    if (!context.mounted) return;
    if (kIsWeb) {
      // Browsers block pop-ups opened after a network call, so ask for one more tap.
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
          title: const Text('PDF link ready'),
          content: SelectableText(url),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (ctx.mounted) showSnack(ctx, 'Message copied');
              },
              child: const Text('Copy message'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              onPressed: () {
                launchUrl(wa, webOnlyWindowName: '_blank');
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.chat),
              label: const Text('Open WhatsApp'),
            ),
          ],
        ),
      );
    } else {
      final ok = await launchUrl(wa, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) showSnack(context, 'WhatsApp is not installed', error: true);
    }
  }
}
