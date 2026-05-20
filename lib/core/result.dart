sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.message, {this.cause});
  final String message;
  final Object? cause;
}

extension ResultX<T> on Result<T> {
  bool get isOk => this is Ok<T>;

  R fold<R>({
    required R Function(T value) ok,
    required R Function(String message) err,
  }) =>
      switch (this) {
        Ok(:final value) => ok(value),
        Err(:final message) => err(message),
      };
}
