// opendspc_pitch.h
#pragma once
#include "opendspc_export.h"
#include "opendspc_types.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

YL_EXPORT float yl_pitch_acf_frame(
    yl_fft_plan_handle plan_handle,
    const float* input,
    int input_len,
    float* out_acf,
    unsigned int mode,
    float sample_rate,
    float fmin, 
    float fmax
);

#ifdef __cplusplus
}
#endif