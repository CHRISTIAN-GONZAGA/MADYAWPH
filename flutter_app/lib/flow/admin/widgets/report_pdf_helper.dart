import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../dio_client.dart';

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
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(res.data ?? const []);
    if (bytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF download returned no data.')),
        );
      }
      return;
    }
    final file = File('${Directory.systemTemp.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    final uri = Uri.file(file.path);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved PDF to ${file.path}')),
        );
      }
    }
  } on DioException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(dioErrorMessage(e))),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$e')),
    );
  }
}
