import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GigBanner extends StatelessWidget {
  final String chatId;
  final String currentUid;
  final String otherUid;
  final String otherName;
  final List<String> providerServices;
  final VoidCallback onRegisterGig;
  final VoidCallback onBuyCredits;

  const GigBanner({
    super.key,
    required this.chatId,
    required this.currentUid,
    required this.otherUid,
    required this.otherName,
    required this.providerServices,
    required this.onRegisterGig,
    required this.onBuyCredits,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').doc(chatId).snapshots(),
      builder: (context, chatSnapshot) {
        if (!chatSnapshot.hasData) return const SizedBox.shrink();

        final chatData = chatSnapshot.data?.data();
        final gigId = chatData?['gigId'] as String?;

        if (gigId == null) {
          return _buildNoGig(context);
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('gigs').doc(gigId).snapshots(),
          builder: (context, gigSnapshot) {
            if (!gigSnapshot.hasData || !gigSnapshot.data!.exists) {
              return _buildNoGig(context);
            }

            final gig = gigSnapshot.data!.data()!;
            final status = gig['status'] ?? 'pending';
            final providerId = gig['providerId'];

            if (status == 'completed' || status == 'cancelled') {
              return _buildNoGig(context);
            }

            final isProvider = providerId == currentUid;

            return _buildPendingBanner(context, isProvider);
          },
        );
      },
    );
  }

  Widget _buildNoGig(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Text(
        'Did you offer your services to $otherName? Register it now to get ratings and reviews to boost your reputation.',
        style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
      ),
    );
  }

  Widget _buildPendingBanner(BuildContext context, bool isProvider) {
    final text = isProvider
        ? 'Waiting for $otherName to rate and review your work'
        : '$otherName is waiting for your rating and review';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: _MarqueeText(text: text),
          ),
        ],
      ),
    );
  }
}

class _MarqueeText extends StatefulWidget {
  final String text;
  const _MarqueeText({required this.text});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    _controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        _controller.duration = Duration(milliseconds: (maxScroll * 20).toInt().clamp(4000, 15000));
        _controller.repeat();
        _controller.addListener(() {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _controller.value * maxScroll,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 40),
            child: Text(
              widget.text,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          );
        },
      ),
    );
  }
}
