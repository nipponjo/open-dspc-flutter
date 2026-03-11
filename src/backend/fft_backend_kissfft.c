#include <float.h>
#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "third_party/kissfft/kiss_fft.h"
#include "third_party/kissfft/kiss_fftr.h"

#include "dsp/fft.h"

#ifndef YL_DB_EPS
#define YL_DB_EPS 1e-20f
#endif

typedef struct yl_fft_backend {
    int n;
    int kind;       /* 1 = real, 2 = complex */
    int is_inverse; /* real plan flavor: 0 = r2c, 1 = c2r */

    kiss_fftr_cfg real_forward_cfg;
    kiss_fftr_cfg real_inverse_cfg;
    kiss_fft_cfg complex_forward_cfg;
    kiss_fft_cfg complex_inverse_cfg;

    float* real_time;
    kiss_fft_cpx* real_spec;
    kiss_fft_cpx* complex_time;
    kiss_fft_cpx* complex_spec;
} yl_fft_backend;

enum {
    YL_KISSFFT_KIND_REAL = 1,
    YL_KISSFFT_KIND_COMPLEX = 2,
};

static inline float yl_pow2(float x) {
    return x * x;
}

static yl_fft_backend* yl_fft_backend_alloc(int n, int kind, int inverse) {
    yl_fft_backend* b;

    if (n <= 0) return NULL;
    if (kind == YL_KISSFFT_KIND_REAL && (n & 1) != 0) return NULL;

    b = (yl_fft_backend*)malloc(sizeof(yl_fft_backend));
    if (!b) return NULL;

    b->n = n;
    b->kind = kind;
    b->is_inverse = inverse ? 1 : 0;
    b->real_forward_cfg = NULL;
    b->real_inverse_cfg = NULL;
    b->complex_forward_cfg = NULL;
    b->complex_inverse_cfg = NULL;
    b->real_time = NULL;
    b->real_spec = NULL;
    b->complex_time = NULL;
    b->complex_spec = NULL;

    if (kind == YL_KISSFFT_KIND_REAL) {
        b->real_forward_cfg = kiss_fftr_alloc(n, 0, NULL, NULL);
        b->real_inverse_cfg = kiss_fftr_alloc(n, 1, NULL, NULL);
        if (!b->real_forward_cfg || !b->real_inverse_cfg) {
            kiss_fftr_free(b->real_forward_cfg);
            kiss_fftr_free(b->real_inverse_cfg);
            free(b);
            return NULL;
        }

        b->real_time = (float*)malloc((size_t)n * sizeof(float));
        b->real_spec = (kiss_fft_cpx*)malloc((size_t)(n / 2 + 1) * sizeof(kiss_fft_cpx));
        if (!b->real_time || !b->real_spec) {
            kiss_fftr_free(b->real_forward_cfg);
            kiss_fftr_free(b->real_inverse_cfg);
            free(b->real_time);
            free(b->real_spec);
            free(b);
            return NULL;
        }
    } else {
        b->complex_forward_cfg = kiss_fft_alloc(n, 0, NULL, NULL);
        b->complex_inverse_cfg = kiss_fft_alloc(n, 1, NULL, NULL);
        if (!b->complex_forward_cfg || !b->complex_inverse_cfg) {
            kiss_fft_free(b->complex_forward_cfg);
            kiss_fft_free(b->complex_inverse_cfg);
            free(b);
            return NULL;
        }

        b->complex_time = (kiss_fft_cpx*)malloc((size_t)n * sizeof(kiss_fft_cpx));
        b->complex_spec = (kiss_fft_cpx*)malloc((size_t)n * sizeof(kiss_fft_cpx));
        if (!b->complex_time || !b->complex_spec) {
            kiss_fft_free(b->complex_forward_cfg);
            kiss_fft_free(b->complex_inverse_cfg);
            free(b->complex_time);
            free(b->complex_spec);
            free(b);
            return NULL;
        }
    }

    return b;
}

/* Create a real-to-complex backend plan for an even-length real transform. */
yl_fft_backend* yl_fft_backend_create_r2c(size_t n) {
    if (n > (size_t)INT_MAX) return NULL;
    return yl_fft_backend_alloc((int)n, YL_KISSFFT_KIND_REAL, 0);
}

/* Create a complex-to-real backend plan for an even-length inverse real transform. */
yl_fft_backend* yl_fft_backend_create_c2r(size_t n) {
    if (n > (size_t)INT_MAX) return NULL;
    return yl_fft_backend_alloc((int)n, YL_KISSFFT_KIND_REAL, 1);
}

/* Create a complex-to-complex backend plan with forward and inverse configs. */
yl_fft_backend* yl_fft_backend_create_c2c(size_t n) {
    if (n > (size_t)INT_MAX) return NULL;
    return yl_fft_backend_alloc((int)n, YL_KISSFFT_KIND_COMPLEX, 0);
}

/* Return the next KISS FFT size supported by the selected transform type. */
size_t yl_fft_backend_next_valid_size(size_t n, int complex_transform) {
    int next;

    if (n == 0 || n > (size_t)INT_MAX) return 0;

    next = complex_transform
        ? kiss_fft_next_fast_size((int)n)
        : kiss_fftr_next_fast_size_real((int)n);

    return next > 0 ? (size_t)next : 0;
}

/* Execute a forward real FFT and unpack the result into split real/imag arrays. */
void yl_fft_backend_execute_r2c(
    yl_fft_backend* b,
    const float* input,
    float* out_real,
    float* out_imag
) {
    int k;
    int nh;

    if (!b || b->kind != YL_KISSFFT_KIND_REAL || b->is_inverse) return;
    if (!input || !out_real || !out_imag) return;

    nh = b->n / 2;
    memcpy(b->real_time, input, (size_t)b->n * sizeof(float));
    kiss_fftr(b->real_forward_cfg, b->real_time, b->real_spec);

    for (k = 0; k <= nh; ++k) {
        out_real[k] = b->real_spec[k].r;
        out_imag[k] = b->real_spec[k].i;
    }
}

/* Return the number of non-redundant bins in a real FFT output. */
size_t yl_fft_backend_bins(const yl_fft_backend* b) {
    return b ? (size_t)(b->n / 2 + 1) : 0;
}

/* Compute magnitude, power, or dB bins from a real-input forward transform. */
void yl_fft_backend_execute_r2c_spec(
    yl_fft_backend* b,
    const float* input,
    float* out_bins,
    yl_spec_mode mode,
    float db_floor
) {
    int k;
    int nh;

    if (!b || b->kind != YL_KISSFFT_KIND_REAL || b->is_inverse) return;
    if (!input || !out_bins) return;

    nh = b->n / 2;
    memcpy(b->real_time, input, (size_t)b->n * sizeof(float));
    kiss_fftr(b->real_forward_cfg, b->real_time, b->real_spec);

    if (mode == YL_SPEC_POWER) {
        for (k = 0; k <= nh; ++k) {
            const float re = b->real_spec[k].r;
            const float im = b->real_spec[k].i;
            out_bins[k] = yl_pow2(re) + yl_pow2(im);
        }
        return;
    }

    if (mode == YL_SPEC_DB) {
        for (k = 0; k <= nh; ++k) {
            const float re = b->real_spec[k].r;
            const float im = b->real_spec[k].i;
            float db = 10.0f * log10f(yl_pow2(re) + yl_pow2(im) + YL_DB_EPS);
            if (db < db_floor) db = db_floor;
            out_bins[k] = db;
        }
        return;
    }

    for (k = 0; k <= nh; ++k) {
        const float re = b->real_spec[k].r;
        const float im = b->real_spec[k].i;
        out_bins[k] = sqrtf(yl_pow2(re) + yl_pow2(im));
    }
}

/* Estimate autocorrelation through FFT power spectrum and inverse real transform. */
void yl_fft_backend_execute_autocorr(
    yl_fft_backend* b,
    const float* input,
    size_t input_len,
    float* out_acf,
    size_t out_len,
    yl_acf_mode mode
) {
    int k;
    int nh;
    float inv_n;

    if (!b || b->kind != YL_KISSFFT_KIND_REAL) return;
    if (!input || !out_acf) return;
    if (input_len > (size_t)b->n) return;

    if (out_len > (size_t)b->n) out_len = (size_t)b->n;

    memcpy(b->real_time, input, input_len * sizeof(float));
    if (input_len < (size_t)b->n) {
        memset(b->real_time + input_len, 0, ((size_t)b->n - input_len) * sizeof(float));
    }

    nh = b->n / 2;
    kiss_fftr(b->real_forward_cfg, b->real_time, b->real_spec);

    for (k = 0; k <= nh; ++k) {
        const float re = b->real_spec[k].r;
        const float im = b->real_spec[k].i;
        b->real_spec[k].r = yl_pow2(re) + yl_pow2(im);
        b->real_spec[k].i = 0.0f;
    }

    kiss_fftri(b->real_inverse_cfg, b->real_spec, b->real_time);

    inv_n = 1.0f / (float)b->n;
    if (mode == YL_ACF_NORM_R0) {
        const float r0 = b->real_time[0] * inv_n;
        const float inv_r0 = (fabsf(r0) > FLT_EPSILON) ? (1.0f / r0) : 0.0f;
        size_t i;
        for (i = 0; i < out_len; ++i) {
            out_acf[i] = (b->real_time[i] * inv_n) * inv_r0;
        }
        return;
    }

    {
        size_t i;
        for (i = 0; i < out_len; ++i) {
            out_acf[i] = b->real_time[i] * inv_n;
        }
    }
}

/* Execute an inverse real FFT from split-spectrum input and normalize by N. */
void yl_fft_backend_execute_c2r(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* output
) {
    int k;
    int nh;
    float inv_n;

    if (!b || b->kind != YL_KISSFFT_KIND_REAL || !b->is_inverse) return;
    if (!in_real || !in_imag || !output) return;

    inv_n = 1.0f / (float)b->n;
    nh = b->n / 2;
    for (k = 0; k <= nh; ++k) {
        b->real_spec[k].r = in_real[k];
        b->real_spec[k].i = in_imag[k];
    }

    kiss_fftri(b->real_inverse_cfg, b->real_spec, b->real_time);

    for (k = 0; k < b->n; ++k) {
        output[k] = b->real_time[k] * inv_n;
    }
}

/* Execute a forward complex FFT into split real/imag output arrays. */
void yl_fft_backend_execute_c2c_forward(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
    int k;

    if (!b || b->kind != YL_KISSFFT_KIND_COMPLEX) return;
    if (!in_real || !in_imag || !out_real || !out_imag) return;

    for (k = 0; k < b->n; ++k) {
        b->complex_time[k].r = in_real[k];
        b->complex_time[k].i = in_imag[k];
    }

    kiss_fft(b->complex_forward_cfg, b->complex_time, b->complex_spec);

    for (k = 0; k < b->n; ++k) {
        out_real[k] = b->complex_spec[k].r;
        out_imag[k] = b->complex_spec[k].i;
    }
}

/* Execute an inverse complex FFT and normalize the complex output by N. */
void yl_fft_backend_execute_c2c_backward(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
    int k;
    float inv_n;

    if (!b || b->kind != YL_KISSFFT_KIND_COMPLEX) return;
    if (!in_real || !in_imag || !out_real || !out_imag) return;

    inv_n = 1.0f / (float)b->n;
    for (k = 0; k < b->n; ++k) {
        b->complex_spec[k].r = in_real[k];
        b->complex_spec[k].i = in_imag[k];
    }

    kiss_fft(b->complex_inverse_cfg, b->complex_spec, b->complex_time);

    for (k = 0; k < b->n; ++k) {
        out_real[k] = b->complex_time[k].r * inv_n;
        out_imag[k] = b->complex_time[k].i * inv_n;
    }
}

/* Release KISS FFT configs and scratch buffers owned by the backend. */
void yl_fft_backend_destroy(yl_fft_backend* b) {
    if (!b) return;

    kiss_fftr_free(b->real_forward_cfg);
    kiss_fftr_free(b->real_inverse_cfg);
    kiss_fft_free(b->complex_forward_cfg);
    kiss_fft_free(b->complex_inverse_cfg);

    free(b->real_time);
    free(b->real_spec);
    free(b->complex_time);
    free(b->complex_spec);
    free(b);
}
