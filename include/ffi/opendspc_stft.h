#pragma once
#include "opendspc_export.h"
#include "opendspc_types.h"
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  uint32_t n_fft;
  uint32_t win_len;
  uint32_t hop;
  yl_window_type win;
  int mean_subtract;
  int center;
} yl_stft_cfg;

typedef void* yl_stft_handle;

YL_EXPORT yl_stft_handle yl_stft_create(const yl_stft_cfg* cfg);
YL_EXPORT void yl_stft_reset(yl_stft_handle s);
YL_EXPORT void yl_stft_destroy(yl_stft_handle s);

YL_EXPORT uint32_t yl_stft_bins(yl_stft_handle s);
YL_EXPORT uint32_t yl_stft_nfft(yl_stft_handle s);
YL_EXPORT uint32_t yl_stft_hop(yl_stft_handle s);
YL_EXPORT uint32_t yl_stft_win_len(yl_stft_handle s);

YL_EXPORT size_t yl_stft_push_r2c(
  yl_stft_handle s,
  const float* input,
  size_t input_len,
  float* out_re,
  float* out_im,
  size_t out_frames_cap
);

YL_EXPORT size_t yl_stft_flush_r2c(
  yl_stft_handle s,
  float* out_re,
  float* out_im,
  size_t out_frames_cap
);

YL_EXPORT size_t yl_stft_process_r2c(
  yl_stft_handle s,
  const float* signal,
  size_t signal_len,
  float* out_re,
  float* out_im,
  size_t out_frames_cap
);

YL_EXPORT size_t yl_stft_push_spec(
  yl_stft_handle s,
  const float* input,
  size_t input_len,
  float* out_bins,
  size_t out_frames_cap,
  unsigned int mode,
  float db_floor
);

YL_EXPORT size_t yl_stft_flush_spec(
  yl_stft_handle s,
  float* out_bins,
  size_t out_frames_cap,
  unsigned int mode,
  float db_floor
);

YL_EXPORT size_t yl_stft_process_spec(
  yl_stft_handle s,
  const float* signal,
  size_t signal_len,
  float* out_bins,
  size_t out_frames_cap,
  unsigned int mode,
  float db_floor
);

#ifdef __cplusplus
}
#endif
