import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Description of the data source used to create an instance of
/// the video player.
class DataSource {
  /// Constructs an instance of [DataSource].
  ///
  /// The [sourceType] is always required.
  ///
  /// The [uri] argument takes the form of `'https://example.com/video.mp4'` or
  /// `'file://${file.path}'`.
  ///
  /// The [formatHint] argument can be null.
  ///
  /// The [asset] argument takes the form of `'assets/video.mp4'`.
  ///
  /// The [package] argument must be non-null when the asset comes from a
  /// package and null otherwise.
  DataSource({
    required this.sourceType,
    this.uri,
    this.formatHint,
    this.asset,
    this.package,
    this.httpHeaders = const <String, String>{},
  });

  /// The way in which the video was originally loaded.
  ///
  /// This has nothing to do with the video's file type. It's just the place
  /// from which the video is fetched from.
  final DataSourceType sourceType;

  /// The URI to the video file.
  ///
  /// This will be in different formats depending on the [DataSourceType] of
  /// the original video.
  final String? uri;

  /// **Android only**. Will override the platform's generic file format
  /// detection with whatever is set here.
  final VideoFormat? formatHint;

  /// HTTP headers used for the request to the [uri].
  /// Only for [DataSourceType.network] videos.
  /// Always empty for other video types.
  Map<String, String> httpHeaders;

  /// The name of the asset. Only set for [DataSourceType.asset] videos.
  final String? asset;

  /// The package that the asset was loaded from. Only set for
  /// [DataSourceType.asset] videos.
  final String? package;
}

/// The way in which the video was originally loaded.
///
/// This has nothing to do with the video's file type. It's just the place
/// from which the video is fetched from.
enum DataSourceType {
  /// The video was included in the app's asset files.
  asset,

  /// The video was downloaded from the internet.
  network,

  /// The video was loaded off of the local filesystem.
  file,

  /// The video is available via contentUri. Android only.
  contentUri,
}

/// The file format of the given video.
enum VideoFormat {
  /// Dynamic Adaptive Streaming over HTTP, also known as MPEG-DASH.
  dash,

  /// HTTP Live Streaming.
  hls,

  /// Smooth Streaming.
  ss,

  /// Any format other than the other ones defined in this enum.
  other,
}

/// Event emitted from the platform implementation.
@immutable
class VideoEvent {
  /// Creates an instance of [VideoEvent].
  ///
  /// The [eventType] argument is required.
  ///
  /// Depending on the [eventType], the [duration], [size],
  /// [rotationCorrection], and [buffered] arguments can be null.
// TODO(stuartmorgan): Temporarily suppress warnings about not using const
  // in all of the other video player packages, fix this, and then update
  // the other packages to use const.
  // ignore: prefer_const_constructors_in_immutables
  VideoEvent({
    required this.eventType,
    this.duration,
    this.size,
    this.rotationCorrection,
    this.buffered,
    this.isPlaying,
  });

  /// The type of the event.
  final VideoEventType eventType;

  /// Duration of the video.
  ///
  /// Only used if [eventType] is [VideoEventType.initialized].
  final Duration? duration;

  /// Size of the video.
  ///
  /// Only used if [eventType] is [VideoEventType.initialized].
  final Size? size;

  /// Degrees to rotate the video (clockwise) so it is displayed correctly.
  ///
  /// Only used if [eventType] is [VideoEventType.initialized].
  final int? rotationCorrection;

  /// Buffered parts of the video.
  ///
  /// Only used if [eventType] is [VideoEventType.bufferingUpdate].
  final List<DurationRange>? buffered;

  /// Whether the video is currently playing.
  ///
  /// Only used if [eventType] is [VideoEventType.isPlayingStateUpdate].
  final bool? isPlaying;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VideoEvent &&
            runtimeType == other.runtimeType &&
            eventType == other.eventType &&
            duration == other.duration &&
            size == other.size &&
            rotationCorrection == other.rotationCorrection &&
            listEquals(buffered, other.buffered) &&
            isPlaying == other.isPlaying;
  }

  @override
  int get hashCode => Object.hash(
    eventType,
    duration,
    size,
    rotationCorrection,
    buffered,
    isPlaying,
  );
}

/// Type of the event.
///
/// Emitted by the platform implementation when the video is initialized or
/// completed or to communicate buffering events or play state changed.
enum VideoEventType {
  /// The video has been initialized.
  initialized,

  /// The playback has ended.
  completed,

  /// Updated information on the buffering state.
  bufferingUpdate,

  /// The video started to buffer.
  bufferingStart,

  /// The video stopped to buffer.
  bufferingEnd,

  /// The playback state of the video has changed.
  ///
  /// This event is fired when the video starts or pauses due to user actions or
  /// phone calls, or other app media such as music players.
  isPlayingStateUpdate,

  /// An unknown event has been received.
  unknown,
}

/// Describes a discrete segment of time within a video using a [start] and
/// [end] [Duration].
@immutable
class DurationRange {
  /// Trusts that the given [start] and [end] are actually in order. They should
  /// both be non-null.
// TODO(stuartmorgan): Temporarily suppress warnings about not using const
  // in all of the other video player packages, fix this, and then update
  // the other packages to use const.
  // ignore: prefer_const_constructors_in_immutables
  DurationRange(this.start, this.end);

  /// The beginning of the segment described relative to the beginning of the
  /// entire video. Should be shorter than or equal to [end].
  ///
  /// For example, if the entire video is 4 minutes long and the range is from
  /// 1:00-2:00, this should be a `Duration` of one minute.
  final Duration start;

  /// The end of the segment described as a duration relative to the beginning of
  /// the entire video. This is expected to be non-null and longer than or equal
  /// to [start].
  ///
  /// For example, if the entire video is 4 minutes long and the range is from
  /// 1:00-2:00, this should be a `Duration` of two minutes.
  final Duration end;

  /// Assumes that [duration] is the total length of the video that this
  /// DurationRange is a segment form. It returns the percentage that [start] is
  /// through the entire video.
  ///
  /// For example, assume that the entire video is 4 minutes long. If [start] has
  /// a duration of one minute, this will return `0.25` since the DurationRange
  /// starts 25% of the way through the video's total length.
  double startFraction(Duration duration) {
    return start.inMilliseconds / duration.inMilliseconds;
  }

  /// Assumes that [duration] is the total length of the video that this
  /// DurationRange is a segment form. It returns the percentage that [start] is
  /// through the entire video.
  ///
  /// For example, assume that the entire video is 4 minutes long. If [end] has a
  /// duration of two minutes, this will return `0.5` since the DurationRange
  /// ends 50% of the way through the video's total length.
  double endFraction(Duration duration) {
    return end.inMilliseconds / duration.inMilliseconds;
  }

  @override
  String toString() =>
      '${objectRuntimeType(this, 'DurationRange')}(start: $start, end: $end)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is DurationRange &&
              runtimeType == other.runtimeType &&
              start == other.start &&
              end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}


/// [VideoPlayerOptions] can be optionally used to set additional player settings
@immutable
class VideoPlayerOptions {
  /// Set additional optional player settings
  // TODO(stuartmorgan): Temporarily suppress warnings about not using const
  // in all of the other video player packages, fix this, and then update
  // the other packages to use const.
  // ignore: prefer_const_constructors_in_immutables
  VideoPlayerOptions({
    this.mixWithOthers = false,
    this.allowBackgroundPlayback = false,
    this.webOptions,
  });

  /// Set this to true to keep playing video in background, when app goes in background.
  /// The default value is false.
  final bool allowBackgroundPlayback;

  /// Set this to true to mix the video players audio with other audio sources.
  /// The default value is false
  ///
  /// Note: This option will be silently ignored in the web platform (there is
  /// currently no way to implement this feature in this platform).
  final bool mixWithOthers;

  /// Additional web controls
  final VideoPlayerWebOptions? webOptions;
}

/// [VideoPlayerWebOptions] can be optionally used to set additional web settings
@immutable
class VideoPlayerWebOptions {
  /// [VideoPlayerWebOptions] can be optionally used to set additional web settings
  const VideoPlayerWebOptions({
    this.controls = const VideoPlayerWebOptionsControls.disabled(),
    this.allowContextMenu = true,
    this.allowRemotePlayback = true,
  });

  /// Additional settings for how control options are displayed
  final VideoPlayerWebOptionsControls controls;

  /// Whether context menu (right click) is allowed
  final bool allowContextMenu;

  /// Whether remote playback is allowed
  final bool allowRemotePlayback;
}

/// [VideoPlayerWebOptions] can be used to set how control options are displayed
@immutable
class VideoPlayerWebOptionsControls {
  /// Enables controls and sets how the options are displayed
  const VideoPlayerWebOptionsControls.enabled({
    this.allowDownload = true,
    this.allowFullscreen = true,
    this.allowPlaybackRate = true,
    this.allowPictureInPicture = true,
  }) : enabled = true;

  /// Disables control options. Default behavior.
  const VideoPlayerWebOptionsControls.disabled()
      : enabled = false,
        allowDownload = false,
        allowFullscreen = false,
        allowPlaybackRate = false,
        allowPictureInPicture = false;

  /// Whether native controls are enabled
  final bool enabled;

  /// Whether downloaded control is displayed
  ///
  /// Only applicable when [controlsEnabled] is true
  final bool allowDownload;

  /// Whether fullscreen control is enabled
  ///
  /// Only applicable when [controlsEnabled] is true
  final bool allowFullscreen;

  /// Whether playback rate control is displayed
  ///
  /// Only applicable when [controlsEnabled] is true
  final bool allowPlaybackRate;

  /// Whether picture in picture control is displayed
  ///
  /// Only applicable when [controlsEnabled] is true
  final bool allowPictureInPicture;

  /// A string representation of disallowed controls
  String get controlsList {
    final List<String> controlsList = <String>[];
    if (!allowDownload) {
      controlsList.add('nodownload');
    }
    if (!allowFullscreen) {
      controlsList.add('nofullscreen');
    }
    if (!allowPlaybackRate) {
      controlsList.add('noplaybackrate');
    }

    return controlsList.join(' ');
  }
}


/// A representation of a single track selection.
///
/// A typical video file will include several [MdkTrackSelection]s. For convenience
/// the auto track selection will be added to this list of [getTrackSelections].
class MdkTrackSelection {
  /// Creates an instance of [VideoEvent].
  ///
  /// The [trackId], [trackType], [trackName] and [isSelected] argument is required.
  ///
  /// Depending on the [trackType], the [width], [height], [language], [label],
  /// [channel] and [bitrate] arguments can be null.
  const MdkTrackSelection({
    required this.trackId,
    required this.trackType,
    required this.trackName,
    required this.isSelected,
    this.size,
    this.role,
    this.language,
    this.label,
    this.channel,
    this.bitrate,
  });

  /// The track id of track selection that uses to determine track selection.
  ///
  /// The track id includes a render number for auto track selection and three numbers
  /// (a render number, a render group index number and a track number) for non-auto
  /// track selection.
  final int trackId;

  /// The type of the track selection.
  final MdkTrackSelectionType trackType;

  /// The name of track selection that uses [TrackSelectionNameResource] to represent
  /// the suggestion name for each track selection based on its type.
  final String trackName;

  /// If the track selection is selected using [setTrackSelection] method, this
  /// is true. For each type there is one selected track selection.
  final bool isSelected;

  /// The size of video track selection. This will be null if the [trackType]
  /// is not [MdkTrackSelectionType.video] or an unknown or a auto track selection.
  ///
  /// If the track selection doesn't specify the width or height this may be null.
  final Size? size;

  /// The label of track selection. This will be null if the [trackType]
  /// is not an unknown or a auto track selection.
  ///
  /// If the track selection doesn't specify the role this may be null.
  final TrackSelectionRoleType? role;

  /// The language of track selection. This will be null if the [trackType]
  /// is not [MdkTrackSelectionType.audio] and [MdkTrackSelectionType.subtitle] or an unknown
  /// or a auto track selection.
  ///
  /// If the track selection doesn't specify the language this may be null.
  final String? language;

  /// The label of track selection. This will be null if the [trackType]
  /// is not [MdkTrackSelectionType.audio] and [MdkTrackSelectionType.subtitle] or an unknown
  /// or a auto track selection.
  ///
  /// If the track selection doesn't specify the label this may be null.
  final String? label;

  /// The channelCount of track selection. This will be null if the [trackType]
  /// is not [MdkTrackSelectionType.audio] or an unknown or a auto track selection.
  ///
  /// If the track selection doesn't specify the channelCount this may be null.
  final TrackSelectionChannelType? channel;

  /// The label of track selection. This will be null if the [trackType]
  /// is not [MdkTrackSelectionType.video] and [MdkTrackSelectionType.audio] or an unknown
  /// or a auto track selection.
  ///
  /// If the track selection doesn't specify the bitrate this may be null.
  final int? bitrate;

  @override
  String toString() {
    return '$runtimeType('
        'trackId: $trackId, '
        'trackType: $trackType, '
        'trackName: $trackName, '
        'isSelected: $isSelected, '
        'size: $size, '
        'role: $role, '
        'language: $language, '
        'label: $label, '
        'channel: $channel, '
        'bitrate: $bitrate)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is MdkTrackSelection &&
              runtimeType == other.runtimeType &&
              trackId == other.trackId &&
              trackType == other.trackType &&
              trackName == other.trackName &&
              isSelected == other.isSelected &&
              size == other.size &&
              role == other.role &&
              label == other.label &&
              channel == other.channel &&
              bitrate == other.bitrate;

  @override
  int get hashCode =>
      trackId.hashCode ^
      trackType.hashCode ^
      trackName.hashCode ^
      isSelected.hashCode ^
      size.hashCode ^
      role.hashCode ^
      label.hashCode ^
      channel.hashCode ^
      bitrate.hashCode;
}

/// Type of the track selection.
enum MdkTrackSelectionType {
  /// The video track selection.
  video,

  /// The audio track selection.
  audio,

  /// The text track selection.
  subtitle,
}

/// Type of the track selection role.
enum TrackSelectionRoleType {
  /// The alternate role.
  alternate,

  /// The supplementary role.
  supplementary,

  /// The commentary role.
  commentary,

  /// The closedCaptions role.
  closedCaptions,
}

/// Type of the track selection channel for [MdkTrackSelectionType.audio].
enum TrackSelectionChannelType {
  /// The mono channel.
  mono,

  /// The stereo channel.
  stereo,

  /// The surround channel.
  surround,
}

/// String resources uses to represent track selection name.
///
/// Pass this class as an argument to [getTrackSelections].
class TrackSelectionNameResource {
  /// Constructs an instance of [TrackSelectionNameResource].
  const TrackSelectionNameResource({
    this.trackAuto = 'Auto',
    this.trackUnknown = 'Unknown',
    this.trackBitrate1080p = '1080P',
    this.trackBitrate720p = '720P',
    this.trackBitrate480p = '480P',
    this.trackBitrate360p = '360P',
    this.trackBitrate240p = '240P',
    this.trackBitrate160p = '160P',
    this.trackResolutionSeparator = '×',
    this.trackBitrateMbps = 'Mbps',
    this.trackMono = 'Mono',
    this.trackStereo = 'Stereo',
    this.trackSurround = 'Surround sound',
    this.trackItemListSeparator = ',',
    this.trackRoleAlternate = 'Alternate',
    this.trackRoleSupplementary = 'Supplementary',
    this.trackRoleCommentary = 'Commentary',
    this.trackRoleClosedCaptions = 'CC',
  });

  /// [MdkTrackSelection.trackName] is `Auto` if track selection is auto.
  final String trackAuto;

  /// [MdkTrackSelection.trackName] is `Unknown` if track selection is unknown.
  final String trackUnknown;

  /// `1080P` quality for [MdkTrackSelectionType.video] track selection.
  final String trackBitrate1080p;

  /// `720P` quality for [MdkTrackSelectionType.video] track selection.
  final String trackBitrate720p;

  /// `480P` quality for [MdkTrackSelectionType.video] track selection.
  final String trackBitrate480p;

  /// `360P` quality for [MdkTrackSelectionType.video] track selection.
  final String trackBitrate360p;

  /// `240P` quality for [MdkTrackSelectionType.video] track selection.
  final String trackBitrate240p;

  /// `160P` quality for [MdkTrackSelectionType.video] track selection.
  final String trackBitrate160p;

  /// `×` resolution separator for [MdkTrackSelectionType.video] track selection.
  ///
  /// For example if track selection bitrate is not in range of 0.3 to 2.8 Mbps,
  /// [MdkTrackSelection.trackName] will be `2048 × 1080`.
  final String trackResolutionSeparator;

  /// `Mbps` followed by bitrate.
  ///
  /// For example `3.5 Mbps`.
  final String trackBitrateMbps;

  /// `Mono` for [MdkTrackSelectionType.audio] if track selection
  /// channel count is 1.
  final String trackMono;

  /// `Stereo` for [MdkTrackSelectionType.audio] if track selection
  /// channel count is 1.
  final String trackStereo;

  /// `Surround sound` for [MdkTrackSelectionType.audio] if track selection
  /// channel count is 1.
  final String trackSurround;

  /// `,` to separate items in track name.
  final String trackItemListSeparator;

  /// `Alternate` for a track if it has role.
  final String trackRoleAlternate;

  /// `Supplementary` for a track if it has role.
  final String trackRoleSupplementary;

  /// `Commentary` for a track if it has role.
  final String trackRoleCommentary;

  /// `CC` for a track if it has role.
  final String trackRoleClosedCaptions;
}


