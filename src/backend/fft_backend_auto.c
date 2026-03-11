#include <float.h>
#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "pffft.h"
#include "third_party/pocketfft-c/pocketfft_f32.h"

#include "dsp/fft.h"

#ifndef YL_DB_EPS
#define YL_DB_EPS 1e-20f
#endif

typedef enum yl_fft_impl_kind {
    YL_IMPL_PFFFT = 1,
    YL_IMPL_POCKETFFT_C = 2,
} yl_fft_impl_kind;

typedef struct yl_fft_backend {
    int n;
    int kind;       /* 1 = real, 2 = complex */
    int is_inverse; /* real plan flavor: 0 = r2c, 1 = c2r */
    yl_fft_impl_kind impl;

    /* pffft state */
    PFFFT_Setup* pffft_setup;
    float* pffft_time;
    float* pffft_spec;
    float* pffft_work;

    /* pocketfft-c state */
    rfft_plan_f32 pfft_rplan;
    cfft_plan_f32 pfft_cplan;
    float* pfft_rbuf; /* length n */
    float* pfft_cbuf; /* length 2*n (interleaved complex) */
} yl_fft_backend;

enum {
    YL_KIND_REAL = 1,
    YL_KIND_COMPLEX = 2,
};

static inline float yl_pow2(float x) { return x * x; }

static void yl_free_pffft_state(yl_fft_backend* b) {
    if (!b) return;
    if (b->pffft_time) pffft_aligned_free(b->pffft_time);
    if (b->pffft_spec) pffft_aligned_free(b->pffft_spec);
    if (b->pffft_work) pffft_aligned_free(b->pffft_work);
    if (b->pffft_setup) pffft_destroy_setup(b->pffft_setup);
    b->pffft_time = NULL;
    b->pffft_spec = NULL;
    b->pffft_work = NULL;
    b->pffft_setup = NULL;
}

static void yl_free_pocketfft_c_state(yl_fft_backend* b) {
    if (!b) return;
    if (b->pfft_rplan) destroy_rfft_plan_f32(b->pfft_rplan);
    if (b->pfft_cplan) destroy_cfft_plan_f32(b->pfft_cplan);
    free(b->pfft_rbuf);
    free(b->pfft_cbuf);
    b->pfft_rplan = NULL;
    b->pfft_cplan = NULL;
    b->pfft_rbuf = NULL;
    b->pfft_cbuf = NULL;
}

static int yl_init_pffft_state(yl_fft_backend* b) {
    const pffft_transform_t transform =
        (b->kind == YL_KIND_COMPLEX) ? PFFFT_COMPLEX : PFFFT_REAL;
    const size_t n_floats =
        (b->kind == YL_KIND_COMPLEX) ? (size_t)(2 * b->n) : (size_t)b->n;

    b->pffft_setup = pffft_new_setup(b->n, transform);
    if (!b->pffft_setup) return 0;

    b->pffft_time = (float*)pffft_aligned_malloc(n_floats * sizeof(float));
    b->pffft_spec = (float*)pffft_aligned_malloc(n_floats * sizeof(float));
    b->pffft_work = (float*)pffft_aligned_malloc(n_floats * sizeof(float));
    if (!b->pffft_time || !b->pffft_spec || !b->pffft_work) {
        yl_free_pffft_state(b);
        return 0;
    }
    return 1;
}

static int yl_init_pocketfft_c_state(yl_fft_backend* b) {
    if (b->kind == YL_KIND_REAL) {
        b->pfft_rplan = make_rfft_plan_f32((size_t)b->n);
        if (!b->pfft_rplan) return 0;
        b->pfft_rbuf = (float*)malloc((size_t)b->n * sizeof(float));
        if (!b->pfft_rbuf) {
            yl_free_pocketfft_c_state(b);
            return 0;
        }
    } else {
        b->pfft_cplan = make_cfft_plan_f32((size_t)b->n);
        if (!b->pfft_cplan) return 0;
        b->pfft_cbuf = (float*)malloc((size_t)(2 * b->n) * sizeof(float));
        if (!b->pfft_cbuf) {
            yl_free_pocketfft_c_state(b);
            return 0;
        }
    }
    return 1;
}

static yl_fft_backend* yl_fft_backend_alloc(int n, int kind, int inverse) {
    yl_fft_backend* b;
    const pffft_transform_t transform =
        (kind == YL_KIND_COMPLEX) ? PFFFT_COMPLEX : PFFFT_REAL;
    int pffft_ok;

    if (n <= 0) return NULL;

    b = (yl_fft_backend*)calloc(1, sizeof(yl_fft_backend));
    if (!b) return NULL;

    b->n = n;
    b->kind = kind;
    b->is_inverse = inverse ? 1 : 0;

    pffft_ok = pffft_is_valid_size(n, transform);
    if (pffft_ok) {
        if (!yl_init_pffft_state(b)) {
            free(b);
            return NULL;
        }
        b->impl = YL_IMPL_PFFFT;
        return b;
    }

    if (!yl_init_pocketfft_c_state(b)) {
        free(b);
        return NULL;
    }
    b->impl = YL_IMPL_POCKETFFT_C;
    return b;
}

yl_fft_backend* yl_fft_backend_create_r2c(size_t n) {
    if (n > (size_t)INT_MAX) return NULL;
    return yl_fft_backend_alloc((int)n, YL_KIND_REAL, 0);
}

yl_fft_backend* yl_fft_backend_create_c2r(size_t n) {
    if (n > (size_t)INT_MAX) return NULL;
    return yl_fft_backend_alloc((int)n, YL_KIND_REAL, 1);
}

yl_fft_backend* yl_fft_backend_create_c2c(size_t n) {
    if (n > (size_t)INT_MAX) return NULL;
    return yl_fft_backend_alloc((int)n, YL_KIND_COMPLEX, 0);
}

size_t yl_fft_backend_next_valid_size(size_t n, int complex_transform) {
    if (n == 0 || n > (size_t)INT_MAX) return 0;
    /* auto-mode contract: all sizes are accepted due to pocketfft-c fallback */
    return n;
}

static void yl_unpack_pocketfft_rfft(const float* halfcomplex, int n, float* out_real, float* out_imag) {
    const int nh = n / 2;
    int k;

    out_real[0] = (float)halfcomplex[0];
    out_imag[0] = 0.0f;

    for (k = 1; k <= (n - 1) / 2; ++k) {
        out_real[k] = halfcomplex[2 * k - 1];
        out_imag[k] = halfcomplex[2 * k];
    }
    if ((n & 1) == 0) {
        out_real[nh] = halfcomplex[n - 1];
        out_imag[nh] = 0.0f;
    }
}

static void yl_pack_pocketfft_rfft(const float* in_real, const float* in_imag, int n, float* halfcomplex) {
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

void yl_fft_backend_execute_r2c(
    yl_fft_backend* b,
    const float* input,
    float* out_real,
    float* out_imag
) {
    if (!b || b->kind != YL_KIND_REAL || b->is_inverse) return;
    if (!input || !out_real || !out_imag) return;

    if (b->impl == YL_IMPL_PFFFT) {
        const int n = b->n;
        const int nh = n / 2;
        int k;
        memcpy(b->pffft_time, input, (size_t)n * sizeof(float));
        pffft_transform_ordered(b->pffft_setup, b->pffft_time, b->pffft_spec, b->pffft_work, PFFFT_FORWARD);
        out_real[0] = b->pffft_spec[0];
        out_imag[0] = 0.0f;
        out_real[nh] = b->pffft_spec[1];
        out_imag[nh] = 0.0f;
        for (k = 1; k < nh; ++k) {
            out_real[k] = b->pffft_spec[2 * k];
            out_imag[k] = b->pffft_spec[2 * k + 1];
        }
        return;
    }

    {
        int i;
        for (i = 0; i < b->n; ++i) b->pfft_rbuf[i] = input[i];
        if (rfft_forward_f32(b->pfft_rplan, b->pfft_rbuf, 1.0f) != 0) return;
        yl_unpack_pocketfft_rfft(b->pfft_rbuf, b->n, out_real, out_imag);
    }
}

size_t yl_fft_backend_bins(const yl_fft_backend* b) {
    return b ? (size_t)(b->n / 2 + 1) : 0;
}

void yl_fft_backend_execute_r2c_spec(
    yl_fft_backend* b,
    const float* input,
    float* out_bins,
    yl_spec_mode mode,
    float db_floor
) {
    const int bins = (b != NULL) ? (b->n / 2 + 1) : 0;
    float* re;
    float* im;
    int k;

    if (!b || b->kind != YL_KIND_REAL || b->is_inverse) return;
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
        for (k = 0; k < bins; ++k) out_bins[k] = yl_pow2(re[k]) + yl_pow2(im[k]);
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
    for (k = 0; k < bins; ++k) out_bins[k] = sqrtf(yl_pow2(re[k]) + yl_pow2(im[k]));
    free(re);
    free(im);
}

void yl_fft_backend_execute_autocorr(
    yl_fft_backend* b,
    const float* input,
    size_t input_len,
    float* out_acf,
    size_t out_len,
    yl_acf_mode mode
) {
    if (!b || b->kind != YL_KIND_REAL || !input || !out_acf) return;

    if (b->impl == YL_IMPL_PFFFT) {
        const int n = b->n;
        const int nh = n / 2;
        const float inv_n = 1.0f / (float)n;
        int k;
        size_t i;
        if (input_len > (size_t)n) return;
        if (out_len > (size_t)n) out_len = (size_t)n;
        memcpy(b->pffft_time, input, input_len * sizeof(float));
        if (input_len < (size_t)n) memset(b->pffft_time + input_len, 0, ((size_t)n - input_len) * sizeof(float));
        pffft_transform_ordered(b->pffft_setup, b->pffft_time, b->pffft_spec, b->pffft_work, PFFFT_FORWARD);
        b->pffft_spec[0] = b->pffft_spec[0] * b->pffft_spec[0];
        b->pffft_spec[1] = b->pffft_spec[1] * b->pffft_spec[1];
        for (k = 1; k < nh; ++k) {
            const float re = b->pffft_spec[2 * k];
            const float im = b->pffft_spec[2 * k + 1];
            b->pffft_spec[2 * k] = re * re + im * im;
            b->pffft_spec[2 * k + 1] = 0.0f;
        }
        pffft_transform_ordered(b->pffft_setup, b->pffft_spec, b->pffft_time, b->pffft_work, PFFFT_BACKWARD);
        if (mode == YL_ACF_NORM_R0) {
            const float r0 = b->pffft_time[0] * inv_n;
            const float inv_r0 = (fabsf(r0) > 1e-20f) ? (1.0f / r0) : 0.0f;
            for (i = 0; i < out_len; ++i) out_acf[i] = (b->pffft_time[i] * inv_n) * inv_r0;
        } else {
            for (i = 0; i < out_len; ++i) out_acf[i] = b->pffft_time[i] * inv_n;
        }
        return;
    }

    {
        size_t i;
        if (input_len > (size_t)b->n) return;
        if (out_len > (size_t)b->n) out_len = (size_t)b->n;
        for (i = 0; i < input_len; ++i) b->pfft_rbuf[i] = input[i];
        for (; i < (size_t)b->n; ++i) b->pfft_rbuf[i] = 0.0f;
        if (rfft_forward_f32(b->pfft_rplan, b->pfft_rbuf, 1.0f) != 0) return;
        b->pfft_rbuf[0] = b->pfft_rbuf[0] * b->pfft_rbuf[0];
        for (i = 1; i <= (size_t)(b->n - 1) / 2; ++i) {
            const float re = b->pfft_rbuf[2 * i - 1];
            const float im = b->pfft_rbuf[2 * i];
            b->pfft_rbuf[2 * i - 1] = re * re + im * im;
            b->pfft_rbuf[2 * i] = 0.0f;
        }
        if ((b->n & 1) == 0) b->pfft_rbuf[b->n - 1] *= b->pfft_rbuf[b->n - 1];
        if (rfft_backward_f32(b->pfft_rplan, b->pfft_rbuf, 1.0f / (float)b->n) != 0) return;
        if (mode == YL_ACF_NORM_R0) {
            const float r0 = b->pfft_rbuf[0];
            const float inv_r0 = (fabsf(r0) > 1e-20f) ? (1.0f / r0) : 0.0f;
            for (i = 0; i < out_len; ++i) out_acf[i] = b->pfft_rbuf[i] * inv_r0;
        } else {
            for (i = 0; i < out_len; ++i) out_acf[i] = b->pfft_rbuf[i];
        }
    }
}

void yl_fft_backend_execute_c2r(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* output
) {
    if (!b || b->kind != YL_KIND_REAL || !b->is_inverse) return;
    if (!in_real || !in_imag || !output) return;

    if (b->impl == YL_IMPL_PFFFT) {
        const int n = b->n;
        const int nh = n / 2;
        const float inv_n = 1.0f / (float)n;
        int k;
        b->pffft_spec[0] = in_real[0];
        b->pffft_spec[1] = in_real[nh];
        for (k = 1; k < nh; ++k) {
            b->pffft_spec[2 * k] = in_real[k];
            b->pffft_spec[2 * k + 1] = in_imag[k];
        }
        pffft_transform_ordered(b->pffft_setup, b->pffft_spec, b->pffft_time, b->pffft_work, PFFFT_BACKWARD);
        for (k = 0; k < n; ++k) output[k] = b->pffft_time[k] * inv_n;
        return;
    }

    yl_pack_pocketfft_rfft(in_real, in_imag, b->n, b->pfft_rbuf);
    if (rfft_backward_f32(b->pfft_rplan, b->pfft_rbuf, 1.0f / (float)b->n) != 0) return;
    {
        int i;
        for (i = 0; i < b->n; ++i) output[i] = b->pfft_rbuf[i];
    }
}

void yl_fft_backend_execute_c2c_forward(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
    if (!b || b->kind != YL_KIND_COMPLEX) return;
    if (!in_real || !in_imag || !out_real || !out_imag) return;

    if (b->impl == YL_IMPL_PFFFT) {
        int k;
        for (k = 0; k < b->n; ++k) {
            b->pffft_time[2 * k] = in_real[k];
            b->pffft_time[2 * k + 1] = in_imag[k];
        }
        pffft_transform_ordered(b->pffft_setup, b->pffft_time, b->pffft_spec, b->pffft_work, PFFFT_FORWARD);
        for (k = 0; k < b->n; ++k) {
            out_real[k] = b->pffft_spec[2 * k];
            out_imag[k] = b->pffft_spec[2 * k + 1];
        }
        return;
    }

    {
        int i;
        for (i = 0; i < b->n; ++i) {
            b->pfft_cbuf[2 * i] = in_real[i];
            b->pfft_cbuf[2 * i + 1] = in_imag[i];
        }
        if (cfft_forward_f32(b->pfft_cplan, b->pfft_cbuf, 1.0f) != 0) return;
        for (i = 0; i < b->n; ++i) {
            out_real[i] = b->pfft_cbuf[2 * i];
            out_imag[i] = b->pfft_cbuf[2 * i + 1];
        }
    }
}

void yl_fft_backend_execute_c2c_backward(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
    if (!b || b->kind != YL_KIND_COMPLEX) return;
    if (!in_real || !in_imag || !out_real || !out_imag) return;

    if (b->impl == YL_IMPL_PFFFT) {
        const float inv_n = 1.0f / (float)b->n;
        int k;
        for (k = 0; k < b->n; ++k) {
            b->pffft_spec[2 * k] = in_real[k];
            b->pffft_spec[2 * k + 1] = in_imag[k];
        }
        pffft_transform_ordered(b->pffft_setup, b->pffft_spec, b->pffft_time, b->pffft_work, PFFFT_BACKWARD);
        for (k = 0; k < b->n; ++k) {
            out_real[k] = b->pffft_time[2 * k] * inv_n;
            out_imag[k] = b->pffft_time[2 * k + 1] * inv_n;
        }
        return;
    }

    {
        int i;
        for (i = 0; i < b->n; ++i) {
            b->pfft_cbuf[2 * i] = in_real[i];
            b->pfft_cbuf[2 * i + 1] = in_imag[i];
        }
        if (cfft_backward_f32(b->pfft_cplan, b->pfft_cbuf, 1.0f / (float)b->n) != 0) return;
        for (i = 0; i < b->n; ++i) {
            out_real[i] = b->pfft_cbuf[2 * i];
            out_imag[i] = b->pfft_cbuf[2 * i + 1];
        }
    }
}

void yl_fft_backend_destroy(yl_fft_backend* b) {
    if (!b) return;
    yl_free_pffft_state(b);
    yl_free_pocketfft_c_state(b);
    free(b);
}
