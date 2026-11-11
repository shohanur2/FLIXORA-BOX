import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import 'download_task.dart';

class ManifestDownloadOption {
  const ManifestDownloadOption({
    required this.url,
    required this.type,
    required this.quality,
    this.audioUrl,
    this.audioName,
    this.bandwidth = 0,
    this.resolution,
  });

  final String url;
  final String type;
  final String quality;
  final String? audioUrl;
  final String? audioName;
  final int bandwidth;
  final String? resolution;

  Map<String, String> toMap() => {
        'video_url': url,
        'download_type': type,
        'quality': quality,
        if (audioUrl != null && audioUrl!.isNotEmpty) 'audio_url': audioUrl!,
        if (audioName != null && audioName!.isNotEmpty) 'audio_name': audioName!,
        if (bandwidth > 0) 'manifest_bandwidth': bandwidth.toString(),
        if (resolution != null && resolution!.isNotEmpty)
          'manifest_resolution': resolution!,
        'size_bytes': '',
      };
}

/// Offline support for clear, finite HLS VOD playlists and static, unprotected
/// DASH manifests. DRM, encrypted HLS keys, live playlists and unsupported
/// DASH layouts are rejected instead of creating broken offline files.
class ManifestDownloadManager {
  ManifestDownloadManager._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 20),
      followRedirects: true,
      maxRedirects: 8,
      responseType: ResponseType.plain,
    ),
  );

  static Uri? safeManifestUri(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    return uri;
  }

  static Future<List<ManifestDownloadOption>> inspect(String rawUrl) async {
    final uri = safeManifestUri(rawUrl);
    if (uri == null) return const [];

    final path = uri.path.toLowerCase();
    final looksHls = path.endsWith('.m3u8');
    final looksDash = path.endsWith('.mpd');
    if (!looksHls && !looksDash) return const [];

    try {
      final text = await _readText(uri);
      if (looksHls || text.trimLeft().startsWith('#EXTM3U')) {
        return parseHlsOptions(uri, text);
      }
      if (looksDash || text.contains('<MPD')) {
        final plans = _parseDashPlans(text, uri);
        return plans.isEmpty
            ? const []
            : [
                ManifestDownloadOption(
                  url: uri.toString(),
                  type: 'dash',
                  quality: 'DASH · Adaptive',
                ),
              ];
      }
    } catch (_) {
      return const [];
    }
    return const [];
  }

  static List<ManifestDownloadOption> parseHlsOptions(
    Uri baseUri,
    String playlist,
  ) {
    final lines = playlist.replaceAll('\r', '').split('\n');
    if (lines.isEmpty || lines.first.trim() != '#EXTM3U') return const [];

    final audioGroups = <String, List<Map<String, String>>>{};
    for (final line in lines) {
      if (!line.startsWith('#EXT-X-MEDIA:')) continue;
      final attributes = _parseHlsAttributes(
        line.substring('#EXT-X-MEDIA:'.length),
      );
      if ((attributes['TYPE'] ?? '').toUpperCase() != 'AUDIO') continue;
      final group = attributes['GROUP-ID'] ?? '';
      if (group.isEmpty) continue;
      audioGroups.putIfAbsent(group, () => []).add(attributes);
    }

    final options = <ManifestDownloadOption>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;

      final attributes = _parseHlsAttributes(
        line.substring('#EXT-X-STREAM-INF:'.length),
      );
      var uriLine = '';
      for (var next = index + 1; next < lines.length; next++) {
        final candidate = lines[next].trim();
        if (candidate.isEmpty || candidate.startsWith('#')) continue;
        uriLine = candidate;
        break;
      }
      if (uriLine.isEmpty) continue;

      final videoUri = baseUri.resolve(uriLine);
      if (safeManifestUri(videoUri.toString()) == null) continue;

      final resolution = attributes['RESOLUTION'];
      final bandwidth = int.tryParse(
            attributes['AVERAGE-BANDWIDTH'] ?? attributes['BANDWIDTH'] ?? '',
          ) ??
          0;
      final quality = _qualityLabel(resolution, bandwidth);
      final audioGroup = attributes['AUDIO'];
      String? audioUrl;
      String? audioName;
      if (audioGroup != null && audioGroup.isNotEmpty) {
        final choices = audioGroups[audioGroup] ?? const [];
        if (choices.isEmpty) continue;
        final selectedAudio = choices.firstWhere(
          (item) => item['DEFAULT']?.toUpperCase() == 'YES',
          orElse: () => choices.first,
        );
        final audioPath = selectedAudio['URI'];
        if (audioPath == null || audioPath.isEmpty) continue;
        audioUrl = baseUri.resolve(audioPath).toString();
        audioName = selectedAudio['NAME'] ?? 'Audio';
      }

      options.add(ManifestDownloadOption(
        url: videoUri.toString(),
        type: 'hls',
        quality: quality,
        audioUrl: audioUrl,
        audioName: audioName,
        bandwidth: bandwidth,
        resolution: resolution,
      ));
    }

    if (options.isNotEmpty) {
      options.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      return options;
    }

    if (playlist.contains('#EXTINF:')) {
      return [
        ManifestDownloadOption(
          url: baseUri.toString(),
          type: 'hls',
          quality: 'HLS · Original',
        ),
      ];
    }
    return const [];
  }

  static String _qualityLabel(String? resolution, int bandwidth) {
    final match = RegExp(r'(\d+)x(\d+)', caseSensitive: false)
        .firstMatch(resolution ?? '');
    if (match != null) return '${match.group(2)}p';
    if (bandwidth > 0) return 'HLS · ${(bandwidth / 1000).round()} kbps';
    return 'HLS · Original';
  }

  static Map<String, String> _parseHlsAttributes(String raw) {
    final result = <String, String>{};
    final pattern = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
    for (final match in pattern.allMatches(raw)) {
      var value = (match.group(2) ?? '').trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      result[match.group(1) ?? ''] = value;
    }
    return result;
  }

  static bool isSupportedDashManifest(String text) {
    try {
      return _parseDashPlans(
        text,
        Uri.parse('https://manifest.invalid/master.mpd'),
      ).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<String> download({
    required DownloadTask task,
    required CancelToken cancelToken,
    required void Function() onProgress,
  }) async {
    final directory = await _downloadDirectory(task);
    if (task.downloadType == 'hls') {
      return _downloadHls(
        task,
        directory,
        cancelToken,
        onProgress,
      );
    }
    if (task.downloadType == 'dash') {
      return _downloadDash(
        task,
        directory,
        cancelToken,
        onProgress,
      );
    }
    throw StateError('Unsupported manifest download type.');
  }

  static Future<Directory> _downloadDirectory(DownloadTask task) async {
    final existing = task.downloadDirectory;
    if (existing != null && existing.isNotEmpty) {
      final directory = Directory(existing);
      await directory.create(recursive: true);
      task.partialPath = directory.path;
      return directory;
    }

    final documents = await getApplicationDocumentsDirectory();
    final safeName = task.displayTitle
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final directory = Directory(
      '${documents.path}/flixora_downloads/${safeName}_${task.taskId}',
    );
    await directory.create(recursive: true);
    task
      ..downloadDirectory = directory.path
      ..partialPath = directory.path;
    return directory;
  }

  static Future<String> _readText(Uri uri) async {
    final response = await _dio.get<String>(
      uri.toString(),
      options: Options(
        responseType: ResponseType.plain,
        headers: const {'Accept': '*/*'},
      ),
    );
    if ((response.statusCode ?? 0) < 200 ||
        (response.statusCode ?? 0) >= 300) {
      throw StateError('The video host returned HTTP ${response.statusCode}.');
    }
    return response.data ?? '';
  }

  static Future<String> _downloadHls(
    DownloadTask task,
    Directory directory,
    CancelToken token,
    void Function() onProgress,
  ) async {
    final videoUri = safeManifestUri(task.videoUrl);
    if (videoUri == null) throw StateError('Invalid HLS playlist URL.');

    var effectiveVideoUrl = task.videoUrl;
    var effectiveAudioUrl = task.audioUrl;
    var effectiveAudioName = task.audioName;
    var effectiveBandwidth = task.manifestBandwidth;
    var effectiveResolution = task.manifestResolution;
    var videoText = await _readText(videoUri);
    if (videoText.contains('#EXT-X-STREAM-INF:')) {
      final variants = parseHlsOptions(videoUri, videoText);
      if (variants.isEmpty) {
        throw StateError('The HLS master playlist has no downloadable variant.');
      }
      final selected = variants.first;
      effectiveVideoUrl = selected.url;
      effectiveAudioUrl = selected.audioUrl;
      effectiveAudioName = selected.audioName;
      effectiveBandwidth = selected.bandwidth;
      effectiveResolution = selected.resolution;
      final selectedUri = safeManifestUri(effectiveVideoUrl);
      if (selectedUri == null) throw StateError('Invalid HLS variant URL.');
      videoText = await _readText(selectedUri);
    }

    final effectiveVideoUri = safeManifestUri(effectiveVideoUrl);
    if (effectiveVideoUri == null) throw StateError('Invalid HLS variant URL.');
    final videoPlan = _prepareHlsMediaPlaylist(
      effectiveVideoUri,
      videoText,
      'video',
    );
    _HlsPlaylistPlan? audioPlan;
    if (effectiveAudioUrl != null && effectiveAudioUrl.isNotEmpty) {
      final audioUri = safeManifestUri(effectiveAudioUrl);
      if (audioUri == null) throw StateError('Invalid HLS audio playlist URL.');
      final audioText = await _readText(audioUri);
      audioPlan = _prepareHlsMediaPlaylist(audioUri, audioText, 'audio');
    }

    final plans = <_HlsPlaylistPlan>[
      videoPlan,
      if (audioPlan != null) audioPlan,
    ];
    final resources = plans.expand((plan) => plan.resources).toList();
    if (resources.isEmpty) throw StateError('The HLS playlist contains no media segments.');

    task
      ..totalSegments = resources.length
      ..completedSegments = 0
      ..totalBytes = 0
      ..bytesReceived = 0;

    for (final resource in resources) {
      final target = File('${directory.path}/${resource.fileName}');
      if (await target.exists() && await target.length() > 0) {
        task
          ..completedSegments++
          ..bytesReceived += await target.length();
      }
    }
    _updateManifestProgress(task);
    onProgress();

    for (final resource in resources) {
      if (token.isCancelled) throw DioException(
        requestOptions: RequestOptions(path: resource.uri.toString()),
        type: DioExceptionType.cancel,
        message: 'Download interrupted.',
      );
      final target = File('${directory.path}/${resource.fileName}');
      if (await target.exists() && await target.length() > 0) continue;
      final size = await _downloadResource(resource.uri, target, token);
      task
        ..completedSegments++
        ..bytesReceived += size;
      _updateManifestProgress(task);
      onProgress();
    }

    final videoPlaylistPath = '${directory.path}/video.m3u8';
    await File(videoPlaylistPath).writeAsString(
      _renderHlsPlaylist(videoPlan),
      flush: true,
    );

    if (audioPlan != null) {
      await File('${directory.path}/audio.m3u8').writeAsString(
        _renderHlsPlaylist(audioPlan),
        flush: true,
      );
      final audioName = _hlsQuote(effectiveAudioName ?? 'Audio');
      final resolution = effectiveResolution;
      final bandwidth = effectiveBandwidth > 0 ? effectiveBandwidth : 1;
      final master = StringBuffer()
        ..writeln('#EXTM3U')
        ..writeln('#EXT-X-VERSION:3')
        ..writeln(
          '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="$audioName",DEFAULT=YES,AUTOSELECT=YES,URI="audio.m3u8"',
        )
        ..write(
          '#EXT-X-STREAM-INF:BANDWIDTH=$bandwidth,AUDIO="audio"${resolution == null ? '' : ',RESOLUTION=$resolution'}\nvideo.m3u8\n',
        );
      final path = '${directory.path}/offline.m3u8';
      await File(path).writeAsString(master.toString(), flush: true);
      task.filePath = path;
    } else {
      task.filePath = videoPlaylistPath;
    }

    task
      ..downloadDirectory = directory.path
      ..partialPath = directory.path
      ..progress = 1;
    final size = await _directorySize(directory);
    task
      ..bytesReceived = size
      ..totalBytes = size;
    return task.filePath!;
  }

  static _HlsPlaylistPlan _prepareHlsMediaPlaylist(
    Uri baseUri,
    String playlist,
    String prefix,
  ) {
    final lines = playlist.replaceAll('\r', '').split('\n');
    if (lines.isEmpty || lines.first.trim() != '#EXTM3U') {
      throw StateError('The HLS source did not return a media playlist.');
    }
    if (!playlist.contains('#EXT-X-ENDLIST')) {
      throw StateError('Live HLS streams cannot be saved for offline playback.');
    }
    if (lines.any((line) => line.startsWith('#EXT-X-BYTERANGE'))) {
      throw StateError('This HLS source uses byte-range segments, which are not supported for offline downloads.');
    }

    for (final line in lines) {
      if (line.startsWith('#EXT-X-KEY:') ||
          line.startsWith('#EXT-X-SESSION-KEY:')) {
        final method = RegExp(r'METHOD=([^,]+)')
            .firstMatch(line)?.group(1)?.replaceAll('"', '').trim();
        if (method != null && method.toUpperCase() != 'NONE') {
          throw StateError('Encrypted HLS streams are not available for offline downloads.');
        }
        if (line.startsWith('#EXT-X-SESSION-KEY:')) {
          throw StateError('Encrypted HLS streams are not available for offline downloads.');
        }
      }
    }

    final resources = <_HlsResource>[];
    final replacements = <int, String>{};
    var segmentIndex = 0;
    var mapIndex = 0;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.startsWith('#EXT-X-MAP:')) {
        final match = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (match == null) {
          throw StateError('The HLS initialization segment is invalid.');
        }
        if (line.contains('BYTERANGE=')) {
          throw StateError('HLS byte-range initialization segments are not supported.');
        }
        final uri = baseUri.resolve(match.group(1)!);
        final fileName = '${prefix}_init_${mapIndex++}${_safeExtension(uri.path)}';
        resources.add(_HlsResource(uri: uri, fileName: fileName));
        replacements[index] = line.replaceFirst(match.group(0)!, 'URI="$fileName"');
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        final uri = baseUri.resolve(line);
        final fileName =
            '${prefix}_segment_${segmentIndex.toString().padLeft(5, '0')}${_safeExtension(uri.path)}';
        resources.add(_HlsResource(uri: uri, fileName: fileName));
        replacements[index] = fileName;
        segmentIndex++;
      }
    }

    if (segmentIndex == 0) {
      throw StateError('The HLS media playlist contains no downloadable segments.');
    }
    return _HlsPlaylistPlan(
      lines: lines,
      resources: resources,
      replacements: replacements,
    );
  }

  static String _renderHlsPlaylist(_HlsPlaylistPlan plan) {
    return plan.lines.asMap().entries.map((entry) {
      return plan.replacements[entry.key] ?? entry.value;
    }).join('\n');
  }

  static String _hlsQuote(String value) =>
      value.replaceAll('"', '').replaceAll('\n', ' ').trim();

  static Future<String> _downloadDash(
    DownloadTask task,
    Directory directory,
    CancelToken token,
    void Function() onProgress,
  ) async {
    final manifestUri = safeManifestUri(task.videoUrl);
    if (manifestUri == null) throw StateError('Invalid DASH manifest URL.');
    final manifestText = await _readText(manifestUri);
    final document = XmlDocument.parse(manifestText);
    final root = document.rootElement;
    final plans = _parseDashPlans(manifestText, manifestUri);
    if (plans.isEmpty) {
      throw StateError('This DASH manifest layout is not supported for offline downloads.');
    }

    final resources = <_DashResource>[];
    for (var planIndex = 0; planIndex < plans.length; planIndex++) {
      final plan = plans[planIndex];
      final prefix = plan.kind == 'video' ? 'video' : 'audio';
      if (plan.initializationUri != null) {
        resources.add(_DashResource(
          uri: plan.initializationUri!,
          fileName: '${prefix}_init.bin',
        ));
      }
      for (var index = 0; index < plan.segmentUris.length; index++) {
        resources.add(_DashResource(
          uri: plan.segmentUris[index],
          fileName:
              '${prefix}_segment_${index.toString().padLeft(5, '0')}.bin',
        ));
      }
    }
    if (resources.isEmpty) throw StateError('The DASH manifest contains no media segments.');

    task
      ..totalSegments = resources.length
      ..completedSegments = 0
      ..totalBytes = 0
      ..bytesReceived = 0;

    for (final resource in resources) {
      final target = File('${directory.path}/${resource.fileName}');
      if (await target.exists() && await target.length() > 0) {
        task
          ..completedSegments++
          ..bytesReceived += await target.length();
      }
    }
    _updateManifestProgress(task);
    onProgress();

    for (final resource in resources) {
      if (token.isCancelled) throw DioException(
        requestOptions: RequestOptions(path: resource.uri.toString()),
        type: DioExceptionType.cancel,
        message: 'Download interrupted.',
      );
      final target = File('${directory.path}/${resource.fileName}');
      if (await target.exists() && await target.length() > 0) continue;
      final size = await _downloadResource(resource.uri, target, token);
      task
        ..completedSegments++
        ..bytesReceived += size;
      _updateManifestProgress(task);
      onProgress();
    }

    final localManifest = _renderDashManifest(root, plans);
    final path = '${directory.path}/offline.mpd';
    await File(path).writeAsString(localManifest, flush: true);
    task
      ..filePath = path
      ..downloadDirectory = directory.path
      ..partialPath = directory.path
      ..progress = 1;
    final size = await _directorySize(directory);
    task
      ..bytesReceived = size
      ..totalBytes = size;
    return path;
  }

  static List<_DashPlan> _parseDashPlans(String text, Uri manifestUri) {
    final document = XmlDocument.parse(text);
    final root = document.rootElement;
    if (root.name.local != 'MPD') {
      throw const FormatException('Not an MPD manifest.');
    }
    if ((root.getAttribute('type') ?? 'static').toLowerCase() != 'static') {
      throw StateError('Live DASH streams cannot be saved for offline playback.');
    }
    final protected = root.descendants
        .whereType<XmlElement>()
        .any((element) => element.name.local == 'ContentProtection');
    if (protected) {
      throw StateError('DRM-protected DASH streams are not available for offline downloads.');
    }

    final periods = root.childElements
        .where((element) => element.name.local == 'Period')
        .toList();
    if (periods.length != 1) {
      throw StateError('DASH manifests with multiple periods are not supported yet.');
    }
    final period = periods.first;
    final adaptations = period.childElements
        .where((element) => element.name.local == 'AdaptationSet')
        .toList();
    _DashCandidate? bestVideo;
    _DashCandidate? bestAudio;

    for (final adaptation in adaptations) {
      final representations = adaptation.childElements
          .where((element) => element.name.local == 'Representation')
          .toList();
      final mime = (adaptation.getAttribute('mimeType') ?? '').toLowerCase();
      final contentType =
          (adaptation.getAttribute('contentType') ?? '').toLowerCase();
      for (var index = 0; index < representations.length; index++) {
        final representation = representations[index];
        final repMime =
            (representation.getAttribute('mimeType') ?? mime).toLowerCase();
        final repType = contentType.isNotEmpty
            ? contentType
            : repMime.startsWith('video/')
                ? 'video'
                : repMime.startsWith('audio/')
                    ? 'audio'
                    : '';
        final bandwidth =
            int.tryParse(representation.getAttribute('bandwidth') ?? '') ?? 0;
        final candidate = _DashCandidate(
          kind: repType,
          adaptation: adaptation,
          representation: representation,
          index: index,
          bandwidth: bandwidth,
        );
        if (repType == 'video' &&
            (bestVideo == null || bandwidth > bestVideo.bandwidth)) {
          bestVideo = candidate;
        } else if (repType == 'audio' &&
            (bestAudio == null || bandwidth > bestAudio.bandwidth)) {
          bestAudio = candidate;
        }
      }
    }

    if (bestVideo == null) {
      throw StateError('The DASH manifest has no supported video representation.');
    }
    final candidates = <_DashCandidate>[
      bestVideo,
      if (bestAudio != null) bestAudio,
    ];
    final plans = <_DashPlan>[];
    for (final candidate in candidates) {
      plans.add(_buildDashPlan(
        root: root,
        period: period,
        candidate: candidate,
        manifestUri: manifestUri,
      ));
    }
    return plans;
  }

  static _DashPlan _buildDashPlan({
    required XmlElement root,
    required XmlElement period,
    required _DashCandidate candidate,
    required Uri manifestUri,
  }) {
    final adaptation = candidate.adaptation;
    final representation = candidate.representation;
    final baseUri = _resolveDashBase(
      manifestUri,
      [root, period, adaptation, representation],
    );
    final segmentList = _findInheritedChild(
      [representation, adaptation, period, root],
      'SegmentList',
    );
    final segmentTemplate = _findInheritedChild(
      [representation, adaptation, period, root],
      'SegmentTemplate',
    );

    final segmentUris = <Uri>[];
    Uri? initializationUri;
    var timescale = 1;
    int? duration;
    var startNumber = 1;
    final timeline = <_DashTimelineItem>[];

    if (segmentList != null) {
      timescale = int.tryParse(segmentList.getAttribute('timescale') ?? '') ?? 1;
      duration = int.tryParse(segmentList.getAttribute('duration') ?? '');
      startNumber = int.tryParse(segmentList.getAttribute('startNumber') ?? '') ?? 1;
      final initialization = _findChild(segmentList, 'Initialization');
      final initPath = initialization?.getAttribute('sourceURL');
      if (initPath != null && initPath.isNotEmpty) {
        initializationUri = baseUri.resolve(initPath);
      }
      final urls = segmentList.childElements
          .where((element) => element.name.local == 'SegmentURL')
          .toList();
      for (final url in urls) {
        final media = url.getAttribute('media');
        if (media == null || media.isEmpty) {
          throw StateError('A DASH SegmentURL is missing its media path.');
        }
        segmentUris.add(baseUri.resolve(media));
      }
      final timelineElement = _findChild(segmentList, 'SegmentTimeline');
      if (timelineElement != null) {
        timeline.addAll(_parseDashTimeline(timelineElement));
      }
    } else if (segmentTemplate != null) {
      timescale = int.tryParse(segmentTemplate.getAttribute('timescale') ?? '') ?? 1;
      duration = int.tryParse(segmentTemplate.getAttribute('duration') ?? '');
      startNumber =
          int.tryParse(segmentTemplate.getAttribute('startNumber') ?? '') ?? 1;
      final mediaTemplate = segmentTemplate.getAttribute('media');
      if (mediaTemplate == null || mediaTemplate.isEmpty) {
        throw StateError('The DASH SegmentTemplate has no media template.');
      }
      final timelineElement = _findChild(segmentTemplate, 'SegmentTimeline');
      final times = <({int time, int duration})>[];
      if (timelineElement != null) {
        final parsed = _parseDashTimeline(timelineElement);
        for (final item in parsed) {
          times.add((time: item.time, duration: item.duration));
        }
      } else {
        if (duration == null || duration <= 0) {
          throw StateError('The DASH SegmentTemplate has no usable duration.');
        }
        final periodDuration = _parseIsoDuration(
          period.getAttribute('duration') ??
              root.getAttribute('mediaPresentationDuration') ??
              '',
        );
        if (periodDuration == null || periodDuration <= 0) {
          throw StateError('The DASH period duration is unavailable.');
        }
        final count = (periodDuration * timescale / duration).ceil();
        for (var index = 0; index < count; index++) {
          times.add((time: index * duration, duration: duration));
        }
      }
      if (times.isEmpty) throw StateError('The DASH timeline contains no segments.');

      final representationId = representation.getAttribute('id') ?? candidate.index.toString();
      final bandwidth =
          int.tryParse(representation.getAttribute('bandwidth') ?? '') ?? 0;
      final initTemplate = segmentTemplate.getAttribute('initialization');
      if (initTemplate != null && initTemplate.isNotEmpty) {
        initializationUri = baseUri.resolve(_expandDashTemplate(
          initTemplate,
          representationId: representationId,
          bandwidth: bandwidth,
          number: startNumber,
          time: times.first.time,
        ));
      }
      for (var index = 0; index < times.length; index++) {
        final item = times[index];
        final url = _expandDashTemplate(
          mediaTemplate,
          representationId: representationId,
          bandwidth: bandwidth,
          number: startNumber + index,
          time: item.time,
        );
        segmentUris.add(baseUri.resolve(url));
        timeline.add(_DashTimelineItem(item.time, item.duration));
      }
    } else {
      throw StateError('DASH SegmentBase is not supported for offline downloads.');
    }

    if (segmentUris.isEmpty) {
      throw StateError('The DASH representation contains no media segments.');
    }
    return _DashPlan(
      kind: candidate.kind,
      adaptationAttributes: _selectedAttributes(adaptation, const [
        'id',
        'contentType',
        'mimeType',
        'lang',
        'segmentAlignment',
        'subsegmentAlignment',
      ]),
      representationAttributes: _selectedAttributes(representation, const [
        'id',
        'bandwidth',
        'width',
        'height',
        'codecs',
        'mimeType',
        'frameRate',
        'audioSamplingRate',
        'startWithSAP',
      ]),
      initializationUri: initializationUri,
      segmentUris: segmentUris,
      timescale: timescale,
      duration: duration,
      startNumber: startNumber,
      timeline: timeline,
    );
  }

  static List<_DashTimelineItem> _parseDashTimeline(XmlElement timeline) {
    final result = <_DashTimelineItem>[];
    var currentTime = 0;
    for (final element in timeline.childElements) {
      if (element.name.local != 'S') continue;
      final duration = int.tryParse(element.getAttribute('d') ?? '');
      if (duration == null || duration <= 0) {
        throw StateError('The DASH timeline contains an invalid segment duration.');
      }
      final repeat = int.tryParse(element.getAttribute('r') ?? '0') ?? 0;
      if (repeat < 0 || repeat > 10000) {
        throw StateError('This DASH timeline uses an unsupported repeat range.');
      }
      final explicitTime = int.tryParse(element.getAttribute('t') ?? '');
      if (explicitTime != null) currentTime = explicitTime;
      for (var index = 0; index <= repeat; index++) {
        result.add(_DashTimelineItem(currentTime, duration));
        currentTime += duration;
      }
    }
    return result;
  }

  static Uri _resolveDashBase(Uri initial, List<XmlElement> hierarchy) {
    var result = initial;
    for (final element in hierarchy) {
      final base = _findChild(element, 'BaseURL')?.innerText.trim() ?? '';
      if (base.isNotEmpty) result = result.resolve(base);
    }
    return result;
  }

  static XmlElement? _findChild(XmlElement parent, String localName) {
    for (final child in parent.childElements) {
      if (child.name.local == localName) return child;
    }
    return null;
  }

  static XmlElement? _findInheritedChild(
    List<XmlElement> hierarchy,
    String localName,
  ) {
    for (final element in hierarchy) {
      final child = _findChild(element, localName);
      if (child != null) return child;
    }
    return null;
  }

  static Map<String, String> _selectedAttributes(
    XmlElement element,
    List<String> names,
  ) {
    final result = <String, String>{};
    for (final name in names) {
      final value = element.getAttribute(name);
      if (value != null && value.isNotEmpty) result[name] = value;
    }
    return result;
  }

  static String _expandDashTemplate(
    String template, {
    required String representationId,
    required int bandwidth,
    required int number,
    required int time,
  }) {
    const marker = '\u0000';
    final escaped = template.replaceAll(r'$$', marker);
    final expanded = escaped.replaceAllMapped(
      RegExp(r'\$(RepresentationID|Bandwidth|Number|Time)(?:%0(\d+)d)?\$'),
      (match) {
        final key = match.group(1);
        final width = int.tryParse(match.group(2) ?? '') ?? 0;
        final value = switch (key) {
          'RepresentationID' => representationId,
          'Bandwidth' => bandwidth.toString(),
          'Number' => number.toString(),
          'Time' => time.toString(),
          _ => '',
        };
        return width > 0 ? value.padLeft(width, '0') : value;
      },
    );
    return expanded.replaceAll(marker, r'$');
  }

  static double? _parseIsoDuration(String value) {
    final match = RegExp(
      r'^PT(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return null;
    final hours = double.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = double.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = double.tryParse(match.group(3) ?? '0') ?? 0;
    return hours * 3600 + minutes * 60 + seconds;
  }

  static String _renderDashManifest(
    XmlElement root,
    List<_DashPlan> plans,
  ) {
    final namespace = root.name.namespaceUri ?? '';
    final rootAttributes = <String, String>{
      'xmlns': namespace.isEmpty
          ? 'urn:mpeg:dash:schema:mpd:2011'
          : namespace,
      'type': 'static',
    };
    for (final key in [
      'profiles',
      'mediaPresentationDuration',
      'minBufferTime',
      'maxSegmentDuration',
    ]) {
      final value = root.getAttribute(key);
      if (value != null && value.isNotEmpty) rootAttributes[key] = value;
    }

    final period = root.childElements.firstWhere(
      (element) => element.name.local == 'Period',
    );
    final periodAttributes = _selectedAttributes(period, ['id', 'start', 'duration']);
    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8"?>\n')
      ..write('<MPD${_attributesXml(rootAttributes)}>\n')
      ..write('<Period${_attributesXml(periodAttributes)}>\n');

    for (var index = 0; index < plans.length; index++) {
      final plan = plans[index];
      buffer
        ..write('<AdaptationSet${_attributesXml(plan.adaptationAttributes)}>\n')
        ..write(
          '<Representation${_attributesXml(plan.representationAttributes)}>\n',
        )
        ..write(
          '<SegmentList timescale="${plan.timescale}"${plan.duration == null ? '' : ' duration="${plan.duration}"'} startNumber="${plan.startNumber}">\n',
        );
      if (plan.initializationUri != null) {
        final prefix = plan.kind == 'video' ? 'video' : 'audio';
        buffer.write(
          '<Initialization sourceURL="${prefix}_init.bin"/>\n',
        );
      }
      if (plan.timeline.isNotEmpty) {
        buffer.write('<SegmentTimeline>\n');
        for (final item in plan.timeline) {
          buffer.write('<S t="${item.time}" d="${item.duration}"/>\n');
        }
        buffer.write('</SegmentTimeline>\n');
      }
      final prefix = plan.kind == 'video' ? 'video' : 'audio';
      for (var segment = 0; segment < plan.segmentUris.length; segment++) {
        buffer.write(
          '<SegmentURL media="${prefix}_segment_PLACEHOLDER"/>',
        );
        buffer.write('\n');
      }
      buffer
        ..write('</SegmentList>\n')
        ..write('</Representation>\n')
        ..write('</AdaptationSet>\n');
    }
    buffer
      ..write('</Period>\n')
      ..write('</MPD>');
    var rendered = buffer.toString();
    for (final plan in plans) {
      final prefix = plan.kind == 'video' ? 'video' : 'audio';
      for (var index = 0; index < plan.segmentUris.length; index++) {
        final placeholder = '${prefix}_segment_PLACEHOLDER';
        final fileName =
            '${prefix}_segment_${index.toString().padLeft(5, '0')}.bin';
        rendered = rendered.replaceFirst(
          '<SegmentURL media="$placeholder"/>',
          '<SegmentURL media="$fileName"/>',
        );
      }
    }
    return rendered;
  }

  static String _attributesXml(Map<String, String> attributes) {
    return attributes.entries
        .map((entry) =>
            ' ${entry.key}="${_xmlEscape(entry.value)}"')
        .join();
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static Future<int> _downloadResource(
    Uri uri,
    File target,
    CancelToken token,
  ) async {
    if (safeManifestUri(uri.toString()) == null) {
      throw StateError('A manifest contains an invalid media segment URL.');
    }
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();
    final response = await _dio.get<ResponseBody>(
      uri.toString(),
      options: Options(responseType: ResponseType.stream),
      cancelToken: token,
    );
    final status = response.statusCode ?? 0;
    if (status != 200 && status != 206) {
      throw StateError('The video host returned HTTP $status for a media segment.');
    }
    final sink = partial.openWrite();
    try {
      final stream = response.data?.stream;
      if (stream == null) throw StateError('The video host returned an empty media segment.');
      await for (final chunk in stream) {
        if (token.isCancelled) {
          throw DioException(
            requestOptions: response.requestOptions,
            type: DioExceptionType.cancel,
            message: 'Download interrupted.',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
    await sink.close();
    if (!await partial.exists() || await partial.length() == 0) {
      throw StateError('The video host returned an empty media segment.');
    }
    if (await target.exists()) await target.delete();
    await partial.rename(target.path);
    return await target.length();
  }

  static String _safeExtension(String path) {
    final match = RegExp(r'\.([A-Za-z0-9]{1,6})$').firstMatch(path);
    return match == null ? '.bin' : '.${match.group(1)!.toLowerCase()}';
  }

  static void _updateManifestProgress(DownloadTask task) {
    if (task.totalSegments <= 0) {
      task.progress = 0;
      return;
    }
    task.progress = (task.completedSegments / task.totalSegments)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static Future<int> _directorySize(Directory directory) async {
    var total = 0;
    if (!await directory.exists()) return 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File && !entity.path.endsWith('.part')) {
        total += await entity.length();
      }
    }
    return total;
  }
}

class _HlsResource {
  const _HlsResource({required this.uri, required this.fileName});
  final Uri uri;
  final String fileName;
}

class _HlsPlaylistPlan {
  const _HlsPlaylistPlan({
    required this.lines,
    required this.resources,
    required this.replacements,
  });
  final List<String> lines;
  final List<_HlsResource> resources;
  final Map<int, String> replacements;
}

class _DashResource {
  const _DashResource({required this.uri, required this.fileName});
  final Uri uri;
  final String fileName;
}

class _DashCandidate {
  const _DashCandidate({
    required this.kind,
    required this.adaptation,
    required this.representation,
    required this.index,
    required this.bandwidth,
  });
  final String kind;
  final XmlElement adaptation;
  final XmlElement representation;
  final int index;
  final int bandwidth;
}

class _DashTimelineItem {
  const _DashTimelineItem(this.time, this.duration);
  final int time;
  final int duration;
}

class _DashPlan {
  const _DashPlan({
    required this.kind,
    required this.adaptationAttributes,
    required this.representationAttributes,
    required this.initializationUri,
    required this.segmentUris,
    required this.timescale,
    required this.duration,
    required this.startNumber,
    required this.timeline,
  });
  final String kind;
  final Map<String, String> adaptationAttributes;
  final Map<String, String> representationAttributes;
  final Uri? initializationUri;
  final List<Uri> segmentUris;
  final int timescale;
  final int? duration;
  final int startNumber;
  final List<_DashTimelineItem> timeline;
}
