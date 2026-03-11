#include "opendspc_export.h"
#include "opendspc_types.h"
#include "opendspc_conv.h"
#include "dsp/conv.h"

YL_EXPORT uint32_t yl_conv_out_len_ffi(uint32_t nx, uint32_t nh) {
    return (uint32_t)yl_conv_out_len((size_t)nx, (size_t)nh);
}

YL_EXPORT uint32_t yl_conv_out_len_mode_ffi(
    uint32_t nx,
    uint32_t nh,
    unsigned int out_mode
) {
    return (uint32_t)yl_conv_out_len_mode(
        (size_t)nx,
        (size_t)nh,
        (yl_corr_out_mode)out_mode
    );
}

YL_EXPORT int yl_conv_direct_f32_ffi(
    const float* x,
    int nx,
    const float* h,
    int nh,
    float* y,
    unsigned int mode
) {
    return yl_conv_direct_f32(
        x,
        (size_t)nx,
        h,
        (size_t)nh,
        y,
        (yl_conv_mode)mode
    );
}

YL_EXPORT int yl_conv_direct_mode_f32_ffi(
    const float* x,
    int nx,
    const float* h,
    int nh,
    float* y,
    unsigned int mode,
    unsigned int out_mode
) {
    return yl_conv_direct_mode_f32(
        x,
        (size_t)nx,
        h,
        (size_t)nh,
        y,
        (yl_conv_mode)mode,
        (yl_corr_out_mode)out_mode
    );
}

YL_EXPORT int yl_conv_direct_mode_simd_f32_ffi(
    const float* x,
    int nx,
    const float* h,
    int nh,
    float* y,
    unsigned int mode,
    unsigned int out_mode
) {
    return yl_conv_direct_mode_simd_f32(
        x,
        (size_t)nx,
        h,
        (size_t)nh,
        y,
        (yl_conv_mode)mode,
        (yl_corr_out_mode)out_mode
    );
}

YL_EXPORT uint32_t yl_autocorr_out_len_ffi(uint32_t n, unsigned int mode) {
    return (uint32_t)yl_autocorr_out_len((size_t)n, (yl_corr_out_mode)mode);
}

YL_EXPORT int yl_autocorr_direct_ffi(
    const float* x,
    int n,
    float* y,
    unsigned int mode
) {
    return yl_autocorr_direct(
        x,
        (size_t)n,
        y,
        (yl_corr_out_mode)mode
    );
}

YL_EXPORT int yl_autocorr_direct_simd_ffi(
    const float* x,
    int n,
    float* y,
    unsigned int mode
) {
    return yl_autocorr_direct_simd(
        x,
        (size_t)n,
        y,
        (yl_corr_out_mode)mode
    );
}

YL_EXPORT void* yl_fftconv_ctx_create_f32(int nx_max, int nh_max) {
    return (void*)yl_fftconv_create_f32((size_t)nx_max, (size_t)nh_max);
}

YL_EXPORT void yl_fftconv_ctx_destroy(void* ctx) {
    yl_fftconv_destroy((yl_fftconv_ctx*)ctx);
}

YL_EXPORT uint32_t yl_fftconv_ctx_nfft(void* ctx) {
    return (uint32_t)yl_fftconv_nfft((const yl_fftconv_ctx*)ctx);
}

YL_EXPORT uint32_t yl_fftconv_ctx_bins(void* ctx) {
    return (uint32_t)yl_fftconv_bins((const yl_fftconv_ctx*)ctx);
}

YL_EXPORT uint32_t yl_fftconv_ctx_x_max(void* ctx) {
    return (uint32_t)yl_fftconv_x_max((const yl_fftconv_ctx*)ctx);
}

YL_EXPORT uint32_t yl_fftconv_ctx_h_max(void* ctx) {
    return (uint32_t)yl_fftconv_h_max((const yl_fftconv_ctx*)ctx);
}

YL_EXPORT int yl_fftconv_ctx_process_f32(
    void* ctx,
    const float* x,
    int nx,
    const float* h,
    int nh,
    float* y,
    unsigned int mode
) {
    return yl_fftconv_process_f32(
        (yl_fftconv_ctx*)ctx,
        x,
        (size_t)nx,
        h,
        (size_t)nh,
        y,
        (yl_conv_mode)mode
    );
}
