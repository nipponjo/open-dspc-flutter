// opendspc_fft.h
#pragma once
#include "opendspc_export.h"
#include "opendspc_types.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif


YL_EXPORT yl_fft_plan_handle yl_fft_plan_r2c_create(int n);
YL_EXPORT yl_fft_plan_handle yl_fft_plan_c2r_create(int n);
YL_EXPORT yl_fft_plan_handle yl_fft_plan_c2c_create(int n);
YL_EXPORT void yl_fft_plan_destroy(yl_fft_plan_handle plan);

YL_EXPORT uint32_t yl_fft_plan_length(yl_fft_plan_handle plan);

// RFFT: out_real/out_imag length = n/2 + 1
YL_EXPORT void yl_fft_plan_execute_r2c(
    yl_fft_plan_handle plan,
    const float* input,      // length n
    float* out_real,         // length n/2+1
    float* out_imag          // length n/2+1
);

// IRFFT: in_real/in_imag length = n/2 + 1, output length = n
YL_EXPORT void yl_fft_plan_execute_c2r(
    yl_fft_plan_handle plan,
    const float* in_real,    // length n/2+1
    const float* in_imag,    // length n/2+1
    float* output            // length n
);

YL_EXPORT void yl_fft_plan_execute_c2c_forward(
    yl_fft_plan_handle plan,
    const float* in_real,    // length n
    const float* in_imag,    // length n
    float* out_real,         // length n
    float* out_imag          // length n
);

YL_EXPORT void yl_fft_plan_execute_c2c_backward(
    yl_fft_plan_handle plan,
    const float* in_real,    // length n
    const float* in_imag,    // length n
    float* out_real,         // length n
    float* out_imag          // length n
);

// RFFT->abs/pow/db: out_bins length = n/2 + 1
YL_EXPORT void yl_fft_plan_execute_r2c_spec(
    yl_fft_plan_handle plan,
    const float* input,
    float* out_bins,      // length n/2+1
    unsigned int mode,
    float db_floor        // e.g. -120.0f (used only for DB)
);

YL_EXPORT void yl_fft_autocorr(
    void* plan_handle,
    const float* input,
    int input_len,
    float* out_acf,
    int out_len,
    unsigned int mode
);

YL_EXPORT uint32_t yl_rfft_bins(uint32_t n);

YL_EXPORT void yl_fft_forward(
    float* input,
    int length,
    float* out_real,
    float* out_imag
);

YL_EXPORT void yl_fft_inverse(
    float* in_real,
    float* in_imag,
    int length,
    float* output
);

YL_EXPORT void yl_fft_complex_forward(
    float* in_real,
    float* in_imag,
    int length,
    float* out_real,
    float* out_imag
);

YL_EXPORT void yl_fft_complex_inverse(
    float* in_real,
    float* in_imag,
    int length,
    float* out_real,
    float* out_imag
);

YL_EXPORT void yl_fft_spec(
    float* input,
    int length,  
    float* out_bins,
    unsigned int mode,
    float db_floor
);

#ifdef __cplusplus
}
#endif
