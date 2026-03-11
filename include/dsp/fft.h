#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>

#include "dsp/window.h"
#include "ffi/opendspc_types.h"

typedef struct yl_fft_plan yl_fft_plan;

/* Create plan for real->complex FFT */
yl_fft_plan* yl_fft_create_r2c(size_t n);

/* Create plan for complex->real IFFT */
yl_fft_plan* yl_fft_create_c2r(size_t n);

/* Create plan for complex->complex FFT/IFFT */
yl_fft_plan* yl_fft_create_c2c(size_t n);

/* Execute forward FFT (real → complex) */
void yl_fft_execute_r2c(
    yl_fft_plan* plan,
    const float* input,
    float* out_real,
    float* out_imag
);

/* Execute inverse FFT (complex → real) */
void yl_fft_execute_c2r(
    yl_fft_plan* plan,
    const float* in_real,
    const float* in_imag,
    float* output
);

/* Execute forward FFT (complex → complex) */
void yl_fft_execute_c2c_forward(
    yl_fft_plan* plan,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
);

/* Execute inverse FFT (complex → complex) */
void yl_fft_execute_c2c_backward(
    yl_fft_plan* plan,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
);

void yl_fft_execute_r2c_spec(
    yl_fft_plan* plan,
    const float* input,
    float* out_bins,      // length n/2+1
    yl_spec_mode mode,
    float db_floor        // e.g. -120.0f (used only for DB)
);

typedef struct yl_fft_backend yl_fft_backend;

// Existing API
yl_fft_backend* yl_fft_backend_create_r2c(size_t n);
yl_fft_backend* yl_fft_backend_create_c2r(size_t n);
yl_fft_backend* yl_fft_backend_create_c2c(size_t n);
size_t yl_fft_backend_next_valid_size(size_t n, int complex_transform);

void yl_fft_backend_execute_r2c(
    yl_fft_backend* b,
    const float* input,
    float* out_real,
    float* out_imag
);

void yl_fft_backend_execute_c2r(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* output
);

void yl_fft_backend_execute_c2c_forward(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
);

void yl_fft_backend_execute_c2c_backward(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
);

void yl_fft_backend_destroy(yl_fft_backend* b);

// New spectral API
size_t yl_fft_backend_bins(const yl_fft_backend* b);

void yl_fft_backend_execute_r2c_spec(
    yl_fft_backend* b,
    const float* input,
    float* out_bins,
    yl_spec_mode mode,
    float db_floor
);


void yl_fft_backend_execute_autocorr(
    yl_fft_backend* b,
    const float* input,
    size_t input_len,
    float* out_acf,
    size_t out_len,
    yl_acf_mode mode
);


// Plan-level API (FFI-safe wrapper can call this)
void yl_fft_execute_autocorr(
    yl_fft_plan* plan,
    const float* input,      // length <= plan->n (typically frame_len <= n/2)
    size_t input_len,
    float* out_acf,          // length out_len
    size_t out_len,
    yl_acf_mode mode
);

/* Destroy plan */
void yl_fft_destroy(yl_fft_plan* plan);

#ifdef __cplusplus
}
#endif
