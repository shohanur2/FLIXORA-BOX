int _toInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class DownloadTask {
  DownloadTask({
    required this.movieId,
    required this.title,
    required this.poster,
    this.videoUrl = '',
    this.quality = 'Original',
    String? taskId,
    this.tmdbId = 0,
    this.mediaType = 'movie',
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle = '',
    this.progress = 0,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.status = 'Waiting',
    this.filePath,
    this.partialPath,
    this.errorMessage,
  }) : taskId = taskId ??
            DateTime.now().microsecondsSinceEpoch.toString();

  final String taskId;
  final int movieId;
  final int tmdbId;
  final String title;
  final String poster;
  final String videoUrl;
  final String quality;
  final String mediaType;
  final int? seasonNumber;
  final int? episodeNumber;
  final String episodeTitle;
  double progress;
  int bytesReceived;
  int totalBytes;
  String status;
  String? filePath;
  String? partialPath;
  String? errorMessage;

  bool get isCompleted => status == 'Completed';

  String get displayTitle {
    if (episodeNumber == null) return title;
    final season = (seasonNumber ?? 1).toString().padLeft(2, '0');
    final episode = episodeNumber!.toString().padLeft(2, '0');
    final suffix = episodeTitle.trim().isEmpty ? '' : ' • $episodeTitle';
    return '$title • S$season E$episode$suffix';
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'movieId': movieId,
        'tmdbId': tmdbId,
        'title': title,
        'poster': poster,
        'videoUrl': videoUrl,
        'quality': quality,
        'mediaType': mediaType,
        'seasonNumber': seasonNumber,
        'episodeNumber': episodeNumber,
        'episodeTitle': episodeTitle,
        'progress': progress,
        'bytesReceived': bytesReceived,
        'totalBytes': totalBytes,
        'status': status,
        'filePath': filePath,
        'partialPath': partialPath,
        'errorMessage': errorMessage,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    final movieId = _toInt(json['movieId']);
    final quality = (json['quality'] ?? 'Original').toString();
    final oldId = 'legacy_${movieId}_${quality.hashCode}';
    return DownloadTask(
      taskId: (json['taskId'] ?? oldId).toString(),
      movieId: movieId,
      tmdbId: _toInt(json['tmdbId']),
      title: (json['title'] ?? 'Downloaded Video').toString(),
      poster: (json['poster'] ?? '').toString(),
      videoUrl: (json['videoUrl'] ?? '').toString(),
      quality: quality,
      mediaType: (json['mediaType'] ?? 'movie').toString(),
      seasonNumber: json['seasonNumber'] == null
          ? null
          : _toInt(json['seasonNumber']),
      episodeNumber: json['episodeNumber'] == null
          ? null
          : _toInt(json['episodeNumber']),
      episodeTitle: (json['episodeTitle'] ?? '').toString(),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      bytesReceived: _toInt(json['bytesReceived']),
      totalBytes: _toInt(json['totalBytes']),
      status: (json['status'] ?? 'Completed').toString(),
      filePath: json['filePath']?.toString(),
      partialPath: json['partialPath']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}
