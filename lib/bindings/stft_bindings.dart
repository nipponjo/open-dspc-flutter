import 'dart:ffi' as ffi;

const _assetId = 'package:open_dspc/bindings/open_dspc_bindings_generated.dart';

final class yl_stft_cfg extends ffi.Struct {
  @ffi.Uint32()
  external int n_fft;

  @ffi.Uint32()
  external int win_len;

  @ffi.Uint32()
  external int hop;

  @ffi.Int()
  external int win;

  @ffi.Int()
  external int mean_subtract;

  @ffi.Int()
  external int center;
}

typedef yl_stft_handle = ffi.Pointer<ffi.Void>;

@ffi.Native<yl_stft_handle Function(ffi.Pointer<yl_stft_cfg>)>(
  assetId: _assetId,
)
external yl_stft_handle yl_stft_create(ffi.Pointer<yl_stft_cfg> cfg);

@ffi.Native<ffi.Void Function(yl_stft_handle)>(assetId: _assetId)
external void yl_stft_reset(yl_stft_handle s);

@ffi.Native<ffi.Void Function(yl_stft_handle)>(assetId: _assetId)
external void yl_stft_destroy(yl_stft_handle s);

@ffi.Native<ffi.Uint32 Function(yl_stft_handle)>(assetId: _assetId)
external int yl_stft_bins(yl_stft_handle s);

@ffi.Native<ffi.Uint32 Function(yl_stft_handle)>(assetId: _assetId)
external int yl_stft_nfft(yl_stft_handle s);

@ffi.Native<ffi.Uint32 Function(yl_stft_handle)>(assetId: _assetId)
external int yl_stft_hop(yl_stft_handle s);

@ffi.Native<ffi.Uint32 Function(yl_stft_handle)>(assetId: _assetId)
external int yl_stft_win_len(yl_stft_handle s);

@ffi.Native<
  ffi.Size Function(
    yl_stft_handle,
    ffi.Pointer<ffi.Float>,
    ffi.Size,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Size,
  )
>(assetId: _assetId)
external int yl_stft_push_r2c(
  yl_stft_handle s,
  ffi.Pointer<ffi.Float> input,
  int input_len,
  ffi.Pointer<ffi.Float> out_re,
  ffi.Pointer<ffi.Float> out_im,
  int out_frames_cap,
);

@ffi.Native<
  ffi.Size Function(
    yl_stft_handle,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Size,
  )
>(assetId: _assetId)
external int yl_stft_flush_r2c(
  yl_stft_handle s,
  ffi.Pointer<ffi.Float> out_re,
  ffi.Pointer<ffi.Float> out_im,
  int out_frames_cap,
);

@ffi.Native<
  ffi.Size Function(
    yl_stft_handle,
    ffi.Pointer<ffi.Float>,
    ffi.Size,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Size,
  )
>(assetId: _assetId)
external int yl_stft_process_r2c(
  yl_stft_handle s,
  ffi.Pointer<ffi.Float> signal,
  int signal_len,
  ffi.Pointer<ffi.Float> out_re,
  ffi.Pointer<ffi.Float> out_im,
  int out_frames_cap,
);

@ffi.Native<
  ffi.Size Function(
    yl_stft_handle,
    ffi.Pointer<ffi.Float>,
    ffi.Size,
    ffi.Pointer<ffi.Float>,
    ffi.Size,
    ffi.UnsignedInt,
    ffi.Float,
  )
>(assetId: _assetId)
external int yl_stft_push_spec(
  yl_stft_handle s,
  ffi.Pointer<ffi.Float> input,
  int input_len,
  ffi.Pointer<ffi.Float> out_bins,
  int out_frames_cap,
  int mode,
  double db_floor,
);

@ffi.Native<
  ffi.Size Function(
    yl_stft_handle,
    ffi.Pointer<ffi.Float>,
    ffi.Size,
    ffi.UnsignedInt,
    ffi.Float,
  )
>(assetId: _assetId)
external int yl_stft_flush_spec(
  yl_stft_handle s,
  ffi.Pointer<ffi.Float> out_bins,
  int out_frames_cap,
  int mode,
  double db_floor,
);

@ffi.Native<
  ffi.Size Function(
    yl_stft_handle,
    ffi.Pointer<ffi.Float>,
    ffi.Size,
    ffi.Pointer<ffi.Float>,
    ffi.Size,
    ffi.UnsignedInt,
    ffi.Float,
  )
>(assetId: _assetId)
external int yl_stft_process_spec(
  yl_stft_handle s,
  ffi.Pointer<ffi.Float> signal,
  int signal_len,
  ffi.Pointer<ffi.Float> out_bins,
  int out_frames_cap,
  int mode,
  double db_floor,
);
