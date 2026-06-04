// lib/screens/translator/video_call_screen.dart
// =============================================
// WebRTC video call with BIM sign language subtitle translation.
//
// OPTION 4 — Single Camera Session Architecture:
//
//   SIGNING OFF:
//     WebRTC owns camera via getUserMedia (video: true)
//     Local background: RTCVideoView of local stream
//     Remote PiP: RTCVideoView of remote stream
//     Sign detection: disabled
//
//   SIGNING ON:
//     WebRTC releases camera — getUserMedia called with video: false
//     CameraX owns camera via ImageAnalysis use case
//     Local background: Image.memory from CameraX JPEG frames (VIDEO_CHANNEL)
//     Remote PiP (what you see of remote): RTCVideoView or remote JPEG
//     Sign detection: active via FRAMES_CHANNEL → extractKeypoints → processFrame
//     Sign subtitles: detected sign sent via DataChannel 'signs' → shown on remote
//
// SIGNALING:
//   Supabase DB table `rooms` — offer/answer SDPs
//   Supabase DB table `ice_candidates` — ICE candidates
//   Supabase Realtime postgres_changes — triggers on both tables

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signlingo/services/camerax_bridge.dart';

const int _kSubtitleFadeMs    = 3000;
const int _kIceTimeoutSeconds = 20;

const Color bgColor     = Color(0xFF131415);
const Color cardColor   = Color(0xFF1E2124);
const Color borderColor = Color(0xFF373A3F);

// ─────────────────────────────────────────────────────────────────────────────
// SIGNALING
// ─────────────────────────────────────────────────────────────────────────────
class Signaling {

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {
        'urls'      : 'turn:openrelay.metered.ca:80',
        'username'  : 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls'      : 'turn:openrelay.metered.ca:443',
        'username'  : 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls'      : 'turn:openrelay.metered.ca:443?transport=tcp',
        'username'  : 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  RTCPeerConnection? peerConnection;

  // Signs DataChannel — sends detected sign labels as text
  RTCDataChannel? dataChannel;

  // Video DataChannel — sends JPEG frames as binary when signing is ON
  // Unordered + maxRetransmits=0: drop stale frames, never queue them
  RTCDataChannel? videoChannel;

  MediaStream? localStream;
  MediaStream? remoteStream;

  // Callbacks
  void Function(MediaStream)?            onAddRemoteStream;
  void Function(RTCIceConnectionState)?  onIceConnectionState;
  void Function(RTCPeerConnectionState)? onPeerConnectionState;
  void Function()?                       onCallEnded;
  void Function(String)?                 onRemoteSign;
  void Function(Uint8List)?              onRemoteVideoFrame;

  final _supabase = Supabase.instance.client;
  RealtimeChannel? _roomsChannel;
  RealtimeChannel? _iceChannel;

  bool   _remoteDescSet = false;
  bool   _disposed      = false;
  bool   _isCaller      = false;
  String _roomId        = '';

  // ── Open local media ───────────────────────────────────────────────────
  // audioOnly = true when signing is ON (CameraX owns camera)
  // audioOnly = false when signing is OFF (WebRTC owns camera)
  Future<void> openUserMedia(
    RTCVideoRenderer localRenderer, {
    bool audioOnly = false,
  }) async {
    // Stop any existing stream first
    localStream?.getTracks().forEach((t) => t.stop());
    localStream?.dispose();
    localStream = null;

    if (audioOnly) {
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
    } else {
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user'},
      });
      localRenderer.srcObject = localStream;
    }
  }

  // ── Caller flow ────────────────────────────────────────────────────────
  Future<void> createRoom(String roomId, RTCVideoRenderer remoteRenderer) async {
    _isCaller = true;
    _roomId   = roomId;

    await _buildPeerConnection(roomId);

    final offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    await _supabase.from('rooms').upsert({
      'id'         : roomId,
      'offer_sdp'  : offer.sdp,
      'offer_type' : offer.type,
      'answer_sdp' : null,
      'answer_type': null,
    });
    debugPrint('[Signaling] Offer written');

    _roomsChannel = _supabase.channel('rooms-$roomId')
      ..onPostgresChanges(
        event   : PostgresChangeEvent.update,
        schema  : 'public',
        table   : 'rooms',
        filter  : PostgresChangeFilter(
          type  : PostgresChangeFilterType.eq,
          column: 'id',
          value : roomId,
        ),
        callback: (payload) async {
          if (_disposed) return;
          final row        = payload.newRecord;
          final answerSdp  = row['answer_sdp']  as String?;
          final answerType = row['answer_type'] as String?;
          if (answerSdp != null && answerType != null && !_remoteDescSet) {
            _remoteDescSet = true;
            debugPrint('[Signaling] Answer received via Realtime');
            await peerConnection!.setRemoteDescription(
              RTCSessionDescription(answerSdp, answerType),
            );
          }
        },
      )
      ..onPostgresChanges(
        event   : PostgresChangeEvent.delete,
        schema  : 'public',
        table   : 'rooms',
        callback: (payload) {
          if (_disposed) return;
          onCallEnded?.call();
        },
      )
      ..subscribe();

    _listenForRemoteCandidates(roomId, listenForRole: 'callee');
    _pollForAnswer(roomId);
  }

  // ── Callee flow ────────────────────────────────────────────────────────
  Future<void> joinRoom(String roomId, RTCVideoRenderer remoteRenderer) async {
    _isCaller = false;
    _roomId   = roomId;

    final rows = await _supabase
        .from('rooms').select().eq('id', roomId).limit(1);

    if (rows.isEmpty) {
      debugPrint('[Signaling] Room $roomId not found');
      return;
    }

    final row = rows.first as Map<String, dynamic>;
    await _buildPeerConnection(roomId);

    _remoteDescSet = true;
    await peerConnection!.setRemoteDescription(RTCSessionDescription(
      row['offer_sdp']  as String,
      row['offer_type'] as String,
    ));

    final answer = await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);

    await _supabase.from('rooms').update({
      'answer_sdp' : answer.sdp,
      'answer_type': answer.type,
    }).eq('id', roomId);
    debugPrint('[Signaling] Answer written');

    _listenForRemoteCandidates(roomId, listenForRole: 'caller');

    _roomsChannel = _supabase.channel('rooms-$roomId')
      ..onPostgresChanges(
        event   : PostgresChangeEvent.delete,
        schema  : 'public',
        table   : 'rooms',
        callback: (payload) {
          if (_disposed) return;
          onCallEnded?.call();
        },
      )
      ..subscribe();
  }

  void _listenForRemoteCandidates(String roomId, {required String listenForRole}) {
    _supabase
        .from('ice_candidates')
        .select()
        .eq('room_id', roomId)
        .eq('role', listenForRole)
        .then((rows) async {
      for (final row in rows) await _addCandidate(row);
    });

    _iceChannel = _supabase.channel('ice-$roomId-$listenForRole')
      ..onPostgresChanges(
        event   : PostgresChangeEvent.insert,
        schema  : 'public',
        table   : 'ice_candidates',
        filter  : PostgresChangeFilter(
          type  : PostgresChangeFilterType.eq,
          column: 'room_id',
          value : roomId,
        ),
        callback: (payload) async {
          if (_disposed) return;
          final row = payload.newRecord;
          if ((row['role'] as String?) != listenForRole) return;
          await _addCandidate(row);
        },
      )
      ..subscribe();
  }

  Future<void> _addCandidate(Map<String, dynamic> row) async {
    if (!_remoteDescSet) {
      for (int i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_remoteDescSet || _disposed) break;
      }
      if (!_remoteDescSet) return;
    }
    try {
      await peerConnection!.addCandidate(RTCIceCandidate(
        row['candidate']        as String,
        row['sdp_mid']          as String?,
        row['sdp_m_line_index'] as int?,
      ));
    } catch (e) {
      debugPrint('[ICE] addCandidate error: $e');
    }
  }

  // ── Build peer connection ──────────────────────────────────────────────
  Future<void> _buildPeerConnection(String roomId) async {
    peerConnection = await createPeerConnection(_configuration);

    // Add local tracks
    localStream?.getTracks().forEach((track) {
      peerConnection!.addTrack(track, localStream!);
    });

    // Remote stream
    peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        onAddRemoteStream?.call(remoteStream!);
      }
    };
    // ignore: deprecated_member_use
    peerConnection!.onAddStream = (MediaStream stream) {
      onAddRemoteStream?.call(stream);
    };

    peerConnection!.onIceConnectionState = (RTCIceConnectionState s) {
      debugPrint('[ICE] $s');
      onIceConnectionState?.call(s);
    };
    peerConnection!.onConnectionState = (RTCPeerConnectionState s) {
      debugPrint('[Peer] $s');
      onPeerConnectionState?.call(s);
    };

    // ── Data channels ──────────────────────────────────────────────────
    if (_isCaller) {
      // Signs channel
      final dc = await peerConnection!.createDataChannel(
          'signs', RTCDataChannelInit()..ordered = true);
      dataChannel = dc;
      dc.onMessage = (msg) => onRemoteSign?.call(msg.text);

      // Video channel — unordered, no retransmits: stale frames dropped
      final vdc = await peerConnection!.createDataChannel(
        'video',
        RTCDataChannelInit()
          ..ordered        = false
          ..maxRetransmits = 0,
      );
      videoChannel = vdc;
      // Caller does not receive video frames via DataChannel
      // (remote sends them back if remote also has signing ON)
      vdc.onMessage = (msg) {
        if (msg.isBinary) onRemoteVideoFrame?.call(msg.binary);
      };

    } else {
      peerConnection!.onDataChannel = (RTCDataChannel dc) {
        if (dc.label == 'signs') {
          dataChannel = dc;
          dc.onMessage = (msg) => onRemoteSign?.call(msg.text);
        } else if (dc.label == 'video') {
          videoChannel = dc;
          dc.onMessage = (msg) {
            if (msg.isBinary) onRemoteVideoFrame?.call(msg.binary);
          };
        }
      };
    }

    // ICE candidate sender
    final role = _isCaller ? 'caller' : 'callee';
    peerConnection!.onIceCandidate = (RTCIceCandidate? c) {
      if (c == null || (c.candidate ?? '').isEmpty || _disposed) return;
      _supabase.from('ice_candidates').insert({
        'room_id'         : roomId,
        'role'            : role,
        'candidate'       : c.candidate,
        'sdp_mid'         : c.sdpMid,
        'sdp_m_line_index': c.sdpMLineIndex,
      }).catchError((e) => debugPrint('[ICE] Insert error: $e'));
    };
  }

  // ── Replace video track when switching modes ───────────────────────────
  // Called when user toggles signing ON→OFF to restore WebRTC video
  Future<void> replaceVideoTrack(MediaStreamTrack newTrack) async {
    final senders = await peerConnection?.getSenders();

    final sender = senders
        ?.where((s) => s.track?.kind == 'video')
        .firstOrNull;

    if (sender != null) {
      await sender.replaceTrack(newTrack);
      debugPrint('[Signaling] Video track replaced');
    }
  }

  void _pollForAnswer(String roomId) {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_remoteDescSet || _disposed) { timer.cancel(); return; }
      final rows = await _supabase
          .from('rooms').select().eq('id', roomId).limit(1);
      if (rows.isEmpty) { timer.cancel(); return; }
      final row        = rows.first as Map<String, dynamic>;
      final answerSdp  = row['answer_sdp']  as String?;
      final answerType = row['answer_type'] as String?;
      if (answerSdp != null && answerType != null && !_remoteDescSet) {
        _remoteDescSet = true;
        timer.cancel();
        debugPrint('[Signaling] Answer found via polling');
        await peerConnection!.setRemoteDescription(
            RTCSessionDescription(answerSdp, answerType));
      }
    });
  }

  Future<void> hangUp(String roomId, {required bool isCaller}) async {
    if (_disposed) return;
    _disposed = true;

    await _roomsChannel?.unsubscribe();
    await _iceChannel?.unsubscribe();

    dataChannel?.close();
    videoChannel?.close();
    localStream?.getTracks().forEach((t) => t.stop());
    remoteStream?.getTracks().forEach((t) => t.stop());
    await peerConnection?.close();

    if (isCaller) {
      try {
        await _supabase.from('rooms').delete().eq('id', roomId);
      } catch (e) {
        debugPrint('[Signaling] Room delete error: $e');
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VIDEO CALL SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final bool   isCaller;

  const VideoCallScreen({
    super.key,
    required this.roomId,
    required this.isCaller,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {

  final Signaling        _signaling     = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer= RTCVideoRenderer();
  final CameraXBridge    _bridge        = CameraXBridge();

  bool   _remoteConnected = false;
  bool   _callEnded       = false;
  bool   _micMuted        = false;
  bool   _signingEnabled  = false;
  String _statusText      = 'Connecting…';

  // Subtitles
  String _mySubtitle     = '';
  String _remoteSubtitle = '';
  Timer? _mySubtitleTimer;
  Timer? _remoteSubtitleTimer;

  // Option 4 video frames
  // _localJpeg  — shown as local background when signing is ON
  // _remoteJpeg — shown in remote PiP when remote is signing
  Uint8List? _localJpeg;
  Uint8List? _remoteJpeg;
  bool _hasRemoteJpeg = false;

  Timer? _iceTimeoutTimer;

  static const double _kCallConfidence = 0.65;
  static const int    _kSignCooldownMs = 1200;
  DateTime _lastSignSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  String   _lastSignSent   = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initRenderers());
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _initCall();
  }

  @override
  void dispose() {
    _iceTimeoutTimer?.cancel();
    _mySubtitleTimer?.cancel();
    _remoteSubtitleTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _bridge.signNotifier.removeListener(_onSignDetected);
    _bridge.dispose();
    _signaling.hangUp(widget.roomId, isCaller: widget.isCaller);
    super.dispose();
  }

  // ── Sign detected locally → send subtitle to remote ───────────────────
  void _onSignDetected() {
    if (!_signingEnabled) return;
    final sign       = _bridge.signNotifier.value;
    final confidence = _bridge.confidenceNotifier.value;
    if (sign.isEmpty || confidence < _kCallConfidence) return;

    final now = DateTime.now();
    if (sign == _lastSignSent &&
        now.difference(_lastSignSentAt).inMilliseconds < _kSignCooldownMs) return;
    if (now.difference(_lastSignSentAt).inMilliseconds < _kSignCooldownMs ~/ 2) return;

    _lastSignSent   = sign;
    _lastSignSentAt = now;

    _showMySubtitle(sign);
    _signaling.dataChannel?.send(RTCDataChannelMessage(sign));
  }

  // ── Init ──────────────────────────────────────────────────────────────
  Future<void> _initCall() async {

    // Remote WebRTC stream arrived
    _signaling.onAddRemoteStream = (MediaStream stream) {
      if (!mounted) return;
      _remoteRenderer.srcObject = stream;
      setState(() {
        _remoteConnected = true;
        _statusText      = 'Connected';
      });
    };

    _signaling.onIceConnectionState = (RTCIceConnectionState s) {
      if (!mounted) return;
      if (s == RTCIceConnectionState.RTCIceConnectionStateChecking  ||
          s == RTCIceConnectionState.RTCIceConnectionStateConnected  ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _iceTimeoutTimer?.cancel();
      }
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        setState(() => _statusText = 'Connected');
      }
      if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        setState(() => _statusText = 'Connection failed');
      }
    };

    _signaling.onPeerConnectionState = (RTCPeerConnectionState s) {
      if (!mounted) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _endCall(remote: true);
      }
    };

    _signaling.onCallEnded = () { if (mounted) _endCall(remote: true); };

    // Remote sign subtitle received
    _signaling.onRemoteSign = (String sign) {
      if (mounted) _showRemoteSubtitle(sign);
    };

    // Remote video JPEG received (Option 4)
    // Shows remote peer's camera as JPEG in PiP when they have signing ON
    _signaling.onRemoteVideoFrame = (Uint8List bytes) {
      if (mounted) setState(() {
        _remoteJpeg    = bytes;
        _hasRemoteJpeg = true;
      });
    };

    // Local JPEG video frame from CameraX (Option 4)
    // Shown as local background and sent to remote via video DataChannel
    _bridge.onVideoFrame = (Uint8List bytes) {
      // Update local background
      if (mounted) setState(() => _localJpeg = bytes);

      // Send to remote peer via DataChannel
      // Check channel is open before sending
      _signaling.videoChannel?.send(
        RTCDataChannelMessage.fromBinary(bytes),
      );
    };

    // Wire sign detection listener
    _bridge.signNotifier.addListener(_onSignDetected);

    // Open audio + video (signing is OFF initially, WebRTC owns camera)
    try {
      await _signaling.openUserMedia(_localRenderer, audioOnly: false);
    } catch (e) {
      if (mounted) setState(() => _statusText = 'Camera access failed: $e');
      return;
    }
    if (mounted) setState(() {});

    _iceTimeoutTimer = Timer(const Duration(seconds: _kIceTimeoutSeconds), () {
      if (_remoteConnected || _callEnded || !mounted) return;
      setState(() => _statusText = 'Connection timed out');
    });

    try {
      if (widget.isCaller) {
        if (mounted) setState(() => _statusText = 'Waiting for other person…');
        await _signaling.createRoom(widget.roomId, _remoteRenderer);
      } else {
        if (mounted) setState(() => _statusText = 'Joining room…');
        await _signaling.joinRoom(widget.roomId, _remoteRenderer);
        if (mounted) setState(() => _statusText = 'Waiting for connection…');
      }
    } catch (e) {
      if (mounted) setState(() => _statusText = 'Error: $e');
    }
  }

  // ── Toggle signing ────────────────────────────────────────────────────
  void _toggleSigning() async {
    if (_signingEnabled) {
      // ── SIGNING OFF ─────────────────────────────────────────────────
      // 1. Stop CameraX so it releases the camera
      await _bridge.stop();

      // 2. Short delay so hardware releases
      await Future.delayed(const Duration(milliseconds: 300));

      // 3. Re-open WebRTC camera
      try {
        await _signaling.openUserMedia(_localRenderer, audioOnly: false);

        // 4. Replace video track in the peer connection so remote sees video
        final newVideoTrack =
            _signaling.localStream?.getVideoTracks().firstOrNull;
        if (newVideoTrack != null) {
          await _signaling.replaceVideoTrack(newVideoTrack);
        }
      } catch (e) {
        debugPrint('[VideoCall] restore camera error: $e');
      }

      if (mounted) setState(() {
        _signingEnabled = false;
        _localJpeg      = null;
        _mySubtitle     = '';
      });

    } else {
      // ── SIGNING ON ──────────────────────────────────────────────────
      // 1. Stop WebRTC video track so CameraX can open the camera
      final videoTrack =
          _signaling.localStream?.getVideoTracks().firstOrNull;
      videoTrack?.stop();

      // 2. Switch WebRTC to audio only
      try {
        await _signaling.openUserMedia(_localRenderer, audioOnly: true);
      } catch (e) {
        debugPrint('[VideoCall] audio-only switch error: $e');
      }

      // 3. Short delay so hardware releases
      await Future.delayed(const Duration(milliseconds: 300));

      // 4. Start CameraX pipeline
      final started = await _bridge.start();
      if (!started && mounted) {
        // Failed — restore WebRTC video
        await _signaling.openUserMedia(_localRenderer, audioOnly: false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign detection not available')),
        );
        return;
      }

      if (mounted) setState(() => _signingEnabled = true);
    }
  }

  // ── Call control ──────────────────────────────────────────────────────
  Future<void> _endCall({bool remote = false}) async {
    if (_callEnded) return;
    _callEnded = true;
    _iceTimeoutTimer?.cancel();
    if (_signingEnabled) await _bridge.stop();
    await _signaling.hangUp(widget.roomId, isCaller: widget.isCaller);
    if (mounted) Navigator.pop(context);
  }

  void _toggleMic() {
    final track = _signaling.localStream?.getAudioTracks().firstOrNull;
    if (track == null) return;
    track.enabled = !track.enabled;
    if (mounted) setState(() => _micMuted = !track.enabled);
  }

  // ── Subtitles ─────────────────────────────────────────────────────────
  void _showMySubtitle(String sign) {
    _mySubtitleTimer?.cancel();
    if (mounted) setState(() => _mySubtitle = sign);
    _mySubtitleTimer = Timer(const Duration(milliseconds: _kSubtitleFadeMs),
        () { if (mounted) setState(() => _mySubtitle = ''); });
  }

  void _showRemoteSubtitle(String sign) {
    _remoteSubtitleTimer?.cancel();
    if (mounted) setState(() => _remoteSubtitle = sign);
    _remoteSubtitleTimer = Timer(const Duration(milliseconds: _kSubtitleFadeMs),
        () { if (mounted) setState(() => _remoteSubtitle = ''); });
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [

            // ── Local video (Full Screen Background) ──────────────────────
            // When signing OFF → RTCVideoView (mirrored)
            // When signing ON  → CameraX JPEG via Image.memory
            if (!_signingEnabled)
              Positioned.fill(
                child: RTCVideoView(
                  _localRenderer,
                  mirror   : true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),

            if (_signingEnabled && _localJpeg != null)
              Positioned.fill(
                child: Image.memory(
                  _localJpeg!,
                  gaplessPlayback: true,
                  fit            : BoxFit.cover,
                ),
              ),

            if (_signingEnabled && _localJpeg == null)
              const Positioned.fill(
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3, 
                    color: Colors.deepOrange
                  ),
                ),
              ),

            // Connecting overlay
            if (!_remoteConnected)
              _ConnectingView(statusText: _statusText),

            // ── Remote subtitle ───────────────────────────────────────────
            if (_remoteSubtitle.isNotEmpty)
              Positioned(
                bottom: 120, left: 24, right: 24,
                child: _SubtitleBanner(text: _remoteSubtitle),
              ),

            // ── My subtitle ───────────────────────────────────────────────
            if (_mySubtitle.isNotEmpty)
              Positioned(
                bottom: 120, left: 24, right: 24,
                child: _SubtitleBanner(text: _mySubtitle),
              ),

            // ── Remote video PiP ──────────────────────────────────────────
            // When remote signing OFF → RTCVideoView (not mirrored)
            // When remote signing ON  → JPEG via Image.memory
            if (_remoteConnected)
              Positioned(
                top: 70, right: 16,
                child: (_hasRemoteJpeg && _remoteJpeg != null)
                    ? _RemoteJpegPipTile(remoteJpeg: _remoteJpeg)
                    : _RemoteVideoPipTile(renderer: _remoteRenderer),
              ),

            // ── Top bar ───────────────────────────────────────────────────
            Positioned(
              top: 16, left: 16, right: 16,
              child: _TopBar(
                roomId         : widget.roomId,
                remoteConnected: _remoteConnected,
                signingEnabled : _signingEnabled,
                onToggleSigning: _toggleSigning,
              ),
            ),

            // ── Bottom controls ───────────────────────────────────────────
            Positioned(
              bottom: 24, left: 0, right: 0,
              child: _BottomControls(
                micMuted       : _micMuted,
                signingEnabled : _signingEnabled,
                onMic          : _toggleMic,
                onEndCall      : () => _endCall(),
                onToggleSigning: _toggleSigning,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REMOTE PiP — Remote JPEG tile (remote signing ON)
// ─────────────────────────────────────────────────────────────────────────────
class _RemoteJpegPipTile extends StatelessWidget {
  final Uint8List? remoteJpeg;
  const _RemoteJpegPipTile({required this.remoteJpeg});

  @override
  Widget build(BuildContext context) => Container(
    width: 110, height: 150,
    decoration: BoxDecoration(
      color        : cardColor,
      borderRadius : BorderRadius.circular(16),
      border       : Border.all(color: Colors.deepOrange.shade500, width: 2),
      boxShadow    : const [
        BoxShadow(color: borderColor, blurRadius: 0, offset: Offset(0, 4)),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: remoteJpeg != null
          ? Image.memory(
              remoteJpeg!,
              gaplessPlayback: true,
              fit            : BoxFit.cover,
            )
          : const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color      : Colors.deepOrange,
              ),
            ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// REMOTE PiP — WebRTC tile (remote signing OFF)
// ─────────────────────────────────────────────────────────────────────────────
class _RemoteVideoPipTile extends StatelessWidget {
  final RTCVideoRenderer renderer;
  const _RemoteVideoPipTile({required this.renderer});

  @override
  Widget build(BuildContext context) => Container(
    width: 110, height: 150,
    decoration: BoxDecoration(
      color       : cardColor,
      borderRadius: BorderRadius.circular(16),
      border      : Border.all(color: borderColor, width: 2),
      boxShadow   : const [
        BoxShadow(color: borderColor, blurRadius: 0, offset: Offset(0, 4)),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: RTCVideoView(
        renderer,
        mirror   : false, // Remote view should not be mirrored
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CONNECTING VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _ConnectingView extends StatelessWidget {
  final String statusText;
  const _ConnectingView({required this.statusText});

  @override
  Widget build(BuildContext context) => Container(
    color: bgColor,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color    : cardColor,
            shape    : BoxShape.circle,
            border   : Border.all(color: borderColor, width: 2),
            boxShadow: const [
              BoxShadow(color: borderColor, blurRadius: 0, offset: Offset(0, 6)),
            ],
          ),
          child: Icon(Icons.videocam_rounded,
              color: Colors.white.withOpacity(0.5), size: 48),
        ),
        const SizedBox(height: 32),
        Text(statusText,
            style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        const SizedBox(
          width: 28, height: 28,
          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SUBTITLE BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _SubtitleBanner extends StatelessWidget {
  final String text;
  const _SubtitleBanner({required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color       :  cardColor,
        borderRadius: BorderRadius.circular(5),
        border      : Border.all(
          color:borderColor, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(text,
              style: const TextStyle(
                color       : Colors.white,
                fontSize    : 22,
                fontWeight  : FontWeight.w300,
                letterSpacing: 1.0,
              )),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String       roomId;
  final bool         remoteConnected;
  final bool         signingEnabled;
  final VoidCallback onToggleSigning;

  const _TopBar({
    required this.roomId,
    required this.remoteConnected,
    required this.signingEnabled,
    required this.onToggleSigning,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      GestureDetector(
        onTap: () => Navigator.maybePop(context),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color    : cardColor,
            shape    : BoxShape.circle,
            border   : Border.all(color: borderColor, width: 2),
            boxShadow: const [
              BoxShadow(color: borderColor, blurRadius: 0, offset: Offset(0, 4)),
            ],
          ),
          child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
        ),
      ),
      const SizedBox(width: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color    : cardColor,
          borderRadius: BorderRadius.circular(16),
          border   : Border.all(color: borderColor, width: 2),
          boxShadow: const [
            BoxShadow(color: borderColor, blurRadius: 0, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: remoteConnected
                    ? Colors.green.shade400
                    : Colors.amber.shade400,
              ),
            ),
            const SizedBox(width: 8),
            Text('ROOM $roomId',
                style: const TextStyle(
                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900,
                  letterSpacing: 0.5)),
          ],
        ),
      ),
      const SizedBox(width: 15),
      GestureDetector(
        onTap: onToggleSigning,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: signingEnabled
                ? Colors.deepOrange.shade500
                : cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: signingEnabled ? Colors.transparent : borderColor,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: signingEnabled
                    ? Colors.deepOrange.shade800
                    : borderColor,
                blurRadius: 0, offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sign_language_rounded, size: 16,
                  color: signingEnabled ? Colors.white : Colors.white54),
              const SizedBox(width: 6),
              Text(
                signingEnabled ? 'SIGNING ON' : 'SIGNING OFF',
                style: TextStyle(
                  fontSize    : 11,
                  fontWeight  : FontWeight.w900,
                  color       : signingEnabled ? Colors.white : Colors.white54,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM CONTROLS
// ─────────────────────────────────────────────────────────────────────────────
class _BottomControls extends StatelessWidget {
  final bool         micMuted;
  final bool         signingEnabled;
  final VoidCallback onMic;
  final VoidCallback onEndCall;
  final VoidCallback onToggleSigning;

  const _BottomControls({
    required this.micMuted,
    required this.signingEnabled,
    required this.onMic,
    required this.onEndCall,
    required this.onToggleSigning,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _ControlButton(
        icon       : micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
        active     : micMuted,
        faceColor  : Colors.white,
        shadowColor: Colors.grey.shade400,
        iconColor  : bgColor,
        activeFace : Colors.red.shade500,
        activeShadow: Colors.red.shade800,
        activeIcon : Colors.white,
        onTap      : onMic,
      ),
      _ControlButton(
        icon       : Icons.call_end_rounded,
        active     : true,
        faceColor  : Colors.white,
        shadowColor: Colors.grey.shade400,
        iconColor  : bgColor,
        activeFace : Colors.red.shade500,
        activeShadow: Colors.red.shade800,
        activeIcon : Colors.white,
        large      : true,
        onTap      : onEndCall,
      ),
      _ControlButton(
        icon       : Icons.sign_language_rounded,
        active     : signingEnabled,
        faceColor  : Colors.white,
        shadowColor: Colors.grey.shade400,
        iconColor  : bgColor,
        activeFace : Colors.deepOrange.shade500,
        activeShadow: Colors.deepOrange.shade800,
        activeIcon : Colors.white,
        onTap      : onToggleSigning,
      ),
    ],
  );
}

class _ControlButton extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;
  final bool         active;
  final bool         large;
  final Color        faceColor;
  final Color        shadowColor;
  final Color        iconColor;
  final Color        activeFace;
  final Color        activeShadow;
  final Color        activeIcon;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.active      = false,
    this.large       = false,
    required this.faceColor,
    required this.shadowColor,
    required this.iconColor,
    required this.activeFace,
    required this.activeShadow,
    required this.activeIcon,
  });

  @override
  Widget build(BuildContext context) {
    final size     = large ? 72.0 : 56.0;
    final iconSize = large ? 32.0 : 24.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape    : BoxShape.circle,
          color    : active ? activeFace : faceColor,
          boxShadow: [
            BoxShadow(
              color: active ? activeShadow : shadowColor,
              blurRadius: 0, offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Icon(icon,
              color: active ? activeIcon : iconColor, size: iconSize),
        ),
      ),
    );
  }
}