import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../network/ipfs_url.dart';
import '../theme/app_spacing.dart';
import 'app_skeleton.dart' show AppShimmer, AppSkeletonBlock;

/// Shared network image widget with disk/memory caching, a shimmer
/// placeholder while loading, and a graceful fallback icon on error.
///
/// For Pinata / IPFS logos, pass [cid] (and optionally the stored [url]) so
/// the widget can retry public gateways when a dedicated gateway URL fails.
class AppNetworkImage extends StatefulWidget {
  const AppNetworkImage({
    required this.url,
    this.cid,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackIcon = Icons.image_not_supported_outlined,
    super.key,
  });

  final String url;
  final String? cid;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData fallbackIcon;

  @override
  State<AppNetworkImage> createState() => _AppNetworkImageState();
}

class _AppNetworkImageState extends State<AppNetworkImage> {
  late List<String> _candidates;
  var _index = 0;

  @override
  void initState() {
    super.initState();
    _resetCandidates();
  }

  @override
  void didUpdateWidget(covariant AppNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.cid != widget.cid) {
      _resetCandidates();
    }
  }

  void _resetCandidates() {
    _candidates = IpfsUrl.candidates(url: widget.url, cid: widget.cid);
    if (_candidates.isEmpty && widget.url.trim().isNotEmpty) {
      _candidates = <String>[widget.url.trim()];
    }
    _index = 0;
  }

  void _advanceOnError() {
    if (!mounted) return;
    if (_index + 1 >= _candidates.length) return;
    setState(() => _index += 1);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(AppRadii.chip);
    if (_candidates.isEmpty) {
      return _fallback(context, radius);
    }

    final imageUrl = _candidates[_index];
    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        key: ValueKey<String>(imageUrl),
        imageUrl: imageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder: (context, url) => AppShimmer(
          child: AppSkeletonBlock(
            width: widget.width ?? double.infinity,
            height: widget.height ?? 40,
            borderRadius: radius,
          ),
        ),
        errorWidget: (context, url, error) {
          // Schedule a retry on the next candidate without calling setState
          // during build.
          WidgetsBinding.instance.addPostFrameCallback((_) => _advanceOnError());
          if (_index + 1 < _candidates.length) {
            return AppShimmer(
              child: AppSkeletonBlock(
                width: widget.width ?? double.infinity,
                height: widget.height ?? 40,
                borderRadius: radius,
              ),
            );
          }
          return _fallback(context, radius);
        },
      ),
    );
  }

  Widget _fallback(BuildContext context, BorderRadius radius) {
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          widget.fallbackIcon,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
