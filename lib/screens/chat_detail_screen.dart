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
import '../services/payment_service.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import '../utils/error_handler.dart';
import 'payment_webview_screen.dart';

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
  final PaymentService _paymentService = PaymentService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ImagePicker _picker = ImagePicker();

  String _chatId = '';
  Map<String, dynamic>? _otherProfile;
  Map<String, dynamic>? _myProfile;
  bool _isRecording = false;
  bool _isTyping = false;
  Timer? _typingTimer;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  static const int _maxRecordingSeconds = 60;

  @override
  void initState() {
    super.initState();
    _chatId = _chatService.getChatId(widget.otherUid);
    _loadProfiles();
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
        _textController.text = pendingText;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Failed to send. Tap retry.'), action: SnackBarAction(label: 'Retry', onPressed: () => _sendText())),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Take Photo'), onTap: () async { Navigator.pop(ctx); final file = await _imageService.takePhoto(); if (file != null) { await _chatService.sendImage(_chatId, file); _scrollToBottom(); } }),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from Gallery'), onTap: () async { Navigator.pop(ctx); final file = await _imageService.pickFromGallery(); if (file != null) { await _chatService.sendImage(_chatId, file); _scrollToBottom(); } }),
        ]),
      ),
    );
  }

  Future<void> _startRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission required'))); return; }
    HapticFeedback.mediumImpact();
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    _recordingSeconds = 0;
    setState(() => _isRecording = true);
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) { _recordingSeconds++; if (_recordingSeconds >= _maxRecordingSeconds) _stopRecording(); if (mounted) setState(() {}); });
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    final path = await _audioRecorder.stop();
    final duration = _recordingSeconds;
    setState(() { _isRecording = false; _recordingSeconds = 0; });
    if (path != null) { HapticFeedback.heavyImpact(); final file = File(path); await _chatService.sendVoice(_chatId, file, duration.toDouble().clamp(0.5, 60)); _scrollToBottom(); }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollController.hasClients) { _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); } });
  }

  void _showViewServices() {
    final categories = List<Map<String, dynamic>>.from(_otherProfile?['serviceCategories'] ?? []);
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This provider has no services listed.')));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF6B7280).withAlpha(77), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('${_otherProfile?['name'] ?? 'Provider'}\'s Services', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
            const SizedBox(height: 16),
            ...categories.map((cat) {
              final items = List<Map<String, dynamic>>.from(cat['items'] ?? []);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppTheme.royalBlue.withAlpha(26), borderRadius: BorderRadius.circular(12)), child: Text(cat['name'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.royalBlue))),
                const SizedBox(height: 6),
                ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child: Text(item['name'] ?? '', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyLarge?.color))),
                    Text('₦${(item['price'] ?? 0).toInt()}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.royalBlue)),
                    const SizedBox(width: 8),
                    SizedBox(height: 28, child: ElevatedButton(
                      onPressed: () { Navigator.pop(ctx); _startPaymentFromChat(item['name'] ?? '', (item['price'] ?? 0).toInt()); },
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.royalBlue, padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: Size.zero, textStyle: const TextStyle(fontSize: 11)),
                      child: const Text('Book'),
                    )),
                  ]),
                )),
                const SizedBox(height: 8),
              ]);
            }),
          ]),
        ),
      ),
    );
  }

  Future<void> _startPaymentFromChat(String itemName, int price) async {
    final providerName = _otherProfile?['name'] ?? 'Provider';
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Confirm Booking'), content: Text('Book "$itemName" from $providerName for ₦$price?'), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
    ]));
    if (confirmed != true) return;

    final proceed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Payment'), content: const Text('Please do not close the payment page while your transaction is being processed.'), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
    ]));
    if (proceed != true) return;

    HapticFeedback.mediumImpact();
    final result = await _paymentService.initializeGigPayment(providerId: widget.otherUid, providerName: providerName, itemName: itemName, price: price);
    if (result == null) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to initialize payment.'))); return; }

    final authorizationUrl = result['authorizationUrl'] as String;
    final reference = result['reference'] as String;
    if (mounted) {
      final paymentResult = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PaymentWebViewScreen(authorizationUrl: authorizationUrl, reference: reference, callbackUrl: 'https://gigscourt.com/payment/callback')));
      if (paymentResult != null && paymentResult is Map && paymentResult['status'] == 'success') {
        await _paymentService.createGigAfterPayment(providerId: widget.otherUid, clientId: FirebaseAuth.instance.currentUser?.uid ?? '', itemName: itemName, price: price, reference: reference);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment successful! The provider will be notified.')));
      }
    }
  }

  void _showConfirmCompletionSheet(String gigId) {
    int rating = 0;
    final textController = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Confirm Completion & Rate', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) => GestureDetector(
              onTap: () { HapticFeedback.selectionClick(); setSheetState(() => rating = i + 1); },
              child: Icon(i < rating ? Icons.star : Icons.star_border, size: 36, color: i < rating ? Colors.amber : const Color(0xFF6B7280)),
            ))),
            const SizedBox(height: 16),
            TextField(controller: textController, maxLines: 3, decoration: const InputDecoration(hintText: 'Write your review (optional)...')),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: rating == 0 ? null : () async {
                HapticFeedback.mediumImpact(); Navigator.pop(ctx);
                try { await _paymentService.completeGig(gigId, rating, textController.text.trim().isEmpty ? null : textController.text.trim()); }
                catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
              },
              child: const Text('Submit Review'),
            ),
          ]),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color), onPressed: () => Navigator.of(context).pop()),
        title: _otherProfile != null
            ? GestureDetector(
                onTap: () => Navigator.of(context, rootNavigator: true).pushNamed('/profile', arguments: widget.otherUid),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(borderRadius: BorderRadius.circular(14), child: CachedNetworkImage(imageUrl: _otherProfile?['photoUrl'] ?? '', width: 28, height: 28, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(width: 28, height: 28, color: Theme.of(context).cardColor, child: Icon(Icons.person, size: 14, color: Theme.of(context).textTheme.bodySmall?.color)))),
                  const SizedBox(width: 8),
                  Flexible(child: Text(_otherProfile?['name'] ?? 'User', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color))),
                ]),
              )
            : null,
        actions: [
          IconButton(icon: const Icon(Icons.work_outline), onPressed: _showViewServices, tooltip: 'View Services'),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _chatService.getMessages(_chatId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final messages = snapshot.data!.docs;
              if (messages.isEmpty) return Center(child: Text('Send a message to start the conversation', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 13)));
              return ListView.builder(
                controller: _scrollController, reverse: true, padding: const EdgeInsets.only(bottom: 8), itemCount: messages.length,
                itemBuilder: (context, index) {
                  final reversedIndex = messages.length - 1 - index;
                  final doc = messages[reversedIndex];
                  final msg = doc.data() as Map<String, dynamic>;
                  final isMine = msg['senderId'] == currentUid;
                  final deleted = msg['deleted_for_$currentUid'] == true;
                  if (deleted) return const SizedBox.shrink();

                  return MessageBubble(
                    message: msg,
                    isMine: isMine,
                    onDelete: () => _chatService.deleteMessage(_chatId, doc.id, isMine),
                    onCopy: msg['type'] == 'text' ? () { Clipboard.setData(ClipboardData(text: msg['text'] ?? '')); HapticFeedback.selectionClick(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'))); } : null,
                    onAccept: msg['type'] == 'payment' ? () => _paymentService.acceptGig(msg['gigId'] ?? '') : null,
                    onDecline: msg['type'] == 'payment' ? () => _paymentService.declineGig(msg['gigId'] ?? '') : null,
                    onConfirmCompletion: msg['type'] == 'payment' && msg['status'] == 'in_progress' ? () => _showConfirmCompletionSheet(msg['gigId'] ?? '') : null,
                  );
                },
              );
            },
          ),
        ),
        if (_isRecording) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red)), const SizedBox(width: 8), Text('Recording ${_maxRecordingSeconds - _recordingSeconds}s remaining', style: const TextStyle(fontSize: 12, color: Colors.red))])),
        StreamBuilder<bool>(stream: _chatService.isOtherUserTyping(_chatId), builder: (context, snapshot) {
          if (snapshot.data == true) return const Padding(padding: EdgeInsets.only(left: 16, bottom: 4), child: Text('typing...', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280), fontStyle: FontStyle.italic)));
          return const SizedBox.shrink();
        }),
        Container(
          decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, border: Border(top: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(13) : Colors.black.withAlpha(13), width: 0.5))),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(children: [
            GestureDetector(onTap: () { FocusScope.of(context).unfocus(); _sendImage(); }, child: Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF6B7280).withAlpha(77))), child: const Icon(Icons.add, size: 20, color: Color(0xFF6B7280)))),
            const SizedBox(width: 6),
            Expanded(child: Container(decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(26) : Colors.black.withAlpha(26))), child: TextField(controller: _textController, maxLines: 4, minLines: 1, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Message...', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8), isDense: true)))),
            const SizedBox(width: 6),
            _textController.text.isEmpty
                ? GestureDetector(onTap: _isRecording ? _stopRecording : _startRecording, onLongPress: _startRecording, onLongPressUp: _stopRecording, child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: _isRecording ? Colors.red : Colors.transparent, border: Border.all(color: _isRecording ? Colors.red : const Color(0xFF6B7280).withAlpha(77))), child: Icon(_isRecording ? Icons.mic : Icons.mic_outlined, size: 20, color: _isRecording ? Colors.white : const Color(0xFF6B7280))))
                : GestureDetector(onTap: _sendText, child: Container(width: 36, height: 36, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.royalBlue), child: const Icon(Icons.arrow_upward, size: 20, color: Colors.white))),
          ]),
        ),
      ]),
    );
  }
}
