// Copyright 2022-2024 Wang Bin. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'; //
import 'package:fvp/mdk.dart';
import 'package:fvp/src/fvp_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../mdk.dart' as mdk;
import 'extensions.dart';

final _log = Logger('fvp');

class MdkPlayer extends mdk.Player {
  final streamCtl = StreamController<VideoEvent>();
  bool _initialized = false;

  @override
  void dispose() {
    onMediaStatus(null);
    onEvent(null);
    onStateChanged(null);
    streamCtl.close();
    _initialized = false;
    super.dispose();
  }

  MdkPlayer() : super() {
    onMediaStatus((oldValue, newValue) {
      _log.fine(
          '$hashCode player$nativeHandle onMediaStatus: $oldValue => $newValue');
      if (!oldValue.test(mdk.MediaStatus.loaded) &&
          newValue.test(mdk.MediaStatus.loaded)) {
        // initialized event must be sent only once. keep_open=1 is another solution
        //if ((textureId.value ?? -1) >= 0) {
        //  return true; // prepared callback is invoked before MediaStatus.loaded, so textureId can be a valid value here
        //}
        if (_initialized) {
          _log.fine('$hashCode player$nativeHandle already initialized');
          return true;
        }
        _initialized = true;
        textureSize.then((size) {
          if (size == null) {
            return;
          }
          streamCtl.add(VideoEvent(
              eventType: VideoEventType.initialized,
              duration: Duration(
                  microseconds: isLive
// int max for live streams, duration.inMicroseconds == 9223372036854775807
                      ? double.maxFinite.toInt()
                      : mediaInfo.duration * 1000),
              size: size));
        });
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
          '$hashCode player$nativeHandle onEvent: ${ev.category} - ${ev.detail} - ${ev.error}');
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

  // _prevImpl: required if registerWith() can be invoked multiple times by user
  static MdkVideoPlayerPlatform? _prevImpl;

/*
  Registers this class as the default instance of [VideoPlayerPlatform].

  [options] can be
  "video.decoders": a list of decoder names. supported decoders: https://github.com/wang-bin/mdk-sdk/wiki/Decoders
  "maxWidth", "maxHeight": texture max size. if not set, video frame size is used. a small value can reduce memory cost, but may result in lower image quality.
 */
  void registerVideoPlayerPlatformsWith({dynamic options}) {
    _log.fine('registerVideoPlayerPlatformsWith: $options');
    if (options is Map<String, dynamic>) {
      final platforms = options['platforms'];
      if (platforms is List<String>) {
        if (!platforms.contains(Platform.operatingSystem)) {
          if (_prevImpl != null) {
            // null if it's the 1st time to call registerWith() including current platform
            MdkVideoPlayerPlatform.instance = _prevImpl!;
          }
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
      // prefer hardware decoders
      const vd = {
        'windows': ['MFT:d3d=11', "D3D11", "DXVA", 'CUDA', 'FFmpeg'],
        'macos': ['VT', 'FFmpeg'],
        'ios': ['VT', 'FFmpeg'],
        'linux': ['VAAPI', 'CUDA', 'VDPAU', 'FFmpeg'],
        'android': ['AMediaCodec', 'FFmpeg'],
      };
      _decoders = vd[Platform.operatingSystem];
    }

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
    mdk.setGlobalOption("log", "all");
    mdk.setGlobalOption('d3d11.sync.cpu', 1);
    mdk.setGlobalOption('subtitle.fonts.file',
        PlatformEx.assetUri(_subtitleFontFile ?? 'assets/subfont.ttf'));
    _globalOpts?.forEach((key, value) {
      mdk.setGlobalOption(key, value);
    });

    // if VideoPlayerPlatform.instance.runtimeType.toString() != '_PlaceholderImplementation' ?
    _prevImpl ??= MdkVideoPlayerPlatform.instance;
    MdkVideoPlayerPlatform.instance = MdkVideoPlayerPlatform();
  }

  Future<void> init() async {}

  Future<void> dispose(int textureId) async {
    _players.remove(textureId)?.dispose();
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    final uri = _toUri(dataSource);
    final player = MdkPlayer();
    _log.fine('$hashCode player${player.nativeHandle} create($uri)');

    //player.setProperty("keep_open", "1");
    player.setProperty('video.decoder', 'shader_resource=0');
    player.setProperty('avformat.strict', 'experimental');
    player.setProperty('avio.reconnect', '1');
    player.setProperty('avio.reconnect_delay_max', '7');
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
// +nobuffer: the 1st key-frame packet is dropped. -nobuffer: high latency
      player.setProperty('avformat.fflags', '+nobuffer');
      player.setProperty('avformat.fpsprobesize', '0');
      player.setProperty('avformat.analyzeduration', '100000');
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
    player.media = uri;
    int ret = await player.prepare(); // required!
    if (ret < 0) {
      // no throw, handle error in controller.addListener
      _players[-hashCode] = player;
      player.streamCtl.addError(PlatformException(
        code: 'media open error',
        message: 'invalid or unsupported media',
      ));
      //player.dispose(); // dispose for throw
      return -hashCode;
    }
// FIXME: pending events will be processed after texture returned, but no events before prepared
// FIXME: set tunnel too late
    final tex = await player.updateTexture(
        width: _maxWidth,
        height: _maxHeight,
        tunnel: _tunnel,
        fit: _fitMaxSize);
    if (tex < 0) {
      _players[-hashCode] = player;
      player.streamCtl.addError(PlatformException(
        code: 'video size error',
        message: 'invalid or unsupported media with invalid video size',
      ));
      //player.dispose();
      return -hashCode;
    }
    _log.fine('$hashCode player${player.nativeHandle} textureId=$tex');
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
    return _seekToWithFlags(textureId, position, mdk.SeekFlag(_seekFlags));
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
    final ranges = player.bufferedTimeRanges();
    player.streamCtl.add(VideoEvent(
        eventType: VideoEventType.bufferingUpdate,
        buffered: ranges +
            [
              DurationRange(Duration(milliseconds: pos),
                  Duration(milliseconds: pos + bufLen))
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

  Future<void> setMixWithOthers(bool mixWithOthers) async {
    FvpPlatform.instance.setMixWithOthers(mixWithOthers);
  }

  // more apis for fvp controller
  bool isLive(int textureId) {
    return _players[textureId]?.isLive ?? false;
  }

  //MediaInfo getMediaInfo() {
  //
  //}
  void setProperty(int textureId, String name, String value) {
    _players[textureId]?.setProperty(name, value);
  }

  void setAudioDecoders(int textureId, List<String> value) {
    _players[textureId]?.audioDecoders = value;
  }

  void setVideoDecoders(int textureId, List<String> value) {
    _players[textureId]?.videoDecoders = value;
  }

  void record(int textureId, {String? to, String? format}) {
    _players[textureId]?.record(to: to, format: format);
  }

  Future<Uint8List?> snapshot(int textureId, {int? width, int? height}) async {
    Uint8List? data;
    final player = _players[textureId];
    if (player == null) {
      return data;
    }
    return _players[textureId]?.snapshot(width: width, height: height);
  }

  void setRange(int textureId, {required int from, int to = -1}) {
    _players[textureId]?.setRange(from: from, to: to);
  }

  void setBufferRange(int textureId,
      {int min = -1, int max = -1, bool drop = false}) {
    _players[textureId]?.setBufferRange(min: min, max: max, drop: drop);
  }

  Future<void> fastSeekTo(int textureId, Duration position) async {
    return _seekToWithFlags(
        textureId, position, mdk.SeekFlag(_seekFlags | mdk.SeekFlag.keyFrame));
  }

  Future<void> step(int textureId, int frames) async {
    final player = _players[textureId];
    if (player == null) {
      return;
    }
    player.seek(
        position: frames,
        flags: const mdk.SeekFlag(mdk.SeekFlag.frame | mdk.SeekFlag.fromNow));
  }

  void setBrightness(int textureId, double value) {
    _players[textureId]?.setVideoEffect(mdk.VideoEffect.brightness, [value]);
  }

  void setContrast(int textureId, double value) {
    _players[textureId]?.setVideoEffect(mdk.VideoEffect.contrast, [value]);
  }

  void setHue(int textureId, double value) {
    _players[textureId]?.setVideoEffect(mdk.VideoEffect.hue, [value]);
  }

  void setSaturation(int textureId, double value) {
    _players[textureId]?.setVideoEffect(mdk.VideoEffect.saturation, [value]);
  }

// embedded tracks, can be main data source from create(), or external media source via setExternalAudio
  void setAudioTracks(int textureId, List<int> value) {
    _players[textureId]?.activeAudioTracks = value;
  }

  void setVideoTracks(int textureId, List<int> value) {
    _players[textureId]?.activeVideoTracks = value;
  }

  void setSubtitleTracks(int textureId, List<int> value) {
    _players[textureId]?.activeSubtitleTracks = value;
  }

// external track. can select external tracks via setAudioTracks()
  void setExternalAudio(int textureId, String uri) {
    _players[textureId]?.setMedia(uri, mdk.MediaType.audio);
  }

  void setExternalVideo(int textureId, String uri) {
    _players[textureId]?.setMedia(uri, mdk.MediaType.video);
  }

  void setExternalSubtitle(int textureId, String uri) {
    _players[textureId]?.setMedia(uri, mdk.MediaType.subtitle);
  }

  Future<void> _seekToWithFlags(
      int textureId, Duration position, mdk.SeekFlag flags) async {
    final player = _players[textureId];
    if (player == null) {
      return;
    }
    if (player.isLive) {
      final bufMax = player.buffered();
      final pos = player.position;
      if (position.inMilliseconds <= pos ||
          position.inMilliseconds > pos + bufMax) {
        _log.fine(
            '_seekToWithFlags: $position out of live stream buffered range [$pos, ${pos + bufMax}]');
        return;
      }
    }
    player.seek(position: position.inMilliseconds, flags: flags);
  }

  String _toUri(DataSource dataSource) {
    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        return PlatformEx.assetUri(dataSource.asset!,
            package: dataSource.package);
      case DataSourceType.network:
        return dataSource.uri!;
      case DataSourceType.file:
        return Uri.decodeComponent(dataSource.uri!);
      case DataSourceType.contentUri:
        return dataSource.uri!;
    }
  }

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
