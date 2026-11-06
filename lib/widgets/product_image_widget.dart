import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../services/app_release_service.dart';

class ProductImageWidget extends StatelessWidget {
  static final _base64MemoryCache = <String, Uint8List>{};
  static int _cachedBytes = 0;
  static const _maxCachedBytes = 8 * 1024 * 1024;

  final String? imageUrl;
  final String category;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? fallbackWidget;

  const ProductImageWidget({
    super.key,
    required this.imageUrl,
    this.category = 'Coffee',
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackWidget,
  });

  static Uint8List _decodeBase64Cached(String dataUrl) {
    final cached = _base64MemoryCache.remove(dataUrl);
    if (cached != null) {
      _base64MemoryCache[dataUrl] = cached;
      return cached;
    }

    final commaIndex = dataUrl.indexOf(',');
    final rawBase64 = commaIndex != -1
        ? dataUrl.substring(commaIndex + 1)
        : dataUrl;
    final bytes = base64Decode(rawBase64.replaceAll(RegExp(r'\s+'), ''));

    if (bytes.length > _maxCachedBytes) return bytes;
    while (_base64MemoryCache.isNotEmpty &&
        (_base64MemoryCache.length >= 120 || _cachedBytes + bytes.length > _maxCachedBytes)) {
      _cachedBytes -= _base64MemoryCache.remove(_base64MemoryCache.keys.first)!.length;
    }
    _base64MemoryCache[dataUrl] = bytes;
    _cachedBytes += bytes.length;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.zero;
    final imagesEnabled = context.watch<AppReleaseService?>()?.enabled('product_images') ?? true;
    final url = imagesEnabled ? imageUrl?.trim() : null;

    if (url == null || url.isEmpty) {
      return ClipRRect(
        borderRadius: br,
        child: SizedBox(
          width: width,
          height: height,
          child: fallbackWidget ?? _buildPlaceholder(),
        ),
      );
    }

    Widget imageWidget;

    try {
      if (url.startsWith('data:image/')) {
        final bytes = _decodeBase64Cached(url);
        imageWidget = Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallbackWidget ?? _buildPlaceholder(),
        );
      } else if (url.startsWith('http://') || url.startsWith('https://')) {
        imageWidget = Image.network(
          url,
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallbackWidget ?? _buildPlaceholder(),
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Container(
              width: width,
              height: height,
              color: AppTheme.surfaceSubtle,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accentAmber,
                  ),
                ),
              ),
            );
          },
        );
      } else if (!kIsWeb && File(url).existsSync()) {
        imageWidget = Image.file(
          File(url),
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallbackWidget ?? _buildPlaceholder(),
        );
      } else {
        imageWidget = fallbackWidget ?? _buildPlaceholder();
      }
    } catch (_) {
      imageWidget = fallbackWidget ?? _buildPlaceholder();
    }

    return ClipRRect(
      borderRadius: br,
      child: SizedBox(
        width: width,
        height: height,
        child: imageWidget,
      ),
    );
  }

  Widget _buildPlaceholder() {
    IconData icon = Icons.coffee_rounded;
    final cat = category.toLowerCase();
    final isHiburan =
        cat.contains('hiburan') || cat.contains('rental') || cat.contains('ps');

    if (isHiburan) {
      icon = Icons.sports_esports_rounded;
    } else if (cat.contains('pastry') ||
        cat.contains('roti') ||
        cat.contains('croissant')) {
      icon = Icons.bakery_dining_rounded;
    } else if (cat.contains('snack') ||
        cat.contains('makan') ||
        cat.contains('fries')) {
      icon = Icons.fastfood_rounded;
    } else if (cat.contains('tea') ||
        cat.contains('matcha') ||
        cat.contains('velvet') ||
        cat.contains('non-coffee')) {
      icon = Icons.local_drink_rounded;
    }

    return Container(
      color: isHiburan ? AppTheme.accentCopperSoft : AppTheme.surfaceLight,
      child: Center(
        child: Icon(
          icon,
          size: (height != null && height! < 60) ? 22 : 36,
          color: isHiburan
              ? AppTheme.accentAmber
              : AppTheme.textMuted.withValues(alpha: 0.42),
        ),
      ),
    );
  }
}
