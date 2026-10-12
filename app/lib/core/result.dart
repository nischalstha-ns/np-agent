/// Uniform success/failure carrier used across NP core.
///
/// Every fallible operation in the agent pipeline returns [Result] instead of
/// throwing for *expected* failures (bad input, missing tool, denied
/// permission). Truly unexpected bugs still throw.
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// Returns the value, or throws the wrapped [NpError].
  T unwrap() => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>(:final error) => throw error,
      };

  T unwrapOr(T fallback) => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => fallback,
      };

  Result<U> map<U>(U Function(T value) f) => switch (this) {
        Ok<T>(:final value) => Ok(f(value)),
        Err<T>(:final error) => Err(error),
      };
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T> extends Result<T> {
  final NpError error;
  const Err(this.error);

  @override
  String toString() => 'Err($error)';
}

/// Structured error for the NP agent.
class NpError implements Exception {
  final String code;
  final String message;
  final Object? cause;

  const NpError(this.code, this.message, [this.cause]);

  factory NpError.notFound(String what) =>
      NpError('not_found', '$what not found');

  factory NpError.permission(String reason) =>
      NpError('permission_denied', reason);

  factory NpError.tool(String tool, String detail) =>
      NpError('tool_failed', 'Tool "$tool" failed: $detail');

  factory NpError.config(String detail) => NpError('config', detail);

  @override
  String toString() =>
      'NpError($code): $message${cause == null ? '' : ' | caused by $cause'}';
}
