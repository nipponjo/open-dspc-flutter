#include "dsp/fft.h"
#include <math.h>
#include <stdlib.h>

/* Forward declarations of backend functions */
typedef struct yl_fft_backend yl_fft_backend;
typedef enum {
    YL_FFT_PLAN_R2C = 1,
    YL_FFT_PLAN_C2R = 2,
    YL_FFT_PLAN_C2C = 3,
} yl_fft_plan_kind;

yl_fft_backend* yl_fft_backend_create_r2c(size_t n);
yl_fft_backend* yl_fft_backend_create_c2r(size_t n);
yl_fft_backend* yl_fft_backend_create_c2c(size_t n);

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

/* Public plan struct */
struct yl_fft_plan {
    size_t n;
    yl_fft_plan_kind kind;
    yl_fft_backend* backend;
};

yl_fft_plan* yl_fft_create_r2c(size_t n) {
    yl_fft_plan* p = malloc(sizeof(yl_fft_plan));
    if (!p) return NULL;

    p->n = n;
    p->kind = YL_FFT_PLAN_R2C;
    p->backend = yl_fft_backend_create_r2c(n);
    if (!p->backend) {
        free(p);
        return NULL;
    }
    return p;
}

yl_fft_plan* yl_fft_create_c2r(size_t n) {
    yl_fft_plan* p = malloc(sizeof(yl_fft_plan));
    if (!p) return NULL;

    p->n = n;
    p->kind = YL_FFT_PLAN_C2R;
    p->backend = yl_fft_backend_create_c2r(n);
    if (!p->backend) {
        free(p);
        return NULL;
    }
    return p;
}

yl_fft_plan* yl_fft_create_c2c(size_t n) {
    yl_fft_plan* p = malloc(sizeof(yl_fft_plan));
    if (!p) return NULL;

    p->n = n;
    p->kind = YL_FFT_PLAN_C2C;
    p->backend = yl_fft_backend_create_c2c(n);
    if (!p->backend) {
        free(p);
        return NULL;
    }
    return p;
}

void yl_fft_execute_r2c(
    yl_fft_plan* plan,
    const float* input,
    float* out_real,
    float* out_imag
) {
    if (!plan || plan->kind != YL_FFT_PLAN_R2C) return;
    yl_fft_backend_execute_r2c(plan->backend, input, out_real, out_imag);
}

void yl_fft_execute_c2r(
    yl_fft_plan* plan,
    const float* in_real,
    const float* in_imag,
    float* output
) {
    if (!plan || plan->kind != YL_FFT_PLAN_C2R) return;
    yl_fft_backend_execute_c2r(plan->backend, in_real, in_imag, output);
}

void yl_fft_execute_c2c_forward(
    yl_fft_plan* plan,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
    if (!plan || plan->kind != YL_FFT_PLAN_C2C) return;
    yl_fft_backend_execute_c2c_forward(plan->backend, in_real, in_imag, out_real, out_imag);
}

void yl_fft_execute_c2c_backward(
    yl_fft_plan* plan,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
    if (!plan || plan->kind != YL_FFT_PLAN_C2C) return;
    yl_fft_backend_execute_c2c_backward(plan->backend, in_real, in_imag, out_real, out_imag);
}

void yl_fft_execute_r2c_spec(
    yl_fft_plan* plan,
    const float* input,
    float* out_bins,      // length n/2+1
    yl_spec_mode mode,
    float db_floor        // e.g. -120.0f (used only for DB)
) {
    if (!plan || plan->kind != YL_FFT_PLAN_R2C) return;
    yl_fft_backend_execute_r2c_spec(plan->backend, input, out_bins, mode, db_floor);
}

void yl_fft_execute_autocorr(
    yl_fft_plan* plan,
    const float* input,
    size_t input_len,
    float* out_acf,
    size_t out_len,
    yl_acf_mode mode
) {
    if (!plan) return;
    yl_fft_backend_execute_autocorr(plan->backend, input, input_len, out_acf, out_len, mode);
}

void yl_fft_destroy(yl_fft_plan* plan) {
    if (!plan) return;
    yl_fft_backend_destroy(plan->backend);
    free(plan);
}
