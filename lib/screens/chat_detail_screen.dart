import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../services/chat_service.dart';
import '../services/image_service.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import '../widgets/gig_banner.dart';
import '../utils/error_handler.dart';

class ChatDetailScreen extends StatefulWidget {
  final String otherUid;

  const ChatDetailScreen({super.key, required this.otherUid});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final ChatService _chatService = ChatService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImageService _imageService = ImageService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ImagePicker _picker = ImagePicker();

  String _chatId = '';
  Map<String, dynamic>? _otherProfile;
  Map<String, dynamic>? _myProfile;
  bool _isRecording = false;
  bool _showScrollFab = false;
  bool _isTyping = false;
  Timer? _typingTimer;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  static const int _maxRecordingSeconds = 60;

  final Set<String> _failedMessageIds = {};
  final Map<String, String> _pendingRetryTexts = {};

  @override
  void initState() {
    super.initState();
    _chatId = _chatService.getChatId(widget.otherUid);
    _loadProfiles();
    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        setState(() => _showScrollFab = _scrollController.offset > 500);
      }
    });
    _textController.addListener(_onTextControllerChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextControllerChanged);
    _textController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _chatService.setTyping(_chatId, false);
    super.dispose();
  }

  void _onTextControllerChanged() {
    // Rebuild to toggle mic/send button
    setState(() {});
    _onTextChanged(_textController.text);
  }

  Future<void> _loadProfiles() async {
    try {
      final otherDoc = await _firestore.collection('profiles').doc(widget.otherUid).get();
      final myDoc = await _firestore.collection('profiles').doc(FirebaseAuth.instance.currentUser?.uid ?? '').get();
      if (mounted) {
        setState(() {
          _otherProfile = otherDoc.data();
          _myProfile = myDoc.data();
        });
      }
      _chatService.markAsRead(_chatId);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _onTextChanged(String text) {
    final isTypingNow = text.isNotEmpty;
    if (isTypingNow != _isTyping) {
      _isTyping = isTypingNow;
      _chatService.setTyping(_chatId, _isTyping);
      _typingTimer?.cancel();
      if (_isTyping) {
        _typingTimer = Timer(const Duration(seconds: 3), () {
          _isTyping = false;
          _chatService.setTyping(_chatId, false);
        });
      }
    }
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final pendingText = text;
    _textController.clear();
    _onTextChanged('');
    HapticFeedback.lightImpact();
    try {
      await _chatService.sendMessage(_chatId, pendingText);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        // Restore text on failure
        _textController.text = pendingText;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to send. Tap retry.'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _sendText(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _sendImage() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(ctx);
                final file = await _imageService.takePhoto();
                if (file != null) {
                  await _chatService.sendImage(_chatId, file);
                  _scrollToBottom();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(ctx);
                final file = await _imageService.pickFromGallery();
                if (file != null) {
                  await _chatService.sendImage(_chatId, file);
                  _scrollToBottom();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission required')));
      return;
    }
    HapticFeedback.mediumImpact();
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    _recordingSeconds = 0;
    setState(() => _isRecording = true);

    // Start countdown timer
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _recordingSeconds++;
      if (_recordingSeconds >= _maxRecordingSeconds) {
        _stopRecording();
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    final path = await _audioRecorder.stop();
    final duration = _recordingSeconds;
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
    });
    if (path != null) {
      HapticFeedback.heavyImpact();
      final file = File(path);
      await _chatService.sendVoice(_chatId, file, duration.toDouble().clamp(0.5, 60));
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // reverse: true list, so position 0 is the bottom (latest messages)
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _onRegisterGig() async {
    HapticFeedback.mediumImpact();
    final services = List<String>.from(_myProfile?['services'] ?? []);
    if (services.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You have no services listed. Add services in your profile.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register Gig'),
        content: Text('Do you want to register a gig with ${_otherProfile?['name'] ?? 'this user'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );

    if (confirmed != true) return;

    final credits = (_myProfile?['credits'] ?? 0).toInt();
    if (credits < 1) {
      final buyCredits = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Insufficient Credits'),
          content: const Text('You need credits to register a gig. Credits allow clients to rate and review your work.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buy Credits')),
          ],
        ),
      );
      if (buyCredits == true) {
        Navigator.of(context, rootNavigator: true).pushNamed('/settings');
      }
      return;
    }

    final serviceChoice = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String chosen = services.first;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Select Service'),
            content: DropdownButton<String>(
              value: chosen,
              items: services.map((s) => DropdownMenuItem(value: s, child: Text(s.replaceAll('-', ' ')))).toList(),
              onChanged: (v) { if (v != null) setState(() => chosen = v); },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, chosen), child: const Text('Confirm')),
            ],
          ),
        );
      },
    );

    if (serviceChoice != null) {
      try {
        await _chatService.registerGig(_chatId, widget.otherUid, serviceChoice);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _onGigButtonTap(String? gigId, String? providerId, String status) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isProvider = providerId == currentUid;

    if (status == 'pending') {
      if (isProvider) {
        final cancel = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cancel Gig'),
            content: const Text('Do you want to cancel this gig?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
            ],
          ),
        );
        if (cancel == true && gigId != null) {
          await _chatService.cancelGig(gigId);
        }
      } else {
        final action = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: const Text('Submit Review & Rating'),
                  onTap: () => Navigator.pop(ctx, 'review'),
                ),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                  title: const Text('Cancel Gig', style: TextStyle(color: Colors.red)),
                  onTap: () => Navigator.pop(ctx, 'cancel'),
                ),
              ],
            ),
          ),
        );
        if (action == 'review' && gigId != null) {
          _showReviewSheet(gigId);
        } else if (action == 'cancel' && gigId != null) {
          await _chatService.cancelGig(gigId);
        }
      }
    }
  }

  void _showReviewSheet(String gigId) {
    int rating = 0;
    final textController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Submit Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) => GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => rating = i + 1);
                      },
                      child: Icon(
                        i < rating ? Icons.star : Icons.star_border,
                        size: 36,
                        color: i < rating ? Colors.amber : const Color(0xFF6B7280),
                      ),
                    )),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: textController,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Write your review (optional)...', alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: rating == 0 ? null : () async {
                      HapticFeedback.mediumImpact();
                      Navigator.pop(ctx);
                      try {
                        await _chatService.submitReview(gigId, rating, textController.text.trim().isEmpty ? null : textController.text.trim());
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    },
                    child: const Text('Submit Review'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _otherProfile != null
            ? GestureDetector(
                onTap: () {
                  Navigator.of(context, rootNavigator: true).pushNamed('/profile', arguments: widget.otherUid);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedNetworkImage(
                        imageUrl: _otherProfile?['photoUrl'] ?? '',
                        width: 28, height: 28, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 28, height: 28, color: Theme.of(context).cardColor,
                          child: Icon(Icons.person, size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _otherProfile?['name'] ?? 'User',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color),
                      ),
                    ),
                  ],
                ),
              )
            : null,
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: _firestore.collection('chats').doc(_chatId).snapshots(),
            builder: (context, chatSnapshot) {
              final chatData = chatSnapshot.data?.data();
              final gigId = chatData != null ? (chatData as Map<String, dynamic>)['gigId'] as String? : null;

              if (gigId == null) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    onPressed: _onRegisterGig,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.royalBlue),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: const StadiumBorder(),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('Register Gig', style: TextStyle(fontSize: 11)),
                  ),
                );
              }

              return StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('gigs').doc(gigId).snapshots(),
                builder: (context, gigSnapshot) {
                  if (!gigSnapshot.hasData || !gigSnapshot.data!.exists) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OutlinedButton(
                        onPressed: _onRegisterGig,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.royalBlue),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: const StadiumBorder(),
                          minimumSize: Size.zero,
                        ),
                        child: const Text('Register Gig', style: TextStyle(fontSize: 11)),
                      ),
                    );
                  }

                  final gig = gigSnapshot.data!.data()! as Map<String, dynamic>;
                  final status = gig['status'] ?? 'pending';
                  final providerId = gig['providerId'] as String?;

                  if (status == 'completed' || status == 'cancelled') {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OutlinedButton(
                        onPressed: _onRegisterGig,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.royalBlue),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: const StadiumBorder(),
                          minimumSize: Size.zero,
                        ),
                        child: const Text('Register Gig', style: TextStyle(fontSize: 11)),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      onPressed: () => _onGigButtonTap(gigId, providerId, status),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: const StadiumBorder(),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('Pending', style: TextStyle(fontSize: 11, color: Colors.red)),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_otherProfile != null)
            GigBanner(
              chatId: _chatId,
              currentUid: FirebaseAuth.instance.currentUser?.uid ?? '',
              otherUid: widget.otherUid,
              otherName: _otherProfile?['name'] ?? 'User',
              providerServices: List<String>.from(_myProfile?['services'] ?? []),
              onRegisterGig: _onRegisterGig,
              onBuyCredits: () {},
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _chatService.getMessages(_chatId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!.docs;
                if (messages.isEmpty) {
                  return Center(
                    child: Text('Send a message to start the conversation',
                      style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 13)),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final reversedIndex = messages.length - 1 - index;
                    final doc = messages[reversedIndex];
                    final msg = doc.data() as Map<String, dynamic>;
                    final isMine = msg['senderId'] == FirebaseAuth.instance.currentUser?.uid;
                    final deleted = msg['deleted_for_${FirebaseAuth.instance.currentUser?.uid}'] == true;
                    if (deleted) return const SizedBox.shrink();
                    return MessageBubble(
                      message: msg,
                      isMine: isMine,
                      onDelete: () => _chatService.deleteMessage(_chatId, doc.id, isMine),
                      onCopy: msg['type'] == 'text' ? () {
                        Clipboard.setData(ClipboardData(text: msg['text'] ?? ''));
                        HapticFeedback.selectionClick();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                      } : null,
                    );
                  },
                );
              },
            ),
          ),
          // Recording timer display
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Recording ${_maxRecordingSeconds - _recordingSeconds}s remaining',
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ),
            ),
          StreamBuilder<bool>(
            stream: _chatService.isOtherUserTyping(_chatId),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return const Padding(
                  padding: EdgeInsets.only(left: 16, bottom: 4),
                  child: Text('typing...', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280), fontStyle: FontStyle.italic)),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(top: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(13) : Colors.black.withAlpha(13),
                width: 0.5,
              )),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    _sendImage();
                  },
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF6B7280).withAlpha(77)),
                    ),
                    child: const Icon(Icons.add, size: 20, color: Color(0xFF6B7280)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withAlpha(26)
                            : Colors.black.withAlpha(26),
                      ),
                    ),
                    child: TextField(
                      controller: _textController,
                      maxLines: 4, minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _textController.text.isEmpty
                    ? GestureDetector(
                        onTap: _isRecording ? _stopRecording : _startRecording,
                        onLongPress: _startRecording,
                        onLongPressUp: _stopRecording,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isRecording ? Colors.red : Colors.transparent,
                            border: Border.all(color: _isRecording ? Colors.red : const Color(0xFF6B7280).withAlpha(77)),
                          ),
                          child: Icon(
                            _isRecording ? Icons.mic : Icons.mic_outlined,
                            size: 20,
                            color: _isRecording ? Colors.white : const Color(0xFF6B7280),
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: _sendText,
                        child: Container(
                          width: 36, height: 36,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.royalBlue,
                          ),
                          child: const Icon(Icons.arrow_upward, size: 20, color: Colors.white),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
