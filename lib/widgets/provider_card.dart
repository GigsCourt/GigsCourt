import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/home_service.dart';

class ProviderCard extends StatelessWidget {
  final ProviderCardData provider;
  final bool isTrending;
  final VoidCallback onTap;

  const ProviderCard({
    super.key,
    required this.provider,
    required this.isTrending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Landscape for Trending (width 2.5x height), Portrait for Nearby
    final aspectRatio = isTrending ? 2.5 : 0.75;

    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Full-bleed photo
              CachedNetworkImage(
                imageUrl: provider.photoUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Shimmer.fromColors(
                  baseColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade800
                      : Colors.grey.shade300,
                  highlightColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade700
                      : Colors.grey.shade100,
                  child: Container(color: Colors.grey),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Theme.of(context).cardColor,
                  child: const Icon(Icons.person, size: 32, color: Color(0xFF6B7280)),
                ),
              ),
              // Gradient overlay from middle to bottom
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withAlpha(180),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              // Content
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Active dot + Name
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF4CAF50),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4CAF50).withAlpha(77),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            provider.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Star + rating
                    Row(
                      children: [
                        const Icon(Icons.star, size: 11, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          '${provider.rating.toStringAsFixed(1)} (${provider.reviewCount})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Services
                    Text(
                      _formatServices(provider.services),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withAlpha(179),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Distance + gigs
                    Text(
                      '${_formatDistance(provider.distance)} · ${provider.gigCount30Days} gigs this month',
                      style: TextStyle(
                        color: Colors.white.withAlpha(179),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatServices(List<String> services) {
    if (services.isEmpty) return '';
    final display = services.take(2).map((s) => s.replaceAll('-', ' ')).join(', ');
    return services.length > 2 ? '$display…' : display;
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }
}
