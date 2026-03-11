#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

#include "dsp/fft.h" // yl_fft_plan
#include "dsp/window.h"       // yl_window_type
#include "opendspc_types.h"
#include "opendspc_export.h"        

typedef struct yl_stft_ctx yl_stft_ctx;

typedef struct {
  uint32_t n_fft;       // FFT size
  uint32_t win_len;     // window length (<= n_fft)
  uint32_t hop;         // hop size
  yl_window_type win;   // hann/hamming/blackman/rect
  int mean_subtract;    // 0/1 (optional)
  int center;           // 0/1 (optional: librosa-style centering)
} yl_stft_cfg;

YL_EXPORT yl_stft_ctx* yl_stft_create(const yl_stft_cfg* cfg);
YL_EXPORT void yl_stft_reset(yl_stft_ctx* s);
YL_EXPORT void yl_stft_destroy(yl_stft_ctx* s);

YL_EXPORT uint32_t yl_stft_bins(const yl_stft_ctx* s);   // n_fft/2+1
YL_EXPORT uint32_t yl_stft_nfft(const yl_stft_ctx* s);
YL_EXPORT uint32_t yl_stft_hop(const yl_stft_ctx* s);
YL_EXPORT uint32_t yl_stft_win_len(const yl_stft_ctx* s);

// Streaming: push arbitrary chunk; returns frames produced (<= out_frames_cap).
YL_EXPORT size_t yl_stft_push_r2c(
  yl_stft_ctx* s,
  const float* input,
  size_t input_len,
  float* out_re,             // frames * bins
  float* out_im,             // frames * bins
  size_t out_frames_cap
);

// Flush: pad with zeros until no more frames can be formed.
// Useful at end-of-stream.
YL_EXPORT size_t yl_stft_flush_r2c(
  yl_stft_ctx* s,
  float* out_re,
  float* out_im,
  size_t out_frames_cap
);

// Offline convenience: process a whole signal buffer.
// Returns frames written (<= out_frames_cap).
YL_EXPORT size_t yl_stft_process_r2c(
  yl_stft_ctx* s,
  const float* signal,
  size_t signal_len,
  float* out_re,
  float* out_im,
  size_t out_frames_cap
);

// Streaming scalar spectrum: returns magnitude, power, or dB bins directly.
YL_EXPORT size_t yl_stft_push_spec(
  yl_stft_ctx* s,
  const float* input,
  size_t input_len,
  float* out_bins,
  size_t out_frames_cap,
  yl_spec_mode mode,
  float db_floor
);

// Flush remaining samples and return scalar spectrum frames.
YL_EXPORT size_t yl_stft_flush_spec(
  yl_stft_ctx* s,
  float* out_bins,
  size_t out_frames_cap,
  yl_spec_mode mode,
  float db_floor
);

// Offline convenience for scalar spectra.
YL_EXPORT size_t yl_stft_process_spec(
  yl_stft_ctx* s,
  const float* signal,
  size_t signal_len,
  float* out_bins,
  size_t out_frames_cap,
  yl_spec_mode mode,
  float db_floor
);

#ifdef __cplusplus
}
#endif
