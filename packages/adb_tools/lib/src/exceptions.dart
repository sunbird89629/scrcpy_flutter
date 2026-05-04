/// Exception thrown when an ADB command or operation fails.
class AdbException implements Exception {
  /// Creates a new [AdbException] with the given [message].
  const AdbException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'AdbException: $message';
}
