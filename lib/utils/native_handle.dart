abstract class NativeResource {
  void free();
}

abstract class NativeHandle<R extends NativeResource> {
  R? _res;
  bool _closed = false;

  static final Finalizer<NativeResource> _finalizer = Finalizer<NativeResource>(
    (r) {
      // print("free $r");
      r.free();
    },
  );

  NativeHandle(R res) {
    _res = res;
    // token = this object; detach using the same token
    _finalizer.attach(this, res, detach: this);
  }

  /// Whether close() has been called.
  bool get isClosed => _closed;

  /// Throws if closed; returns the native resource otherwise.
  R get res {
    final r = _res;
    if (r == null) throw StateError('NativeHandle is closed');
    return r;
  }

  /// Deterministic cleanup.
  void close() {
    if (_closed) return;
    _closed = true;

    // prevent finalizer running later
    _finalizer.detach(this);

    final r = _res!;
    _res = null;
    r.free();
  }
}
