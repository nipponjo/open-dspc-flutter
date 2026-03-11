#include "opendspc_export.h"
#include "opendspc_types.h"
#include "opendspc_fft.h"     // public prototypes
#include "dsp/fft.h"         // internal yl_fft_plan + backend interface
#include <stdlib.h>

YL_EXPORT void yl_fft_forward(
    float* input,
    int length,
    float* out_real,
    float* out_imag
) {
    yl_fft_plan* p = yl_fft_create_r2c((size_t)length);
    if (!p) return;
    yl_fft_execute_r2c(p, input, out_real, out_imag);
    yl_fft_destroy(p);
}

YL_EXPORT void yl_fft_inverse(
    float* in_real,
    float* in_imag,
    int length,
    float* output
) {
    yl_fft_plan* p = yl_fft_create_c2r((size_t)length);
    if (!p) return;
    yl_fft_execute_c2r(p, in_real, in_imag, output);
    yl_fft_destroy(p);
}

YL_EXPORT void yl_fft_complex_forward(
    float* in_real,
    float* in_imag,
    int length,
    float* out_real,
    float* out_imag
) {
    yl_fft_plan* p = yl_fft_create_c2c((size_t)length);
    if (!p) return;
    yl_fft_execute_c2c_forward(p, in_real, in_imag, out_real, out_imag);
    yl_fft_destroy(p);
}

YL_EXPORT void yl_fft_complex_inverse(
    float* in_real,
    float* in_imag,
    int length,
    float* out_real,
    float* out_imag
) {
    yl_fft_plan* p = yl_fft_create_c2c((size_t)length);
    if (!p) return;
    yl_fft_execute_c2c_backward(p, in_real, in_imag, out_real, out_imag);
    yl_fft_destroy(p);
}

YL_EXPORT void yl_fft_spec(
    float* input,
    int length,  
    float* out_bins,
    unsigned int mode,
    float db_floor
) {
    yl_fft_plan* p = yl_fft_create_r2c((size_t)length);
    if (!p) return;
    yl_fft_execute_r2c_spec(p, input, out_bins, (yl_spec_mode)mode, db_floor);
    yl_fft_destroy(p);
}

// plan based
YL_EXPORT yl_fft_plan* yl_fft_plan_r2c(int length) {
    return yl_fft_create_r2c((size_t)length);
}

YL_EXPORT uint32_t yl_rfft_bins(uint32_t n) {
    return (n / 2u) + 1u;
}

YL_EXPORT yl_fft_plan_handle yl_fft_plan_r2c_create(int n) {
    yl_fft_plan* p = yl_fft_create_r2c((size_t)n);
    return (yl_fft_plan_handle)p;
}

YL_EXPORT yl_fft_plan_handle yl_fft_plan_c2r_create(int n) {
    yl_fft_plan* p = yl_fft_create_c2r((size_t)n);
    return (yl_fft_plan_handle)p;
}

YL_EXPORT yl_fft_plan_handle yl_fft_plan_c2c_create(int n) {
    yl_fft_plan* p = yl_fft_create_c2c((size_t)n);
    return (yl_fft_plan_handle)p;
}

YL_EXPORT void yl_fft_plan_destroy(yl_fft_plan_handle plan) {
    yl_fft_plan* p = (yl_fft_plan*)plan;
    yl_fft_destroy(p);
}

// YL_EXPORT uint32_t yl_fft_plan_length(yl_fft_plan_handle plan) {
//     yl_fft_plan* p = (yl_fft_plan*)plan;
//     return p ? (uint32_t)p->n : 0u;
// }

YL_EXPORT void yl_fft_plan_execute_r2c(
    yl_fft_plan_handle plan,
    const float* input,
    float* out_real,
    float* out_imag
) {
    yl_fft_plan* p = (yl_fft_plan*)plan;
    if (!p) return;
    yl_fft_execute_r2c(p, input, out_real, out_imag);
}

YL_EXPORT void yl_fft_plan_execute_c2r(
    yl_fft_plan_handle plan,
    const float* in_real,
    const float* in_imag,
    float* output
) {
    yl_fft_plan* p = (yl_fft_plan*)plan;
    if (!p) return;
    yl_fft_execute_c2r(p, in_real, in_imag, output);
}

YL_EXPORT void yl_fft_plan_execute_c2c_forward(
    yl_fft_plan_handle plan,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
    yl_fft_plan* p = (yl_fft_plan*)plan;
    if (!p) return;
    yl_fft_execute_c2c_forward(p, in_real, in_imag, out_real, out_imag);
}

YL_EXPORT void yl_fft_plan_execute_c2c_backward(
    yl_fft_plan_handle plan,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
    yl_fft_plan* p = (yl_fft_plan*)plan;
    if (!p) return;
    yl_fft_execute_c2c_backward(p, in_real, in_imag, out_real, out_imag);
}

YL_EXPORT void yl_fft_plan_execute_r2c_spec(
    yl_fft_plan_handle plan,
    const float* input,
    float* out_bins,      // length n/2+1
    unsigned int mode,
    float db_floor        // e.g. -120.0f (used only for DB)
) {
    yl_fft_plan* p = (yl_fft_plan*)plan;
    if (!p) return;
    yl_fft_execute_r2c_spec(p, input, out_bins, (yl_spec_mode)mode, db_floor);
}

YL_EXPORT void yl_fft_autocorr(
    void* plan_handle,
    const float* input,
    int input_len,
    float* out_acf,
    int out_len,
    unsigned int mode
) {
    yl_fft_plan* p = (yl_fft_plan*)plan_handle;
    if (!p) return;
    yl_fft_execute_autocorr(p, input, (size_t)input_len, out_acf, (size_t)out_len, (yl_acf_mode)mode);
}
