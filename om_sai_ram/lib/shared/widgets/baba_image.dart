import 'package:flutter/material.dart';

const babaPhotoUrl =
    'https://upload.wikimedia.org/wikipedia/commons/7/7e/Sai_Baba_of_Shirdi_with_garland.jpg';
const babaAtDwarakamaiPhotoUrl =
    'https://upload.wikimedia.org/wikipedia/commons/a/aa/Shirdi_Sai_Baba_on_steps_of_Dwarakamai.jpg';
const babaReadingPhotoUrl =
    'https://upload.wikimedia.org/wikipedia/commons/7/7f/Shirdi_Sai_Baba_reading.jpg';

/// A verified public-domain historical photograph of Sai Baba of Shirdi.
class BabaImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double height;
  final double borderRadius;
  final BoxFit fit;
  final Alignment alignment;

  const BabaImage({
    super.key,
    this.imageUrl = babaPhotoUrl,
    this.width,
    required this.height,
    this.borderRadius = 16,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        semanticLabel: 'Sai Baba of Shirdi',
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : _BabaImageFallback(width: width, height: height),
        errorBuilder: (_, __, ___) => _BabaImageFallback(
          width: width,
          height: height,
          color: colors.primaryContainer,
        ),
      ),
    );
  }
}

class _BabaImageFallback extends StatelessWidget {
  final double? width;
  final double height;
  final Color? color;
  const _BabaImageFallback({this.width, required this.height, this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.temple_hindu_rounded,
            size: height.clamp(24, 56),
            color: Theme.of(context).colorScheme.primary),
      );
}
