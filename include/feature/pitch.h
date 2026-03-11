#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include "opendspc_types.h"
#include "dsp/fft.h"

float yl_execute_pitch_acf_frame(
    yl_fft_plan* plan,
    const float* input,
    size_t input_len,
    float* out_acf,
    yl_acf_mode mode,
    float sample_rate,
    float fmin, 
    float fmax
);

#ifdef __cplusplus
}
#endif
