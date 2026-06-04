import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class SignYoutubePlayer extends StatefulWidget {
  const SignYoutubePlayer({super.key, required this.videoId});

  final String videoId;

  @override
  State<SignYoutubePlayer> createState() => _SignYoutubePlayerState();
}

class _SignYoutubePlayerState extends State<SignYoutubePlayer> {

  late final YoutubePlayerController _controller = YoutubePlayerController(
    initialVideoId: widget.videoId,
    flags: const YoutubePlayerFlags(
      autoPlay: false,
      mute: false,
      loop: false,
      showLiveFullscreenButton: false,
      useHybridComposition: false
    ),
  );


  @override
  Widget build(BuildContext context) {
    return YoutubePlayer(controller: _controller,
        showVideoProgressIndicator: true,
);
  }
}