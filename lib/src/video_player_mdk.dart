// Copyright 2022-2024 Wang Bin. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'; //
import 'package:fvp/mdk.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../mdk.dart' as mdk;
import 'extensions.dart';

final _log = Logger('fvp');

class MdkPlayer extends mdk.Player {
  final streamCtl = StreamController<VideoEvent>();

  @override
  void dispose() {
    onMediaStatus(null);
    onEvent(null);
    onStateChanged(null);
    streamCtl.close();
    super.dispose();
  }

  MdkPlayer() : super() {
    onMediaStatus((oldValue, newValue) {
      _log.fine(
          '$hashCode player$nativeHandle onMediaStatus: $oldValue => $newValue');
      if (!oldValue.test(mdk.MediaStatus.loaded) &&
          newValue.test(mdk.MediaStatus.loaded)) {
        final info = mediaInfo;
        var size = const Size(0, 0);
        if (info.video != null) {
          final vc = info.video![0].codec;
          size = Size(vc.width.toDouble(),
              (vc.height.toDouble() / vc.par).roundToDouble());
          if (info.video![0].rotation % 180 == 90) {
            size = Size(size.height, size.width);
          }
        }
        streamCtl.add(VideoEvent(
            eventType: VideoEventType.initialized,
            duration: Duration(
                milliseconds: info.duration == 0
                    ? double.maxFinite.toInt()
                    : info.duration)
            // FIXME: live stream info.duraiton == 0 and result a seekTo(0) in play()
            ,
            size: size));
      } else if (!oldValue.test(mdk.MediaStatus.buffering) &&
          newValue.test(mdk.MediaStatus.buffering)) {
        streamCtl.add(VideoEvent(eventType: VideoEventType.bufferingStart));
      } else if (!oldValue.test(mdk.MediaStatus.buffered) &&
          newValue.test(mdk.MediaStatus.buffered)) {
        streamCtl.add(VideoEvent(eventType: VideoEventType.bufferingEnd));
      }
      return true;
    });

    onEvent((ev) {
      _log.fine(
          '$hashCode player$nativeHandle onEvent: ${ev.category} ${ev.error}');
      if (ev.category == "reader.buffering") {
        final pos = position;
        final bufLen = buffered();
        streamCtl.add(
            VideoEvent(eventType: VideoEventType.bufferingUpdate, buffered: [
          DurationRange(
              Duration(microseconds: pos), Duration(milliseconds: pos + bufLen))
        ]));
      }
    });

    onStateChanged((oldValue, newValue) {
      _log.fine(
          '$hashCode player$nativeHandle onPlaybackStateChanged: $oldValue => $newValue');
      if (newValue == mdk.PlaybackState.stopped) {
        // FIXME: keep_open no stopped
        streamCtl.add(VideoEvent(eventType: VideoEventType.completed));
        return;
      }
      streamCtl.add(VideoEvent(
          eventType: VideoEventType.isPlayingStateUpdate,
          isPlaying: newValue == mdk.PlaybackState.playing));
    });
  }
}

class _PlaceholderImplementation extends MdkVideoPlayerPlatform {}

class MdkVideoPlayerPlatform extends PlatformInterface {
  /// Constructs a VideoPlayerPlatform.
  MdkVideoPlayerPlatform() : super(token: _token);

  static final Object _token = Object();

  static MdkVideoPlayerPlatform _instance = _PlaceholderImplementation();

  /// The instance of [MdkVideoPlayerPlatform] to use.
  ///
  /// Defaults to a placeholder that does not override any methods, and thus
  /// throws `UnimplementedError` in most cases.
  static MdkVideoPlayerPlatform get instance => _instance;

  /// Platform-specific plugins should override this with their own
  /// platform-specific class that extends [VideoPlayerPlatform] when they
  /// register themselves.
  static set instance(MdkVideoPlayerPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  static final _players = <int, MdkPlayer>{};
  Map<String, Object>? _globalOpts;
  Map<String, String>? _playerOpts;
  int? _maxWidth;
  int? _maxHeight;
  bool? _fitMaxSize;
  bool? _tunnel;
  static String? _subtitleFontFile;
  int _lowLatency = 0;
  int _seekFlags = mdk.SeekFlag.fromStart | mdk.SeekFlag.inCache;
  List<String>? _decoders;
  final _mdkLog = Logger('mdk');

/*
  Registers this class as the default instance of [VideoPlayerPlatform].

  [options] can be
  "video.decoders": a list of decoder names. supported decoders: https://github.com/wang-bin/mdk-sdk/wiki/Decoders
  "maxWidth", "maxHeight": texture max size. if not set, video frame size is used. a small value can reduce memory cost, but may result in lower image quality.
 */
  void registerVideoPlayerPlatformsWith({dynamic options}) {
    // prefer hardware decoders
    _log.fine('registerVideoPlayerPlatformsWith: $options');
    if (options is Map<String, dynamic>) {
      final platforms = options['platforms'];
      if (platforms is List<String>) {
        if (!platforms.contains(Platform.operatingSystem)) {
          return;
        }
      }

      if ((options['fastSeek'] ?? false) as bool) {
        _seekFlags |= mdk.SeekFlag.keyFrame;
      }
      _lowLatency = (options['lowLatency'] ?? 0) as int;
      _maxWidth = options["maxWidth"];
      _maxHeight = options["maxHeight"];
      _fitMaxSize = options["fitMaxSize"];
      _tunnel = options["tunnel"];
      _playerOpts = options['player'];
      _globalOpts = options['global'];
      _decoders = options['video.decoders'];
      _subtitleFontFile = options['subtitleFontFile'];
    }

    if (_decoders == null && !PlatformEx.isAndroidEmulator()) {
      const vd = {
        'windows': ['MFT:d3d=11', "D3D11", 'CUDA', 'FFmpeg'],
        'macos': ['VT', 'FFmpeg'],
        'ios': ['VT', 'FFmpeg'],
        'linux': ['VAAPI', 'CUDA', 'VDPAU', 'FFmpeg'],
        'android': ['AMediaCodec', 'FFmpeg'],
      };
      _decoders = vd[Platform.operatingSystem];
    }
    mdk.setGlobalOption('subtitle.fonts.file',
        _assetUri(_subtitleFontFile ?? 'assets/subfont.ttf', null));
    _globalOpts?.forEach((key, value) {
      mdk.setGlobalOption(key, value);
    });

    MdkVideoPlayerPlatform.instance = MdkVideoPlayerPlatform();

    mdk.setLogHandler((level, msg) {
      if (msg.endsWith('\n')) {
        msg = msg.substring(0, msg.length - 1);
      }
      switch (level) {
        case mdk.LogLevel.error:
          _mdkLog.severe(msg);
        case mdk.LogLevel.warning:
          _mdkLog.warning(msg);
        case mdk.LogLevel.info:
          _mdkLog.info(msg);
        case mdk.LogLevel.debug:
          _mdkLog.fine(msg);
        case mdk.LogLevel.all:
          _mdkLog.finest(msg);
        default:
          return;
      }
    });

    // mdk.setGlobalOptions('plugins', 'mdk-braw');
  }

  Future<void> init() async {}

  Future<void> dispose(int textureId) async {
    _players.remove(textureId)?.dispose();
  }

  Future<int?> create(DataSource dataSource) async {
    String? uri;
    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        uri = _assetUri(dataSource.asset!, dataSource.package);
        break;
      case DataSourceType.network:
        uri = dataSource.uri;
        break;
      case DataSourceType.file:
        uri = Uri.decodeComponent(dataSource.uri!);
        break;
      case DataSourceType.contentUri:
        uri = dataSource.uri;
        break;
    }
    final player = MdkPlayer();
    _log.fine('$hashCode player${player.nativeHandle} create($uri)');

    //player.setProperty("keep_open", "1");
    player.setProperty('avformat.strict', 'experimental');
    player.setProperty('avio.protocol_whitelist',
        'file,rtmp,http,https,tls,rtp,tcp,udp,crypto,httpproxy,data,concatf,concat,subfile');
    player.setProperty('avformat.rtsp_transport', 'tcp');

    _playerOpts?.forEach((key, value) {
      player.setProperty(key, value);
    });

    if (_decoders != null) {
      player.videoDecoders = _decoders!;
    }

    if (_lowLatency > 0) {
      player.setProperty('avformat.fflags', '+nobuffer');
      player.setProperty('avformat.fpsprobesize', '0');
      if (_lowLatency > 1) {
        player.setBufferRange(min: 0, max: 1000, drop: true);
      } else {
        player.setBufferRange(min: 0);
      }
    }

    if (dataSource.httpHeaders.isNotEmpty) {
      String headers = '';
      dataSource.httpHeaders.forEach((key, value) {
        headers += '$key: $value\r\n';
      });
      player.setProperty('avio.headers', headers);
    }
    player.media = uri!;

    player.prepare(); // required!
// FIXME: pending events will be processed after texture returned, but no events before prepared
// FIXME: set tunnel too late
    final tex = await player.updateTexture(
        width: _maxWidth,
        height: _maxHeight,
        tunnel: _tunnel,
        fit: _fitMaxSize);
    if (tex < 0) {
      player.dispose();
      throw PlatformException(
        code: 'media open error',
        message: 'invalid or unsupported media',
      );
    }
    _players[tex] = player;
    return tex;
  }

  List<SubtitleStreamInfo>? getSubtitle(int textureId) {
    final player = _players[textureId];

    return player?.mediaInfo.subtitle;
  }

  Future<void> setLooping(int textureId, bool looping) async {
    final player = _players[textureId];
    if (player != null) {
      player.loop = looping ? -1 : 0;
    }
  }

  Future<void> play(int textureId) async {
    _players[textureId]?.state = mdk.PlaybackState.playing;
  }

  Future<void> pause(int textureId) async {
    _players[textureId]?.state = mdk.PlaybackState.paused;
  }

  Future<void> setVolume(int textureId, double volume) async {
    _players[textureId]?.volume = volume;
  }

  Future<void> setPlaybackSpeed(int textureId, double speed) async {
    _players[textureId]?.playbackRate = speed;
  }

  Future<void> seekTo(int textureId, Duration position) async {
    _players[textureId]?.seek(
        position: position.inMilliseconds, flags: mdk.SeekFlag(_seekFlags));
  }

  /// Gets the video [MdkTrackSelection]s. For convenience if the video file has at
  /// least one [MdkTrackSelection] for a specific type, the auto track selection will
  /// be added to this list with that type.
  Future<List<MdkTrackSelection>> getVideoTracks(
    int textureId,
  ) async {
    final player = _players[textureId];
    final videoTracks = player?.mediaInfo.video ?? [];
    final List<MdkTrackSelection> trackSelections = [];

    for (int i = 0; i < videoTracks.length; i++) {
      final e = videoTracks[i];
      int bitrate = e.codec.bitRate;
      final int width = e.codec.width;
      final int height = e.codec.height;
      const trackSelectionNameResource = mdk.TrackSelectionNameResource();

      if (bitrate <= 0) {
        bitrate = e.metadata.containsKey('bitrate')
            ? (e.metadata['bitrate'] as int?) ?? -1
            : -1;
      }

      final trackSelectionName = _joinWithSeparator([
        _buildVideoQualityOrResolutionString(
            bitrate, width, height, trackSelectionNameResource),
      ], trackSelectionNameResource.trackItemListSeparator);

      trackSelections.add(MdkTrackSelection(
        trackId: i,
        trackType: MdkTrackSelectionType.video,
        trackName: trackSelectionName.isEmpty
            ? trackSelectionNameResource.trackUnknown
            : trackSelectionName,
        isSelected: false,
        size: width == -1 || height == -1
            ? null
            : Size(width.toDouble(), height.toDouble()),
        bitrate: bitrate == -1 ? null : bitrate,
      ));
    }
    return trackSelections;
  }

  Future<List<MdkTrackSelection>> getAudioTracks(
    int textureId,
  ) async {
    final player = _players[textureId];
    final audioTracks = player?.mediaInfo.audio ?? [];

    const trackSelectionNameResource = mdk.TrackSelectionNameResource();
    final List<MdkTrackSelection> trackSelections = [];

    for (int i = 0; i < audioTracks.length; i++) {
      final e = audioTracks[i];

      final String language = e.metadata['language'] ?? '';
      final String label = e.metadata['label'] ?? '';
      final int channelCount = e.codec.channels;
      int bitrate = e.codec.bitRate;

      final trackSelectionName = _joinWithSeparator([
        _buildLanguageOrLabelString(
            language, label, trackSelectionNameResource),
        _buildAudioChannelString(channelCount, trackSelectionNameResource),
        _buildAvgBitrateString(bitrate, trackSelectionNameResource),
      ], trackSelectionNameResource.trackItemListSeparator);
      trackSelections.add(MdkTrackSelection(
        trackId: i,
        trackType: MdkTrackSelectionType.audio,
        trackName: trackSelectionName.isEmpty
            ? trackSelectionNameResource.trackUnknown
            : trackSelectionName,
        isSelected: false,
        language: language.isEmpty ? null : language,
        label: label.isEmpty ? null : label,
        channel: _toChannelType(channelCount),
        bitrate: bitrate == -1 ? null : bitrate,
      ));
    }
    return trackSelections;
  }

  Future<List<MdkTrackSelection>> getSubtitleTracks(
    int textureId,
  ) async {
    final player = _players[textureId];
    final subtitleTracks = player?.mediaInfo.subtitle ?? [];

    const trackSelectionNameResource = mdk.TrackSelectionNameResource();

    final List<MdkTrackSelection> trackSelections = [];

    for (int i = 0; i < subtitleTracks.length; i++) {
      final e = subtitleTracks[i];
      final String language = e.metadata['language'] ?? '';
      final String label = e.metadata['label'] ?? '';
      final trackSelectionName = _joinWithSeparator([
        _buildLanguageOrLabelString(
            language, label, trackSelectionNameResource),
      ], trackSelectionNameResource.trackItemListSeparator);
      trackSelections.add(MdkTrackSelection(
        trackId: i,
        trackType: MdkTrackSelectionType.subtitle,
        trackName: trackSelectionName.isEmpty
            ? trackSelectionNameResource.trackUnknown
            : trackSelectionName,
        isSelected: false,
        language: language.isEmpty ? null : language,
        label: label.isEmpty ? null : label,
      ));
    }
    return trackSelections;
  }

  /// Gets the selected video track selection.
  /// Returns -1 if no video track is selected.
  int getActiveVideoTrack(int textureId) {
    final player = _players[textureId];
    return player?.activeVideoTracks[0] ?? -1;
  }

  /// Gets the selected audio track selection.
  /// Returns -1 if no audio track is selected.
  int getActiveAudioTrack(int textureId) {
    final player = _players[textureId];
    return player?.activeAudioTracks[0] ?? -1;
  }

  /// Gets the selected subtitle track selection.
  /// Returns -1 if no subtitle track is selected.
  int getActiveSubtitleTrack(int textureId) {
    final player = _players[textureId];
    return player?.activeSubtitleTracks[0] ?? -1;
  }

  /// Sets the selected video track selection.
  void setVideoTrack(int textureId, int trackId) {
    final player = _players[textureId];
    player?.setActiveTracks(MediaType.video, [trackId]);
  }

  /// Sets the selected audio track selection.
  void setAudioTrack(int textureId, int trackId) {
    final player = _players[textureId];
    player?.setActiveTracks(MediaType.audio, [trackId]);
  }

  void updateDataSource(int textureId, DataSource dataSource) {
    String? uri;
    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        uri = _assetUri(dataSource.asset!, dataSource.package);
        break;
      case DataSourceType.network:
        uri = dataSource.uri;
        break;
      case DataSourceType.file:
        uri = Uri.decodeComponent(dataSource.uri!);
        break;
      case DataSourceType.contentUri:
        uri = dataSource.uri;
        break;
    }
    final player = _players[textureId];
    if (player != null) {
      player.media = uri!;
      player.prepare();
      player.updateTexture(
        width: _maxWidth,
        height: _maxHeight,
        tunnel: _tunnel,
        fit: _fitMaxSize,
      );
    }
  }

  ///Sets the subtitle track selection.
  void setSubtitleTrack(int textureId, int trackId) {
    final player = _players[textureId];
    player?.setActiveTracks(MediaType.subtitle, [trackId]);
  }

  Future<Duration> getPosition(int textureId) async {
    final player = _players[textureId];
    if (player == null) {
      return Duration.zero;
    }
    final pos = player.position;
    final bufLen = player.buffered();
    player.streamCtl.add(VideoEvent(
        eventType: VideoEventType.bufferingUpdate,
        buffered: [
          DurationRange(
              Duration(microseconds: pos), Duration(milliseconds: pos + bufLen))
        ]));
    return Duration(milliseconds: pos);
  }

  Stream<VideoEvent> videoEventsFor(int textureId) {
    final player = _players[textureId];
    if (player != null) {
      return player.streamCtl.stream;
    }
    throw Exception('No Stream<VideoEvent> for textureId: $textureId.');
  }

  Widget buildView(int textureId) {
    return Texture(textureId: textureId);
  }

  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  static String _assetUri(String asset, String? package) {
    final key = asset;
    switch (Platform.operatingSystem) {
      case 'windows':
        return path.join(path.dirname(Platform.resolvedExecutable), 'data',
            'flutter_assets', key);
      case 'linux':
        return path.join(path.dirname(Platform.resolvedExecutable), 'data',
            'flutter_assets', key);
      case 'macos':
        return path.join(path.dirname(Platform.resolvedExecutable), '..',
            'Frameworks', 'App.framework', 'Resources', 'flutter_assets', key);
      case 'ios':
        return path.join(path.dirname(Platform.resolvedExecutable),
            'Frameworks', 'App.framework', 'flutter_assets', key);
      case 'android':
        return 'assets://flutter_assets/$key';
    }
    return asset;
  }

  TrackSelectionChannelType? _toChannelType(int channelCount) {
    switch (channelCount) {
      case 1:
        return TrackSelectionChannelType.mono;
      case 2:
        return TrackSelectionChannelType.stereo;
      default:
        return TrackSelectionChannelType.surround;
    }
  }

  String _buildVideoQualityOrResolutionString(
    int bitrate,
    int width,
    int height,
    TrackSelectionNameResource trackSelectionNameResource,
  ) {
    const int bitrate1080p = 2800000;
    const int bitrate720p = 1600000;
    const int bitrate480p = 700000;
    const int bitrate360p = 530000;
    const int bitrate240p = 400000;
    const int bitrate160p = 300000;

    if (bitrate != -1 && bitrate <= bitrate160p) {
      return trackSelectionNameResource.trackBitrate160p;
    }
    if (bitrate != -1 && bitrate <= bitrate240p) {
      return trackSelectionNameResource.trackBitrate240p;
    }
    if (bitrate != -1 && bitrate <= bitrate360p) {
      return trackSelectionNameResource.trackBitrate360p;
    }
    if (bitrate != -1 && bitrate <= bitrate480p) {
      return trackSelectionNameResource.trackBitrate480p;
    }
    if (bitrate != -1 && bitrate <= bitrate720p) {
      return trackSelectionNameResource.trackBitrate720p;
    }
    if (bitrate != -1 && bitrate <= bitrate1080p) {
      return trackSelectionNameResource.trackBitrate1080p;
    }

    return _joinWithSeparator([
      _buildResolutionString(width, height, trackSelectionNameResource),
      _buildAvgBitrateString(bitrate, trackSelectionNameResource),
    ], trackSelectionNameResource.trackItemListSeparator);
  }

  String _buildResolutionString(int width, int height,
      TrackSelectionNameResource trackSelectionNameResource) {
    if (width == -1 || height == -1) {
      return '';
    }
    return [width, trackSelectionNameResource.trackResolutionSeparator, height]
        .join(' ');
  }

  String _buildAvgBitrateString(
      int bitrate, TrackSelectionNameResource trackSelectionNameResource) {
    if (bitrate == -1) {
      return '';
    }
    return [
      (bitrate / 1000000).toStringAsFixed(2),
      trackSelectionNameResource.trackBitrateMbps,
    ].join(' ');
  }

  String _buildLanguageOrLabelString(
    String language,
    String label,
    TrackSelectionNameResource trackSelectionNameResource,
  ) {
    String languageAndRole = _joinWithSeparator(
      [
        language,
      ],
      trackSelectionNameResource.trackItemListSeparator,
    );
    return languageAndRole.isEmpty ? label : languageAndRole;
  }

  String _buildAudioChannelString(
      int channelCount, TrackSelectionNameResource trackSelectionNameResource) {
    if (channelCount == -1) {
      return '';
    }
    switch (channelCount) {
      case 1:
        return trackSelectionNameResource.trackMono;
      case 2:
        return trackSelectionNameResource.trackStereo;
      default:
        return trackSelectionNameResource.trackSurround;
    }
  }

  String _joinWithSeparator(List<String> names, String separator) {
    String jointNames = '';
    for (String name in names) {
      if (jointNames.isEmpty) {
        jointNames = name;
      } else if (name.isNotEmpty) {
        jointNames += [separator, name].join(' ');
      }
    }
    return jointNames;
  }
}
