#include "opendspc_export.h"
#include "opendspc_types.h"
#include "feature/mel.h"         // internal yl_fft_plan + backend interface
#include <stdlib.h>

YL_EXPORT void* yl_mel_ctx_create(
  int sr, int n_fft, int n_mels,
  float fmin, float fmax,
  unsigned int scale, 
  unsigned int norm
) {
    return (yl_mel_ctx*)yl_mel_create(
        sr, n_fft, n_mels,
        fmin, fmax,
        (yl_mel_scale)scale,
        (yl_mel_norm)norm);
}

YL_EXPORT void yl_mel_ctx_destroy(void* m) {
    yl_mel_destroy((yl_mel_ctx*)m);
}

/* Apply filterbank to one frame of power bins (size n_bins = n_fft/2+1). */
YL_EXPORT void yl_mel_ctx_apply(
  const void* m, 
  const float* power_bins, 
  float* mel_out
) {
    yl_mel_apply((yl_mel_ctx*)m, power_bins, mel_out);
}

