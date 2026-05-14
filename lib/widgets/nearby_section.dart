import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../services/home_service.dart';
import 'provider_card.dart';

class NearbySection extends StatefulWidget {
  final List<ProviderCardData> initialProviders;
  final bool hasMore;
  final String? nextCursor;
  final Future<PaginatedResult> Function(String? cursor) onFetchMore;
  final Function(ProviderCardData provider) onProviderTap;
  final ScrollController parentScrollController;

  const NearbySection({
    super.key,
    required this.initialProviders,
    required this.hasMore,
    this.nextCursor,
    required this.onFetchMore,
    required this.onProviderTap,
    required this.parentScrollController,
  });

  @override
  State<NearbySection> createState() => _NearbySectionState();
}

class _NearbySectionState extends State<NearbySection> {
  late List<ProviderCardData> _providers;
  String? _nextCursor;
  bool _hasMore = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _providers = widget.initialProviders;
    _nextCursor = widget.nextCursor;
    _hasMore = widget.hasMore;

    widget.parentScrollController.addListener(_onParentScroll);
  }

  @override
  void dispose() {
    widget.parentScrollController.removeListener(_onParentScroll);
    super.dispose();
  }

  void _onParentScroll() {
    final position = widget.parentScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      _fetchMore();
    }
  }

  Future<void> _fetchMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    try {
      final result = await widget.onFetchMore(_nextCursor);
      setState(() {
        _providers.addAll(result.providers);
        _nextCursor = result.nextCursor;
        _hasMore = result.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Nearby Providers',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_providers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 24),
            child: Center(
              child: Text(
                'No providers near you yet.\nBe the first to join GigsCourt!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          )
        else
          GridView.builder(
            key: const PageStorageKey('nearby_grid'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.75,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: _providers.length + (_hasMore ? 2 : 0),
            itemBuilder: (context, index) {
              if (index >= _providers.length) {
                return Shimmer.fromColors(
                  baseColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade800
                      : Colors.grey.shade300,
                  highlightColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade700
                      : Colors.grey.shade100,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }

              return ProviderCard(
                provider: _providers[index],
                isTrending: false,
                onTap: () => widget.onProviderTap(_providers[index]),
              );
            },
          ),
      ],
    );
  }
}
