/// A cloud broadcast session's status, straight from the worker's
/// `stream_sessions.status` column (spec §7.2's `stream_status_enum`) —
/// not an invented boolean, since the worker already speaks this
/// vocabulary.
class CloudStatus {
  const CloudStatus({required this.status, this.watchUrl});

  factory CloudStatus.fromJson(Map<String, dynamic> json) => CloudStatus(
    status: json['status'] as String,
    watchUrl: json['watchUrl'] as String?,
  );

  final String status;
  final String? watchUrl;

  bool get isLive => status == 'LIVE';
  bool get isActive =>
      const ['INITIALIZING', 'LIVE', 'RECONNECTING'].contains(status);
}
