#include <float.h>
#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "third_party/pocketfft-c/pocketfft_f32.h"

#include "dsp/fft.h"

#ifndef YL_DB_EPS
#define YL_DB_EPS 1e-20f
#endif

typedef struct yl_fft_backend {
    int n;
    int kind;       /* 1 = real, 2 = complex */
    int is_inverse; /* real plan flavor: 0 = r2c, 1 = c2r */

    rfft_plan_f32 rplan;
    cfft_plan_f32 cplan;

    float* rbuf; /* length n */
    float* cbuf; /* length 2*n (interleaved complex) */
} yl_fft_backend;

enum {
    YL_POCKETFFT_C_KIND_REAL = 1,
    YL_POCKETFFT_C_KIND_COMPLEX = 2,
};

static inline float yl_pow2(float x) {
    return x * x;
}

static yl_fft_backend* yl_fft_backend_alloc(int n, int kind, int inverse) {
    yl_fft_backend* b = NULL;
    if (n <= 0) return NULL;

    b = (yl_fft_backend*)malloc(sizeof(yl_fft_backend));
    if (!b) return NULL;

    b->n = n;
    b->kind = kind;
    b->is_inverse = inverse ? 1 : 0;
    b->rplan = NULL;
    b->cplan = NULL;
    b->rbuf = NULL;
    b->cbuf = NULL;

    if (kind == YL_POCKETFFT_C_KIND_REAL) {
        b->rplan = make_rfft_plan_f32((size_t)n);
        if (!b->rplan) {
            free(b);
            return NULL;
        }
        b->rbuf = (float*)malloc((size_t)n * sizeof(float));
        if (!b->rbuf) {
            destroy_rfft_plan_f32(b->rplan);
            free(b);
            return NULL;
        }
    } else {
        b->cplan = make_cfft_plan_f32((size_t)n);
        if (!b->cplan) {
            free(b);
            return NULL;
        }
        b->cbuf = (float*)malloc((size_t)(2 * n) * sizeof(float));
        if (!b->cbuf) {
            destroy_cfft_plan_f32(b->cplan);
            free(b);
            return NULL;
        }
    }

    return b;
}

/* Create a real-to-complex backend plan. */
yl_fft_backend* yl_fft_backend_create_r2c(size_t n) {
    if (n > (size_t)INT_MAX) return NULL;
    return yl_fft_backend_alloc((int)n, YL_POCKETFFT_C_KIND_REAL, 0);
}

/* Create a complex-to-real backend plan. */
yl_fft_backend* yl_fft_backend_create_c2r(size_t n) {
    if (n > (size_t)INT_MAX) return NULL;
    return yl_fft_backend_alloc((int)n, YL_POCKETFFT_C_KIND_REAL, 1);
}

/* Create a complex-to-complex backend plan. */
yl_fft_backend* yl_fft_backend_create_c2c(size_t n) {
    if (n > (size_t)INT_MAX) return NULL;
    return yl_fft_backend_alloc((int)n, YL_POCKETFFT_C_KIND_COMPLEX, 0);
}

/* pocketfft-c supports all positive sizes. */
size_t yl_fft_backend_next_valid_size(size_t n, int complex_transform) {
    (void)complex_transform;
    if (n == 0 || n > (size_t)INT_MAX) return 0;
    return n;
}

/* pocketfft-c rfft output layout (FFTPACK halfcomplex):
 * out[0] = Re(0)
 * for k=1..floor((N-1)/2): out[2k-1]=Re(k), out[2k]=Im(k)
 * if N even: out[N-1]=Re(N/2)
 */
static void yl_unpack_rfft_to_split(
    const float* halfcomplex,
    int n,
    float* out_real,
    float* out_imag
) {
    const int nh = n / 2;
    int k;

    out_real[0] = (float)halfcomplex[0];
    out_imag[0] = 0.0f;

    for (k = 1; k <= (n - 1) / 2; ++k) {
        out_real[k] = (float)halfcomplex[2 * k - 1];
        out_imag[k] = (float)halfcomplex[2 * k];
    }

    if ((n & 1) == 0) {
        out_real[nh] = (float)halfcomplex[n - 1];
        out_imag[nh] = 0.0f;
    }
}

static void yl_pack_split_to_rfft(
    const float* in_real,
    const float* in_imag,
    int n,
    float* halfcomplex
) {
    const int nh = n / 2;
    int k;

    halfcomplex[0] = in_real[0];

    for (k = 1; k <= (n - 1) / 2; ++k) {
        halfcomplex[2 * k - 1] = in_real[k];
        halfcomplex[2 * k] = in_imag[k];
    }

    if ((n & 1) == 0) {
        halfcomplex[n - 1] = in_real[nh];
    }
}

/* Execute a forward real FFT into split real/imag arrays. */
void yl_fft_backend_execute_r2c(
    yl_fft_backend* b,
    const float* input,
    float* out_real,
    float* out_imag
) {
    int i;
    if (!b || b->kind != YL_POCKETFFT_C_KIND_REAL || b->is_inverse) return;
    if (!input || !out_real || !out_imag) return;

    for (i = 0; i < b->n; ++i) {
        b->rbuf[i] = input[i];
    }

    if (rfft_forward_f32(b->rplan, b->rbuf, 1.0f) != 0) return;
    yl_unpack_rfft_to_split(b->rbuf, b->n, out_real, out_imag);
}

/* Return non-redundant bin count. */
size_t yl_fft_backend_bins(const yl_fft_backend* b) {
    return b ? (size_t)(b->n / 2 + 1) : 0;
}

/* Compute scalar spectral bins from a real-input FFT. */
void yl_fft_backend_execute_r2c_spec(
    yl_fft_backend* b,
    const float* input,
    float* out_bins,
    yl_spec_mode mode,
    float db_floor
) {
    const int bins = (b != NULL) ? (b->n / 2 + 1) : 0;
    float* re = NULL;
    float* im = NULL;
    int k;

    if (!b || b->kind != YL_POCKETFFT_C_KIND_REAL || b->is_inverse) return;
    if (!input || !out_bins) return;

    re = (float*)malloc((size_t)bins * sizeof(float));
    im = (float*)malloc((size_t)bins * sizeof(float));
    if (!re || !im) {
        free(re);
        free(im);
        return;
    }

    yl_fft_backend_execute_r2c(b, input, re, im);

    if (mode == YL_SPEC_POWER) {
        for (k = 0; k < bins; ++k) {
            out_bins[k] = yl_pow2(re[k]) + yl_pow2(im[k]);
        }
        free(re);
        free(im);
        return;
    }

    if (mode == YL_SPEC_DB) {
        for (k = 0; k < bins; ++k) {
            float db = 10.0f * log10f(yl_pow2(re[k]) + yl_pow2(im[k]) + YL_DB_EPS);
            if (db < db_floor) db = db_floor;
            out_bins[k] = db;
        }
        free(re);
        free(im);
        return;
    }

    for (k = 0; k < bins; ++k) {
        out_bins[k] = sqrtf(yl_pow2(re[k]) + yl_pow2(im[k]));
    }

    free(re);
    free(im);
}

/* FFT-based autocorrelation with optional r0 normalization. */
void yl_fft_backend_execute_autocorr(
    yl_fft_backend* b,
    const float* input,
    size_t input_len,
    float* out_acf,
    size_t out_len,
    yl_acf_mode mode
) {
    size_t i;
    if (!b || b->kind != YL_POCKETFFT_C_KIND_REAL) return;
    if (!input || !out_acf) return;
    if (input_len > (size_t)b->n) return;
    if (out_len > (size_t)b->n) out_len = (size_t)b->n;

    for (i = 0; i < input_len; ++i) {
        b->rbuf[i] = input[i];
    }
    for (; i < (size_t)b->n; ++i) {
        b->rbuf[i] = 0.0f;
    }

    if (rfft_forward_f32(b->rplan, b->rbuf, 1.0f) != 0) return;

    /* In-place halfcomplex power spectrum: imag terms become zero. */
    b->rbuf[0] = b->rbuf[0] * b->rbuf[0];
    for (i = 1; i <= (size_t)(b->n - 1) / 2; ++i) {
        const float re = b->rbuf[2 * i - 1];
        const float im = b->rbuf[2 * i];
        b->rbuf[2 * i - 1] = re * re + im * im;
        b->rbuf[2 * i] = 0.0f;
    }
    if ((b->n & 1) == 0) {
        const int ny = b->n - 1;
        b->rbuf[ny] = b->rbuf[ny] * b->rbuf[ny];
    }

    if (rfft_backward_f32(b->rplan, b->rbuf, 1.0f / (float)b->n) != 0) return;

    if (mode == YL_ACF_NORM_R0) {
        const float r0 = b->rbuf[0];
        const float inv_r0 = (fabsf(r0) > 1e-20f) ? (1.0f / r0) : 0.0f;
        for (i = 0; i < out_len; ++i) {
            out_acf[i] = b->rbuf[i] * inv_r0;
        }
    } else {
        for (i = 0; i < out_len; ++i) {
            out_acf[i] = b->rbuf[i];
        }
    }
}

/* Execute inverse real FFT from split bins. */
void yl_fft_backend_execute_c2r(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* output
) {
    int i;
    if (!b || b->kind != YL_POCKETFFT_C_KIND_REAL || !b->is_inverse) return;
    if (!in_real || !in_imag || !output) return;

    yl_pack_split_to_rfft(in_real, in_imag, b->n, b->rbuf);
    if (rfft_backward_f32(b->rplan, b->rbuf, 1.0f / (float)b->n) != 0) return;

    for (i = 0; i < b->n; ++i) {
        output[i] = b->rbuf[i];
    }
}

/* Execute forward complex FFT into split arrays. */
void yl_fft_backend_execute_c2c_forward(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
    int i;
    if (!b || b->kind != YL_POCKETFFT_C_KIND_COMPLEX) return;
    if (!in_real || !in_imag || !out_real || !out_imag) return;

    for (i = 0; i < b->n; ++i) {
        b->cbuf[2 * i] = in_real[i];
        b->cbuf[2 * i + 1] = in_imag[i];
    }

    if (cfft_forward_f32(b->cplan, b->cbuf, 1.0f) != 0) return;

    for (i = 0; i < b->n; ++i) {
        out_real[i] = b->cbuf[2 * i];
        out_imag[i] = b->cbuf[2 * i + 1];
    }
}

/* Execute inverse complex FFT into split arrays, normalized by N. */
void yl_fft_backend_execute_c2c_backward(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
    int i;
    if (!b || b->kind != YL_POCKETFFT_C_KIND_COMPLEX) return;
    if (!in_real || !in_imag || !out_real || !out_imag) return;

    for (i = 0; i < b->n; ++i) {
        b->cbuf[2 * i] = in_real[i];
        b->cbuf[2 * i + 1] = in_imag[i];
    }

    if (cfft_backward_f32(b->cplan, b->cbuf, 1.0f / (float)b->n) != 0) return;

    for (i = 0; i < b->n; ++i) {
        out_real[i] = b->cbuf[2 * i];
        out_imag[i] = b->cbuf[2 * i + 1];
    }
}

/* Destroy backend resources. */
void yl_fft_backend_destroy(yl_fft_backend* b) {
    if (!b) return;
    if (b->rplan) destroy_rfft_plan_f32(b->rplan);
    if (b->cplan) destroy_cfft_plan_f32(b->cplan);
    free(b->rbuf);
    free(b->cbuf);
    free(b);
}
