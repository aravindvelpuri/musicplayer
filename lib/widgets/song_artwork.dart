import 'dart:typed_data';

import 'package:flutter/material.dart';

class SongArtwork extends StatelessWidget {
  const SongArtwork({
    super.key,
    required this.bytes,
    required this.isLoading,
    required this.size,
    required this.borderRadius,
    required this.iconSize,
    this.height,
    this.backgroundColor,
    this.foregroundColor,
  });

  final Uint8List? bytes;
  final bool isLoading;
  final double size;
  final double? height;
  final double borderRadius;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: size,
      height: height ?? size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: ColoredBox(
          color: backgroundColor ?? theme.colorScheme.secondaryContainer,
          child: bytes != null
              ? SizedBox.expand(
                  child: Image.memory(
                    bytes!,
                    fit: BoxFit.fill,
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Icon(
                        Icons.album_rounded,
                        size: iconSize,
                        color:
                            foregroundColor ??
                            theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    if (isLoading)
                      const Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
