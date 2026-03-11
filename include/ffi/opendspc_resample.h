// opendspc_lpc.h
#pragma once
#include "opendspc_export.h"
#include "opendspc_types.h"
#include <stdint.h>
#include "dsp/resample.h"

#ifdef __cplusplus
extern "C" {
#endif

YL_EXPORT void* yl_resample_ctx_create(
    int orig_freq, 
    int new_freq,
    int lowpass_filter_width,
    float rolloff,
    unsigned int method,
    float beta
);

YL_EXPORT void yl_resample_ctx_destroy(void* r);

YL_EXPORT void yl_resample_reset_ffi(void* r);

YL_EXPORT int yl_resample_out_len_ffi(
    int orig_freq, 
    int new_freq, 
    int in_len
);

YL_EXPORT int yl_resample_ctx_process(
    const void* r,
    const float* in, 
    int in_len,
    float* out
);

#ifdef __cplusplus
}
#endif