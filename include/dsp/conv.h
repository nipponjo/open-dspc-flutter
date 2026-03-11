#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum yl_conv_mode {
  YL_CONV_MODE_CONV = 0,
  YL_CONV_MODE_XCORR = 1,
} yl_conv_mode;

typedef enum yl_corr_out_mode {
  YL_CORR_MODE_FULL = 0,
  YL_CORR_MODE_VALID = 1,
  YL_CORR_MODE_SAME = 2,
} yl_corr_out_mode;

typedef struct yl_fftconv_ctx yl_fftconv_ctx;

/* Full output length for linear convolution/cross-correlation. */
size_t yl_conv_out_len(size_t nx, size_t nh);
/* Output length for linear convolution/cross-correlation in requested mode. */
size_t yl_conv_out_len_mode(size_t nx, size_t nh, yl_corr_out_mode out_mode);

/* Direct O(nx * nh) full convolution/cross-correlation. */
int yl_conv_direct_f32(
    const float* x,
    size_t nx,
    const float* h,
    size_t nh,
    float* y,
    yl_conv_mode mode
);

/* Direct O(nx * nh) convolution/cross-correlation with scipy-like output modes. */
int yl_conv_direct_mode_f32(
    const float* x,
    size_t nx,
    const float* h,
    size_t nh,
    float* y,
    yl_conv_mode mode,
    yl_corr_out_mode out_mode
);

/* Same API as yl_conv_direct_mode_f32 but uses SIMD acceleration when available. */
int yl_conv_direct_mode_simd_f32(
    const float* x,
    size_t nx,
    const float* h,
    size_t nh,
    float* y,
    yl_conv_mode mode,
    yl_corr_out_mode out_mode
);

/* Output length for direct autocorrelation in requested mode. */
size_t yl_autocorr_out_len(size_t n, yl_corr_out_mode mode);

/* Direct O(n^2) autocorrelation with scipy-like output modes.
   - full:  length 2*n - 1
   - valid: length 1 (for autocorrelation)
   - same:  length n, centered with respect to full */
int yl_autocorr_direct(
    const float* x,
    size_t n,
    float* y,
    yl_corr_out_mode mode
);

/* Same API as yl_autocorr_direct but uses SIMD acceleration when available. */
int yl_autocorr_direct_simd(
    const float* x,
    size_t n,
    float* y,
    yl_corr_out_mode mode
);

/* Create an FFT convolution context for inputs up to nx_max / nh_max.
   Internally pads to the next valid real-FFT size supported by the backend. */
yl_fftconv_ctx* yl_fftconv_create_f32(size_t nx_max, size_t nh_max);

void yl_fftconv_destroy(yl_fftconv_ctx* ctx);

size_t yl_fftconv_nfft(const yl_fftconv_ctx* ctx);
size_t yl_fftconv_bins(const yl_fftconv_ctx* ctx);
size_t yl_fftconv_x_max(const yl_fftconv_ctx* ctx);
size_t yl_fftconv_h_max(const yl_fftconv_ctx* ctx);

/* Allocation-free FFT convolution/cross-correlation using the cached context.
   - nx must be <= x_max and nh <= h_max configured at create time
   - y must have length >= yl_conv_out_len(nx, nh) */
int yl_fftconv_process_f32(
    yl_fftconv_ctx* ctx,
    const float* x,
    size_t nx,
    const float* h,
    size_t nh,
    float* y,
    yl_conv_mode mode
);

#ifdef __cplusplus
}
#endif
