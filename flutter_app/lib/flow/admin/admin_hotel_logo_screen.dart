import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../auth_storage.dart';
import '../../dio_client.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/chat_attachment.dart';

/// Upload the hotel logo shown when guests search and browse properties.
class AdminHotelLogoScreen extends StatefulWidget {
  const AdminHotelLogoScreen({super.key});

  @override
  State<AdminHotelLogoScreen> createState() => _AdminHotelLogoScreenState();
}

class _AdminHotelLogoScreenState extends State<AdminHotelLogoScreen> {
  String? _logoUrl;
  String? _hotelName;
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/hotel/logo',
      );
      if (!mounted) return;
      setState(() {
        _logoUrl = (res.data?['logo_url'] ?? res.data?['banner_url'] ?? '')
            .toString()
            .trim();
        _hotelName = (res.data?['hotel_name'] ?? '').toString();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _upload() async {
    final image = await ChatAttachment.pickRoomImageFromGallery(context);
    if (image == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final form = await ChatAttachment.formWithImage(
        fields: const <String, dynamic>{},
        file: image,
      );
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/hotel/logo',
        data: form,
        options: Options(
          contentType: 'multipart/form-data',
          headers: {Headers.acceptHeader: 'application/json'},
        ),
      );
      await AuthStorage.clearHotelsDirectoryCache();
      if (!mounted) return;
      setState(() {
        _logoUrl =
            (res.data?['logo_url'] ?? res.data?['banner_url'] ?? '').toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hotel logo updated. Guests will see it when browsing hotels.',
          ),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dioErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedLogo = ChatAttachment.resolveMediaUrl(_logoUrl ?? '');

    return AppScaffold(
      appBar: AppBar(title: const Text('Hotel logo')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Text(
                      (_hotelName ?? '').isNotEmpty ? _hotelName! : 'Your property',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This image appears when guests search destinations in '
                      '"Where do you want to go?" and browse hotel results.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Preview',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: resolvedLogo.isEmpty
                                    ? ColoredBox(
                                        color: scheme.surfaceContainerHighest,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.apartment_outlined,
                                              size: 48,
                                              color: scheme.outline,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'No logo yet',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      )
                                    : NetworkMediaImage(
                                        url: resolvedLogo,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _uploading ? null : _upload,
                              icon: _uploading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.upload_outlined),
                              label: Text(
                                resolvedLogo.isEmpty
                                    ? 'Upload hotel logo'
                                    : 'Change hotel logo',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Use a clear square or wide image (PNG or JPG). '
                              'Recommended at least 512×512 px.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
