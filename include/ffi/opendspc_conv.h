#pragma once
#include "opendspc_export.h"
#include "opendspc_types.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

YL_EXPORT uint32_t yl_conv_out_len_ffi(uint32_t nx, uint32_t nh);
YL_EXPORT uint32_t yl_conv_out_len_mode_ffi(
    uint32_t nx,
    uint32_t nh,
    unsigned int out_mode
);

YL_EXPORT int yl_conv_direct_f32_ffi(
    const float* x,
    int nx,
    const float* h,
    int nh,
    float* y,
    unsigned int mode
);

YL_EXPORT int yl_conv_direct_mode_f32_ffi(
    const float* x,
    int nx,
    const float* h,
    int nh,
    float* y,
    unsigned int mode,
    unsigned int out_mode
);

YL_EXPORT int yl_conv_direct_mode_simd_f32_ffi(
    const float* x,
    int nx,
    const float* h,
    int nh,
    float* y,
    unsigned int mode,
    unsigned int out_mode
);

YL_EXPORT uint32_t yl_autocorr_out_len_ffi(uint32_t n, unsigned int mode);

YL_EXPORT int yl_autocorr_direct_ffi(
    const float* x,
    int n,
    float* y,
    unsigned int mode
);

YL_EXPORT int yl_autocorr_direct_simd_ffi(
    const float* x,
    int n,
    float* y,
    unsigned int mode
);

YL_EXPORT void* yl_fftconv_ctx_create_f32(int nx_max, int nh_max);
YL_EXPORT void yl_fftconv_ctx_destroy(void* ctx);

YL_EXPORT uint32_t yl_fftconv_ctx_nfft(void* ctx);
YL_EXPORT uint32_t yl_fftconv_ctx_bins(void* ctx);
YL_EXPORT uint32_t yl_fftconv_ctx_x_max(void* ctx);
YL_EXPORT uint32_t yl_fftconv_ctx_h_max(void* ctx);

YL_EXPORT int yl_fftconv_ctx_process_f32(
    void* ctx,
    const float* x,
    int nx,
    const float* h,
    int nh,
    float* y,
    unsigned int mode
);

#ifdef __cplusplus
}
#endif
