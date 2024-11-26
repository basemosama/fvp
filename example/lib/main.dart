// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs

/// An example of using the plugin, controlling lifecycle and playback of the
/// video.

import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart';
import 'package:logging/logging.dart';

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.loggerName}.${record.level.name}: ${record.message}');
  });

  runApp(
    MaterialApp(
      home: _App(),
    ),
  );
}

class _App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        key: const ValueKey<String>('home_page'),
        appBar: AppBar(
          title: const Text('Video player example'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(
                icon: Icon(Icons.cloud),
                text: 'Remote',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _BumbleBeeRemoteVideo(),
          ],
        ),
      ),
    );
  }
}

class _BumbleBeeRemoteVideo extends StatefulWidget {
  @override
  _BumbleBeeRemoteVideoState createState() => _BumbleBeeRemoteVideoState();
}

class _BumbleBeeRemoteVideoState extends State<_BumbleBeeRemoteVideo> {
  late MdkVideoPlayerController _controller;

  @override
  void initState() {
    super.initState();

    //https://storage.googleapis.com/exoplayer-test-media-1/mp4/dizzy-with-tx3g.mp4
    //http://sample.vodobox.com/planete_interdite/planete_interdite_alternate.m3u8
    // 'https://mirror.selfnet.de/CCC/congress/2019/h264-hd/36c3-11235-eng-deu-fra-36C3_Infrastructure_Review_hd.mp4'
    _controller = MdkVideoPlayerController.networkUrl(
      // 'assets/5.ts',
      Uri.parse(
          'https://storage.googleapis.com/exoplayer-test-media-1/mp4/dizzy-with-tx3g.mp4'
          // 'http://sample.vodobox.com/planete_interdite/planete_interdite_alternate.m3u8',
          ),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    _controller.setLooping(true);
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          Container(padding: const EdgeInsets.only(top: 20.0)),
          const Text('With remote mp4'),
          Container(
            padding: const EdgeInsets.all(20),
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  MdkVideoPlayer(_controller),
                  // ClosedCaption(text: subtitle),
                  _ControlsOverlay(controller: _controller),
                  VideoProgressIndicator(_controller, allowScrubbing: true),
                ],
              ),
            ),
          ),
          IconButton(
              onPressed: () async {
                await _controller.dispose();
                _controller = MdkVideoPlayerController.networkUrl(
                  Uri.parse(
                      'https://storage.googleapis.com/exoplayer-test-media-1/mp4/dizzy-with-tx3g.mp4'),
                  videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
                );

                _controller.addListener(() {
                  // print('video listener :${_controller.value}');
                  // final cues = _controller.value.subtitle;
                  // subtitle = (cues.isEmpty ? '' : cues.join("/n"));
                  // setState(() {});
                });

                _controller.setLooping(true);
                _controller.initialize();
                setState(() {});
              },
              icon: Icon(Icons.next_plan_sharp)),
          _GetTrackSelectionButton(controller: _controller),
        ],
      ),
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({required this.controller});

  static const List<Duration> _exampleCaptionOffsets = <Duration>[
    Duration(seconds: -10),
    Duration(seconds: -3),
    Duration(seconds: -1, milliseconds: -500),
    Duration(milliseconds: -250),
    Duration.zero,
    Duration(milliseconds: 250),
    Duration(seconds: 1, milliseconds: 500),
    Duration(seconds: 3),
    Duration(seconds: 10),
  ];
  static const List<double> _examplePlaybackRates = <double>[
    0.25,
    0.5,
    1.0,
    1.5,
    2.0,
    3.0,
    5.0,
    10.0,
  ];

  final MdkVideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        ListenableBuilder(
          listenable: controller,
          builder: (cxt, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 50),
            reverseDuration: const Duration(milliseconds: 200),
            child: controller.value.isPlaying
                ? const SizedBox.shrink()
                : Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 100.0,
                        semanticLabel: 'Play',
                      ),
                    ),
                  ),
          ),
        ),
        GestureDetector(
          onTap: () {
            controller.value.isPlaying ? controller.pause() : controller.play();
          },
        ),
        Align(
          alignment: Alignment.topLeft,
          child: PopupMenuButton<Duration>(
            initialValue: controller.value.captionOffset,
            tooltip: 'Caption Offset',
            onSelected: (Duration delay) {
              controller.setCaptionOffset(delay);
            },
            itemBuilder: (BuildContext context) {
              return <PopupMenuItem<Duration>>[
                for (final Duration offsetDuration in _exampleCaptionOffsets)
                  PopupMenuItem<Duration>(
                    value: offsetDuration,
                    child: Text('${offsetDuration.inMilliseconds}ms'),
                  )
              ];
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                // Using less vertical padding as the text is also longer
                // horizontally, so it feels like it would need more spacing
                // horizontally (matching the aspect ratio of the video).
                vertical: 12,
                horizontal: 16,
              ),
              child: Text('${controller.value.captionOffset.inMilliseconds}ms'),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: PopupMenuButton<double>(
            initialValue: controller.value.playbackSpeed,
            tooltip: 'Playback speed',
            onSelected: (double speed) {
              controller.setPlaybackSpeed(speed);
            },
            itemBuilder: (BuildContext context) {
              return <PopupMenuItem<double>>[
                for (final double speed in _examplePlaybackRates)
                  PopupMenuItem<double>(
                    value: speed,
                    child: Text('${speed}x'),
                  )
              ];
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                // Using less vertical padding as the text is also longer
                // horizontally, so it feels like it would need more spacing
                // horizontally (matching the aspect ratio of the video).
                vertical: 12,
                horizontal: 16,
              ),
              child: Text('${controller.value.playbackSpeed}x'),
            ),
          ),
        ),
      ],
    );
  }
}

class _GetTrackSelectionButton extends StatelessWidget {
  _GetTrackSelectionButton({required this.controller});

  final MdkVideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 20.0),
      child: MaterialButton(
          child: Text('Get Track Selection'),
          onPressed: () async {
            final videoTracks = await controller.getVideoTracks();
            final audioTracks = await controller.getAudioTracks();
            final subtitleTracks = await controller.getSubtitleTracks();

            final selectedVideoTrack = controller.getActiveVideoTrack();
            final selectedAudioTrack = controller.getActiveAudioTrack();
            final selectedSubtitleTrack = controller.getActiveSubtitleTrack();

            print('tracks :$subtitleTracks active :$selectedSubtitleTrack');
            // ignore: use_build_context_synchronously
            showDialog<MdkTrackSelection>(
              context: context,
              builder: (_) => _TrackSelectionDialog(
                videoTrackSelections: videoTracks,
                audioTrackSelections: audioTracks,
                textTrackSelections: subtitleTracks,
                selectedVideoTrack: selectedVideoTrack,
                selectedAudioTrack: selectedAudioTrack,
                selectedSubtitleTrack: selectedSubtitleTrack,
                controller: controller,
              ),
            );
          }),
    );
  }
}

class _TrackSelectionDialog extends StatelessWidget {
  const _TrackSelectionDialog({
    required this.videoTrackSelections,
    required this.audioTrackSelections,
    required this.textTrackSelections,
    required this.controller,
    required this.selectedVideoTrack,
    required this.selectedAudioTrack,
    required this.selectedSubtitleTrack,
  });
  final MdkVideoPlayerController controller;
  final List<MdkTrackSelection> videoTrackSelections;
  final List<MdkTrackSelection> audioTrackSelections;
  final List<MdkTrackSelection> textTrackSelections;
  final int selectedVideoTrack;
  final int selectedAudioTrack;
  final int selectedSubtitleTrack;

  int _tabBarLength() {
    int length = 0;
    if (videoTrackSelections.isNotEmpty) length += 1;
    if (audioTrackSelections.isNotEmpty) length += 1;
    if (textTrackSelections.isNotEmpty) length += 1;
    return length;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      initialIndex: 0,
      length: _tabBarLength(),
      child: AlertDialog(
        titlePadding: EdgeInsets.all(0),
        contentPadding: EdgeInsets.all(0),
        title: TabBar(
          labelColor: Colors.black,
          tabs: [
            if (videoTrackSelections.isNotEmpty) Tab(text: 'Video'),
            if (audioTrackSelections.isNotEmpty) Tab(text: 'Audio'),
            if (textTrackSelections.isNotEmpty) Tab(text: 'Text'),
          ],
        ),
        content: Container(
          height: 200,
          width: 200,
          child: TabBarView(
            children: [
              if (videoTrackSelections.isNotEmpty)
                SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: videoTrackSelections
                        .map((track) => RadioListTile<MdkTrackSelection>(
                              title: Text(track.trackName),
                              value: track,
                              groupValue: videoTrackSelections
                                  .where((track) =>
                                      track.trackId == selectedVideoTrack)
                                  .firstOrNull,
                              selected: track.trackId == selectedVideoTrack,
                              onChanged: (MdkTrackSelection? track) {
                                if (track == null) {
                                  return;
                                }
                                controller.setVideoTrack(track.trackId);
                              },
                            ))
                        .toList(),
                  ),
                ),
              if (audioTrackSelections.isNotEmpty)
                SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: audioTrackSelections
                        .map((track) => RadioListTile<MdkTrackSelection>(
                              title: Text(track.trackName),
                              value: track,
                              groupValue: audioTrackSelections
                                  .where((track) =>
                                      track.trackId == selectedAudioTrack)
                                  .firstOrNull,
                              selected: track.trackId == selectedAudioTrack,
                              onChanged: (MdkTrackSelection? track) {
                                if (track == null) {
                                  return;
                                }
                                if (!track.isSelected) {
                                  controller.setAudioTrack(track.trackId);
                                }
                              },
                            ))
                        .toList(),
                  ),
                ),
              if (textTrackSelections.isNotEmpty)
                SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: textTrackSelections
                        .map((track) => RadioListTile<MdkTrackSelection>(
                              title: Text(track.trackName),
                              value: track,
                              groupValue: textTrackSelections
                                  .where((track) =>
                                      track.trackId == selectedSubtitleTrack)
                                  .firstOrNull,
                              selected: track.trackId == selectedSubtitleTrack,
                              onChanged: (MdkTrackSelection? track) {
                                if (track == null) {
                                  return;
                                }
                                if (!track.isSelected) {
                                  controller.setSubtitleTrack(track.trackId);
                                }
                              },
                            ))
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
