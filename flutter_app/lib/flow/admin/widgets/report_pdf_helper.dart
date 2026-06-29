import 'dart:io';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../../dio_client.dart';

bool _looksLikePdf(Uint8List bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;
}

String? _pdfErrorFromBytes(Uint8List bytes) {
  if (bytes.isEmpty) {
    return 'PDF download returned no data.';
  }
  if (_looksLikePdf(bytes)) return null;
  try {
    final text = String.fromCharCodes(bytes.take(512));
    if (text.trimLeft().startsWith('{') || text.contains('"message"')) {
      return 'Server did not return a PDF. Pull to refresh and try again.';
    }
  } catch (_) {}
  return 'Downloaded file is not a valid PDF.';
}

/// Downloads a server-generated PDF report and opens it with the system viewer.
Future<void> downloadReportPdf({
  required BuildContext context,
  required String path,
  required Map<String, String> queryParameters,
  required String filename,
}) async {
  try {
    final res = await portalDio().get<List<int>>(
      path,
      queryParameters: queryParameters,
      options: Options(
        responseType: ResponseType.bytes,
        headers: const {'Accept': 'application/pdf'},
      ),
    );
    final bytes = Uint8List.fromList(res.data ?? const []);
    final pdfError = _pdfErrorFromBytes(bytes);
    if (pdfError != null) {
      if (context.mounted) {
        showAppMessage(context, pdfError);
      }
      return;
    }

    final safeName = filename.endsWith('.pdf') ? filename : '$filename.pdf';
    final file = File('${Directory.systemTemp.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);

    final result = await OpenFilex.open(file.path, type: 'application/pdf');
    if (!context.mounted) return;
    if (result.type != ResultType.done) {
      showAppMessage(context, result.message.isNotEmpty
                ? result.message
                : 'PDF saved to ${file.path}',);
    }
  } on DioException catch (e) {
    if (!context.mounted) return;
    showAppMessage(context, dioErrorMessage(e), isError: true);
  } catch (e) {
    if (!context.mounted) return;
    showAppMessage(context, '$e');
  }
}
