/// A cloud broadcast session's status, straight from the worker's
/// `stream_sessions.status` column (spec §7.2's `stream_status_enum`) —
/// not an invented boolean, since the worker already speaks this
/// vocabulary.
class CloudStatus {
  const CloudStatus({required this.status});

  factory CloudStatus.fromJson(Map<String, dynamic> json) =>
      CloudStatus(status: json['status'] as String);

  final String status;

  bool get isLive => status == 'LIVE';
}
