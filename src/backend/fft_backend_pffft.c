#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <math.h>
#include <float.h>

#include "pffft.h"

#include "dsp/fft.h"

#ifndef YL_DB_EPS
#define YL_DB_EPS 1e-20f
#endif

/*
PFFFT REAL transform (ordered) layout (N floats):
- bin 0 (DC) is stored as Y[0] (real); Y[1] stores Nyquist (real)
- bins k=1..N/2-1 stored as interleaved complex:
    Re(k) = Y[2*k]
    Im(k) = Y[2*k+1]
So we map to out_real/out_imag of length (N/2+1):
- out_real[0]   = Y[0],  out_imag[0]   = 0
- out_real[N/2] = Y[1],  out_imag[N/2] = 0
- out_real[k]   = Y[2*k], out_imag[k]  = Y[2*k+1] for 1<=k<=N/2-1
*/

typedef struct yl_fft_backend {
    int n;
    int kind;             // 1=real, 2=complex
    PFFFT_Setup* setup;
    float* time;          // aligned, length n for real, 2*n for complex
    float* spec;          // aligned, length n for real, 2*n for complex
    float* work;          // aligned, length n for real, 2*n for complex
    int is_inverse;       // real-only: 0=r2c, 1=c2r
} yl_fft_backend;

enum {
    YL_PFFFT_KIND_REAL = 1,
    YL_PFFFT_KIND_COMPLEX = 2,
};

static yl_fft_backend* yl_fft_backend_alloc(int n, int kind, int inverse) {
    if (n <= 0) return NULL;

    const pffft_transform_t transform =
        (kind == YL_PFFFT_KIND_COMPLEX) ? PFFFT_COMPLEX : PFFFT_REAL;
    const size_t n_floats = (kind == YL_PFFFT_KIND_COMPLEX) ? (size_t)(2 * n) : (size_t)n;

    if (!pffft_is_valid_size(n, transform)) {
        return NULL;
    }

    yl_fft_backend* b = (yl_fft_backend*)malloc(sizeof(yl_fft_backend));
    if (!b) return NULL;

    b->n = n;
    b->kind = kind;
    b->is_inverse = inverse ? 1 : 0;
    b->setup = NULL;
    b->time = NULL;
    b->spec = NULL;
    b->work = NULL;

    b->setup = pffft_new_setup(n, transform);
    if (!b->setup) {
        free(b);
        return NULL;
    }

    // PFFFT expects 16-byte aligned buffers for best SIMD performance.
    b->time = (float*)pffft_aligned_malloc(n_floats * sizeof(float));
    b->spec = (float*)pffft_aligned_malloc(n_floats * sizeof(float));
    b->work = (float*)pffft_aligned_malloc(n_floats * sizeof(float));
    if (!b->time || !b->spec || !b->work) {
        if (b->time) pffft_aligned_free(b->time);
        if (b->spec) pffft_aligned_free(b->spec);
        if (b->work) pffft_aligned_free(b->work);
        pffft_destroy_setup(b->setup);
        free(b);
        return NULL;
    }

    return b;
}

yl_fft_backend* yl_fft_backend_create_r2c(size_t n) {
    if (n > (size_t)INT_MAX) return NULL;
    return yl_fft_backend_alloc((int)n, YL_PFFFT_KIND_REAL, 0);
}

yl_fft_backend* yl_fft_backend_create_c2r(size_t n) {
    if (n > (size_t)INT_MAX) return NULL;
    return yl_fft_backend_alloc((int)n, YL_PFFFT_KIND_REAL, 1);
}

yl_fft_backend* yl_fft_backend_create_c2c(size_t n) {
    if (n > (size_t)INT_MAX) return NULL;
    return yl_fft_backend_alloc((int)n, YL_PFFFT_KIND_COMPLEX, 0);
}

size_t yl_fft_backend_next_valid_size(size_t n, int complex_transform) {
    if (n == 0 || n > (size_t)INT_MAX) return 0;
    const pffft_transform_t transform =
        complex_transform ? PFFFT_COMPLEX : PFFFT_REAL;
    const int next = pffft_nearest_transform_size((int)n, transform, 1);
    return (next > 0) ? (size_t)next : 0;
}

void yl_fft_backend_execute_r2c(
    yl_fft_backend* b,
    const float* input,
    float* out_real,
    float* out_imag
) {
    if (!b || b->kind != YL_PFFFT_KIND_REAL || b->is_inverse) return;
    if (!input || !out_real || !out_imag) return;

    const int n = b->n;
    const int nh = n / 2;

    // Copy input into aligned buffer
    memcpy(b->time, input, (size_t)n * sizeof(float));

    // Forward REAL FFT into ordered spectrum layout (length n floats)
    pffft_transform_ordered(b->setup, b->time, b->spec, b->work, PFFFT_FORWARD);

    // Unpack to real/imag arrays of length (n/2+1)
    out_real[0] = b->spec[0];
    out_imag[0] = 0.0f;

    out_real[nh] = b->spec[1]; // Nyquist
    out_imag[nh] = 0.0f;

    for (int k = 1; k < nh; ++k) {
        out_real[k] = b->spec[2 * k];
        out_imag[k] = b->spec[2 * k + 1];
    }
}

static inline float yl_pow2(float x) { return x * x; }

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
    if (!b || b->kind != YL_PFFFT_KIND_REAL || b->is_inverse) return;
    if (!input || !out_bins) return;

    const int n  = b->n;
    const int nh = n / 2;

    // Copy input
    memcpy(b->time, input, (size_t)n * sizeof(float));

    // FFT (ordered real)
    pffft_transform_ordered(b->setup, b->time, b->spec, b->work, PFFFT_FORWARD);

    // DC and Nyquist are real-only
    const float dc  = b->spec[0];
    const float nyq = b->spec[1];

    if (mode == YL_SPEC_POWER) {
        out_bins[0]  = yl_pow2(dc);
        out_bins[nh] = yl_pow2(nyq);
        for (int k = 1; k < nh; ++k) {
            const float re = b->spec[2 * k];
            const float im = b->spec[2 * k + 1];
            out_bins[k] = re * re + im * im;
        }
        return;
    }

    if (mode == YL_SPEC_MAG) {
        out_bins[0]  = fabsf(dc);
        out_bins[nh] = fabsf(nyq);
        for (int k = 1; k < nh; ++k) {
            const float re = b->spec[2 * k];
            const float im = b->spec[2 * k + 1];
            out_bins[k] = sqrtf(re * re + im * im);
        }
        return;
    }

    if (mode == YL_SPEC_DB) {
        // We compute dB from POWER: 10*log10(power + eps)
        // Clamp to db_floor for nicer UI.
        out_bins[0]  = 10.0f * log10f(yl_pow2(dc) + YL_DB_EPS);
        out_bins[nh] = 10.0f * log10f(yl_pow2(nyq) + YL_DB_EPS);

        if (out_bins[0] < db_floor) out_bins[0] = db_floor;
        if (out_bins[nh] < db_floor) out_bins[nh] = db_floor;

        for (int k = 1; k < nh; ++k) {
            const float re = b->spec[2 * k];
            const float im = b->spec[2 * k + 1];
            float db = 10.0f * log10f(re * re + im * im + YL_DB_EPS);
            if (db < db_floor) db = db_floor;
            out_bins[k] = db;
        }
        return;
    }

    // Default: treat as MAG
    out_bins[0]  = fabsf(dc);
    out_bins[nh] = fabsf(nyq);
    for (int k = 1; k < nh; ++k) {
        const float re = b->spec[2 * k];
        const float im = b->spec[2 * k + 1];
        out_bins[k] = sqrtf(re * re + im * im);
    }
}

void yl_fft_backend_execute_autocorr(
    yl_fft_backend* b,
    const float* input,
    size_t input_len,
    float* out_acf,
    size_t out_len,
    yl_acf_mode mode
) {
    if (!b || b->kind != YL_PFFFT_KIND_REAL || !input || !out_acf) return;

    const int n = b->n;
    const int nh = n / 2;

    if (input_len > (size_t)n) return;
    if (out_len > (size_t)n) out_len = (size_t)n;

    // 1) Copy + zero-pad into aligned time buffer
    //    (memset whole buffer is often fine; if you want faster, only zero tail)
    memcpy(b->time, input, input_len * sizeof(float));
    if (input_len < (size_t)n) {
        memset(b->time + input_len, 0, ((size_t)n - input_len) * sizeof(float));
    }

    // 2) Forward FFT: time -> spec (ordered real layout)
    pffft_transform_ordered(b->setup, b->time, b->spec, b->work, PFFFT_FORWARD);

    // 3) Power spectrum in-place: spec = X * conj(X)
    //    For real ordered layout:
    //    spec[0] = DC (real), spec[1] = Nyquist (real),
    //    bins k=1..nh-1 are complex interleaved in spec[2k], spec[2k+1]
    {
        const float dc  = b->spec[0];
        const float nyq = b->spec[1];
        b->spec[0] = dc * dc;
        b->spec[1] = nyq * nyq;

        for (int k = 1; k < nh; ++k) {
            const float re = b->spec[2 * k];
            const float im = b->spec[2 * k + 1];
            b->spec[2 * k]     = re * re + im * im; // power
            b->spec[2 * k + 1] = 0.0f;              // imag = 0
        }
    }

    // 4) Inverse FFT: spec -> time (autocorrelation, circular)
    //    Note: PFFFT backward is not normalized => divide by n.
    pffft_transform_ordered(b->setup, b->spec, b->time, b->work, PFFFT_BACKWARD);

    const float inv_n = 1.0f / (float)n;

    // 5) Output lags 0..out_len-1
    if (mode == YL_ACF_NORM_R0) {
        // Normalize by r0 (avoid divide-by-zero)
        const float r0 = b->time[0] * inv_n;
        const float inv_r0 = (fabsf(r0) > 1e-20f) ? (1.0f / r0) : 0.0f;
        for (size_t i = 0; i < out_len; ++i) {
            out_acf[i] = (b->time[i] * inv_n) * inv_r0;
        }
    } else {
        for (size_t i = 0; i < out_len; ++i) {
            out_acf[i] = b->time[i] * inv_n;
        }
    }
}

void yl_fft_backend_execute_c2r(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* output
) {
    if (!b || b->kind != YL_PFFFT_KIND_REAL || !b->is_inverse) return;
    if (!in_real || !in_imag || !output) return;

    const int n = b->n;
    const int nh = n / 2;

    // Pack from real/imag arrays into PFFFT ordered spectrum layout
    // DC + Nyquist packed into first complex entry:
    b->spec[0] = in_real[0];   // DC (real)
    b->spec[1] = in_real[nh];  // Nyquist (real)

    for (int k = 1; k < nh; ++k) {
        b->spec[2 * k]     = in_real[k];
        b->spec[2 * k + 1] = in_imag[k];
    }

    // Inverse REAL FFT. PFFFT is unnormalized: backward(forward(x)) = N*x
    pffft_transform_ordered(b->setup, b->spec, b->time, b->work, PFFFT_BACKWARD);

    const float invN = 1.0f / (float)n;
    for (int i = 0; i < n; ++i) {
        output[i] = b->time[i] * invN;
    }
}

void yl_fft_backend_execute_c2c_forward(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
    if (!b || b->kind != YL_PFFFT_KIND_COMPLEX) return;
    if (!in_real || !in_imag || !out_real || !out_imag) return;

    const int n = b->n;
    for (int k = 0; k < n; ++k) {
        b->time[2 * k] = in_real[k];
        b->time[2 * k + 1] = in_imag[k];
    }

    pffft_transform_ordered(b->setup, b->time, b->spec, b->work, PFFFT_FORWARD);

    for (int k = 0; k < n; ++k) {
        out_real[k] = b->spec[2 * k];
        out_imag[k] = b->spec[2 * k + 1];
    }
}

void yl_fft_backend_execute_c2c_backward(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
    if (!b || b->kind != YL_PFFFT_KIND_COMPLEX) return;
    if (!in_real || !in_imag || !out_real || !out_imag) return;

    const int n = b->n;
    const float invN = 1.0f / (float)n;

    for (int k = 0; k < n; ++k) {
        b->spec[2 * k] = in_real[k];
        b->spec[2 * k + 1] = in_imag[k];
    }

    pffft_transform_ordered(b->setup, b->spec, b->time, b->work, PFFFT_BACKWARD);

    for (int k = 0; k < n; ++k) {
        out_real[k] = b->time[2 * k] * invN;
        out_imag[k] = b->time[2 * k + 1] * invN;
    }
}

void yl_fft_backend_destroy(yl_fft_backend* b) {
    if (!b) return;
    if (b->time) pffft_aligned_free(b->time);
    if (b->spec) pffft_aligned_free(b->spec);
    if (b->work) pffft_aligned_free(b->work);
    if (b->setup) pffft_destroy_setup(b->setup);
    free(b);
}
