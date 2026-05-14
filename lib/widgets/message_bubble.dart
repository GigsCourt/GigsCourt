import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MessageBubble extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  final bool showTimestamp;
  final String? dateDivider;
  final bool isNewMessagesDivider;
  final VoidCallback? onReply;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;

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
      _audioPlayer.onDurationChanged.listen((dur) {
        setState(() => _totalDuration = dur);
      });
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
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(UrlSource(widget.message['voiceUrl'] ?? ''));
    }
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

    return Column(
      children: [
        if (widget.dateDivider != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(widget.dateDivider!, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
          ),
        if (widget.isNewMessagesDivider)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: const Text('New Messages', style: TextStyle(fontSize: 11, color: Color(0xFF1A1F71), fontWeight: FontWeight.w600)),
          ),
        GestureDetector(
          onLongPress: () => _showActions(context),
          child: Align(
            alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: type == 'image' ? _buildImage() : type == 'voice' ? _buildVoice() : _buildText(),
          ),
        ),
        if (widget.showTimestamp && widget.isMine)
          Padding(
            padding: const EdgeInsets.only(right: 4, top: 2),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (createdAt != null)
                    Text(DateFormat('HH:mm').format(createdAt.toDate()), style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                  const SizedBox(width: 4),
                  Icon(isRead ? Icons.done_all : Icons.done, size: 14, color: isRead ? const Color(0xFF1A1F71) : const Color(0xFF6B7280)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildText() {
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isMine ? const Color(0xFF1A1F71) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.isMine ? 18 : 4),
          bottomRight: Radius.circular(widget.isMine ? 4 : 18),
        ),
      ),
      child: Text(
        widget.message['text'] ?? '',
        style: TextStyle(
          color: widget.isMine ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildImage() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        showDialog(
          context: context,
          builder: (ctx) => GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: widget.message['imageUrl'] ?? '',
                  width: MediaQuery.of(context).size.width * 0.85,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        );
      },
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: widget.message['imageUrl'] ?? '',
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              height: 200,
              color: Theme.of(context).cardColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoice() {
    final duration = (widget.message['duration'] as num?)?.toDouble() ?? 0.0;
    final totalMs = _totalDuration.inMilliseconds > 0 ? _totalDuration.inMilliseconds.toDouble() : (duration * 1000);
    final positionMs = _position.inMilliseconds.toDouble();

    return Container(
      width: 200,
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isMine ? const Color(0xFF1A1F71) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.isMine ? 18 : 4),
          bottomRight: Radius.circular(widget.isMine ? 4 : 18),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlayPause,
            child: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              size: 20,
              color: widget.isMine ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: widget.isMine ? Colors.white : const Color(0xFF1A1F71),
                inactiveTrackColor: widget.isMine ? Colors.white.withAlpha(51) : const Color(0xFF6B7280).withAlpha(51),
                thumbColor: widget.isMine ? Colors.white : const Color(0xFF1A1F71),
              ),
              child: Slider(
                value: positionMs.clamp(0, totalMs),
                max: totalMs > 0 ? totalMs : 1,
                onChangeStart: (_) => _isSeeking = true,
                onChanged: _seekTo,
                onChangeEnd: (_) => _isSeeking = false,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _formatDuration(_isPlaying ? _position : Duration(milliseconds: (duration * 1000).toInt())),
            style: TextStyle(
              fontSize: 11,
              color: widget.isMine ? Colors.white.withAlpha(179) : const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  void _showActions(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onReply != null)
              ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () { Navigator.pop(ctx); widget.onReply?.call(); }),
            if (widget.onCopy != null && widget.message['type'] == 'text')
              ListTile(leading: const Icon(Icons.copy), title: const Text('Copy'), onTap: () { Navigator.pop(ctx); widget.onCopy?.call(); }),
            if (widget.onDelete != null)
              ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Delete', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(ctx); widget.onDelete?.call(); }),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
