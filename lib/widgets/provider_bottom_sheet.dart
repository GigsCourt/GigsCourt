import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/home_service.dart';

class ProviderBottomSheet extends StatelessWidget {
  final ProviderCardData provider;

  const ProviderBottomSheet({
    super.key,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B7280).withAlpha(77),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Photo
              ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: CachedNetworkImage(
                  imageUrl: provider.photoUrl,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(
                    width: 80,
                    height: 80,
                    color: Theme.of(context).cardColor,
                    child: const Icon(Icons.person, size: 40, color: Color(0xFF6B7280)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Name + active dot
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (provider.gigCount7Days >= 1)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 6),
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
                  Flexible(
                    child: Text(
                      provider.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Rating
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, size: 14, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    '${provider.rating.toStringAsFixed(1)} (${provider.reviewCount} reviews)',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Services chips
              if (provider.services.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: provider.services.map((service) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1F71).withAlpha(26),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        service.replaceAll('-', ' '),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF1A1F71)),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),
              // Distance + gigs
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF6B7280)),
                  const SizedBox(width: 4),
                  Text(
                    _formatDistance(provider.distance),
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.work_outline, size: 14, color: Color(0xFF6B7280)),
                  const SizedBox(width: 4),
                  Text(
                    '${provider.gigCount30Days} gigs this month',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Address
              if (provider.workspaceAddress.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    provider.workspaceAddress,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ),
              const SizedBox(height: 24),
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/profile', arguments: provider.uid);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('View Profile'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/chat', arguments: provider.uid);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Message'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m away';
    return '${(meters / 1000).toStringAsFixed(1)}km away';
  }
}
