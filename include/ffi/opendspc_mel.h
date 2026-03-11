// opendspc_lpc.h
#pragma once
#include "opendspc_export.h"
#include "opendspc_types.h"
#include <stdint.h>
#include "feature/mel.h"

#ifdef __cplusplus
extern "C" {
#endif

YL_EXPORT void* yl_mel_ctx_create(
  int sr, int n_fft, int n_mels,
  float fmin, float fmax,
  unsigned int scale, 
  unsigned int norm
);

YL_EXPORT void yl_mel_ctx_destroy(void* m);

/* Apply filterbank to one frame of power bins (size n_bins = n_fft/2+1). */
YL_EXPORT void yl_mel_ctx_apply(
  const void* m, 
  const float* power_bins, 
  float* mel_out
);


#ifdef __cplusplus
}
#endif