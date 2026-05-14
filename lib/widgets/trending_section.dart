import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../services/home_service.dart';
import 'provider_card.dart';

class TrendingSection extends StatefulWidget {
  final List<ProviderCardData> initialProviders;
  final bool hasMore;
  final String? nextCursor;
  final Future<PaginatedResult> Function(String? cursor) onFetchMore;
  final Function(ProviderCardData provider) onProviderTap;

  const TrendingSection({
    super.key,
    required this.initialProviders,
    required this.hasMore,
    this.nextCursor,
    required this.onFetchMore,
    required this.onProviderTap,
  });

  @override
  State<TrendingSection> createState() => _TrendingSectionState();
}

class _TrendingSectionState extends State<TrendingSection> {
  final ScrollController _scrollController = ScrollController();
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
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      _fetchMore();
    }
  }

  Future<void> _fetchMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      final result = await widget.onFetchMore(_nextCursor);
      if (mounted) {
        setState(() {
          _providers.addAll(result.providers);
          _nextCursor = result.nextCursor;
          _hasMore = result.hasMore;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_providers.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth * 0.72;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trending', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text('Top providers this week near you', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: cardWidth / 2.5,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _providers.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _providers.length) {
                return Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: SizedBox(
                    width: cardWidth,
                    child: Shimmer.fromColors(
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
                    ),
                  ),
                );
              }
              return Padding(
                padding: EdgeInsets.only(left: index == 0 ? 0 : 4),
                child: SizedBox(
                  width: cardWidth,
                  child: ProviderCard(
                    provider: _providers[index],
                    isTrending: true,
                    onTap: () => widget.onProviderTap(_providers[index]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
