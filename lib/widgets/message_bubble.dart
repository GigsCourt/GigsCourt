import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';

class MessageBubble extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  final bool showTimestamp;
  final String? dateDivider;
  final bool isNewMessagesDivider;
  final VoidCallback? onReply;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onConfirmCompletion;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showTimestamp = true,
    this.dateDivider,
    this.isNewMessagesDivider = false,
    this.onReply,
    this.onCopy,
    this.onDelete,
    this.onAccept,
    this.onDecline,
    this.onConfirmCompletion,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isSeeking = false;

  @override
  void initState() {
    super.initState();
    if (widget.message['type'] == 'voice') {
      _audioPlayer.onPositionChanged.listen((pos) {
        if (!_isSeeking) setState(() => _position = pos);
      });
      _audioPlayer.onDurationChanged.listen((dur) => setState(() => _totalDuration = dur));
      _audioPlayer.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
      });
    }
  }

  @override
  void dispose() {
    if (widget.message['type'] == 'voice') _audioPlayer.dispose();
    super.dispose();
  }

  void _togglePlayPause() async {
    if (_isPlaying) { await _audioPlayer.pause(); }
    else { await _audioPlayer.play(UrlSource(widget.message['voiceUrl'] ?? '')); }
  }

  void _seekTo(double value) {
    final seekPos = Duration(milliseconds: value.toInt());
    _audioPlayer.seek(seekPos);
    setState(() => _position = seekPos);
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.message['type'] ?? 'text';
    final createdAt = widget.message['createdAt'] as Timestamp?;
    final isRead = widget.message['read'] == true;

    if (type == 'payment') return _buildPaymentCard();

    return Column(
      children: [
        if (widget.dateDivider != null)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(widget.dateDivider!, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)))),
        if (widget.isNewMessagesDivider)
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: const Text('New Messages', style: TextStyle(fontSize: 11, color: AppTheme.royalBlue, fontWeight: FontWeight.w600))),
        GestureDetector(
          onLongPress: () => _showActions(context),
          child: Align(alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft, child: type == 'image' ? _buildImage() : type == 'voice' ? _buildVoice() : _buildText()),
        ),
        if (widget.showTimestamp && widget.isMine)
          Padding(padding: const EdgeInsets.only(right: 4, top: 2), child: Align(alignment: Alignment.centerRight, child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (createdAt != null) Text(DateFormat('HH:mm').format(createdAt.toDate()), style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
            const SizedBox(width: 4),
            Icon(isRead ? Icons.done_all : Icons.done, size: 14, color: isRead ? AppTheme.royalBlue : const Color(0xFF6B7280)),
          ]))),
      ],
    );
  }

  Widget _buildPaymentCard() {
    final status = widget.message['status'] ?? 'awaiting_provider';
    final itemName = widget.message['itemName'] ?? 'Service';
    final price = (widget.message['price'] ?? 0).toInt();
    final rating = widget.message['rating'] as int?;
    final review = widget.message['review'] as String?;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'awaiting_provider':
        statusColor = Colors.orange;
        statusText = 'Awaiting Provider';
        statusIcon = Icons.hourglass_empty;
        break;
      case 'in_progress':
        statusColor = AppTheme.royalBlue;
        statusText = 'Work in Progress';
        statusIcon = Icons.construction;
        break;
      case 'completed':
        statusColor = const Color(0xFF4CAF50);
        statusText = 'Completed';
        statusIcon = Icons.check_circle;
        break;
      case 'declined':
        statusColor = Colors.red;
        statusText = 'Declined';
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusText = 'Pending';
        statusIcon = Icons.hourglass_empty;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withAlpha(51), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with status
            Row(children: [
              Icon(statusIcon, size: 20, color: statusColor),
              const SizedBox(width: 8),
              Text(statusText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: statusColor)),
              const Spacer(),
              Text('₦$price', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
            ]),
            const SizedBox(height: 8),
            Text(itemName, style: TextStyle(fontSize: 14, color: Theme.of(context).textTheme.bodyLarge?.color)),
            const SizedBox(height: 4),
            Text(widget.isMine ? 'You booked this service' : 'Client booked this service', style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),

            // Completed state - show rating
            if (status == 'completed' && rating != null) ...[
              const SizedBox(height: 12),
              Row(children: List.generate(5, (i) => Icon(i < rating ? Icons.star : Icons.star_border, size: 18, color: i < rating ? Colors.amber : const Color(0xFF6B7280)))),
              if (review != null && review.isNotEmpty) ...[const SizedBox(height: 4), Text(review, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)))],
            ],

            // Action buttons
            if (status == 'awaiting_provider' && !widget.isMine && widget.onAccept != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: ElevatedButton(onPressed: widget.onAccept, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10), shape: const StadiumBorder()), child: const Text('Accept'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: widget.onDecline, style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 10), shape: const StadiumBorder()), child: const Text('Decline'))),
              ]),
            ],

            // Client confirm button
            if (status == 'in_progress' && widget.isMine && widget.onConfirmCompletion != null) ...[
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: widget.onConfirmCompletion, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.royalBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10), shape: const StadiumBorder()), child: const Text('Confirm Completion & Rate'))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildText() {
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: widget.isMine ? AppTheme.royalBlue : Theme.of(context).cardColor, borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(widget.isMine ? 18 : 4), bottomRight: Radius.circular(widget.isMine ? 4 : 18))),
      child: Text(widget.message['text'] ?? '', style: TextStyle(color: widget.isMine ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color, fontSize: 14, height: 1.4)),
    );
  }

  Widget _buildImage() {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); showDialog(context: context, builder: (ctx) => GestureDetector(onTap: () => Navigator.pop(ctx), child: Center(child: ClipRRect(borderRadius: BorderRadius.circular(16), child: CachedNetworkImage(imageUrl: widget.message['imageUrl'] ?? '', width: MediaQuery.of(context).size.width * 0.85, fit: BoxFit.contain))))); },
      child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6), margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedNetworkImage(imageUrl: widget.message['imageUrl'] ?? '', fit: BoxFit.cover, placeholder: (_, __) => Container(height: 200, color: Theme.of(context).cardColor)))),
    );
  }

  Widget _buildVoice() {
    final duration = (widget.message['duration'] as num?)?.toDouble() ?? 0.0;
    final totalMs = _totalDuration.inMilliseconds > 0 ? _totalDuration.inMilliseconds.toDouble() : (duration * 1000);
    final positionMs = _position.inMilliseconds.toDouble();

    return Container(
      width: 200, margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: widget.isMine ? AppTheme.royalBlue : Theme.of(context).cardColor, borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(widget.isMine ? 18 : 4), bottomRight: Radius.circular(widget.isMine ? 4 : 18))),
      child: Row(children: [
        GestureDetector(onTap: _togglePlayPause, child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 20, color: widget.isMine ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color)),
        const SizedBox(width: 8),
        Expanded(child: SliderTheme(data: SliderThemeData(trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), activeTrackColor: widget.isMine ? Colors.white : AppTheme.royalBlue, inactiveTrackColor: widget.isMine ? Colors.white.withAlpha(51) : const Color(0xFF6B7280).withAlpha(51), thumbColor: widget.isMine ? Colors.white : AppTheme.royalBlue), child: Slider(value: positionMs.clamp(0, totalMs), max: totalMs > 0 ? totalMs : 1, onChangeStart: (_) => _isSeeking = true, onChanged: _seekTo, onChangeEnd: (_) => _isSeeking = false))),
        const SizedBox(width: 4),
        Text(_formatDuration(_isPlaying ? _position : Duration(milliseconds: (duration * 1000).toInt())), style: TextStyle(fontSize: 11, color: widget.isMine ? Colors.white.withAlpha(179) : const Color(0xFF6B7280))),
      ]),
    );
  }

  void _showActions(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(context: context, backgroundColor: Theme.of(context).scaffoldBackgroundColor, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (widget.onReply != null) ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () { Navigator.pop(ctx); widget.onReply?.call(); }),
      if (widget.onCopy != null && widget.message['type'] == 'text') ListTile(leading: const Icon(Icons.copy), title: const Text('Copy'), onTap: () { Navigator.pop(ctx); widget.onCopy?.call(); }),
      if (widget.onDelete != null) ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Delete', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(ctx); widget.onDelete?.call(); }),
    ])));
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
