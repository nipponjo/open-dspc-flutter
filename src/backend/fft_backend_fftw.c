#include <fftw3.h>
#include <stdlib.h>

/* Backend struct */
typedef struct yl_fft_backend {
    size_t n;

    float* in;
    fftwf_complex* out;

    fftwf_plan plan_r2c;
    fftwf_plan plan_c2r;
} yl_fft_backend;

/* Create real->complex */
yl_fft_backend* yl_fft_backend_create_r2c(size_t n) {
    yl_fft_backend* b = malloc(sizeof(yl_fft_backend));
    if (!b) return NULL;

    b->n = n;

    b->in = fftwf_malloc(sizeof(float) * n);
    b->out = fftwf_malloc(sizeof(fftwf_complex) * (n/2 + 1));

    b->plan_r2c = fftwf_plan_dft_r2c_1d(
        n,
        b->in,
        b->out,
        FFTW_MEASURE
    );

    b->plan_c2r = NULL;

    return b;
}

/* Create complex->real */
yl_fft_backend* yl_fft_backend_create_c2r(size_t n) {
    yl_fft_backend* b = malloc(sizeof(yl_fft_backend));
    if (!b) return NULL;

    b->n = n;

    b->in = fftwf_malloc(sizeof(float) * n);
    b->out = fftwf_malloc(sizeof(fftwf_complex) * (n/2 + 1));

    b->plan_r2c = NULL;

    b->plan_c2r = fftwf_plan_dft_c2r_1d(
        n,
        b->out,
        b->in,
        FFTW_MEASURE
    );

    return b;
}

void yl_fft_backend_execute_r2c(
    yl_fft_backend* b,
    const float* input,
    float* out_real,
    float* out_imag
) {
    for (size_t i = 0; i < b->n; i++)
        b->in[i] = input[i];

    fftwf_execute(b->plan_r2c);

    for (size_t i = 0; i < b->n/2 + 1; i++) {
        out_real[i] = b->out[i][0];
        out_imag[i] = b->out[i][1];
    }
}

void yl_fft_backend_execute_c2r(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* output
) {
    for (size_t i = 0; i < b->n/2 + 1; i++) {
        b->out[i][0] = in_real[i];
        b->out[i][1] = in_imag[i];
    }

    fftwf_execute(b->plan_c2r);

    /* Normalize inverse FFT */
    for (size_t i = 0; i < b->n; i++)
        output[i] = b->in[i] / b->n;
}

void yl_fft_backend_destroy(yl_fft_backend* b) {
    if (!b) return;

    if (b->plan_r2c) fftwf_destroy_plan(b->plan_r2c);
    if (b->plan_c2r) fftwf_destroy_plan(b->plan_c2r);

    fftwf_free(b->in);
    fftwf_free(b->out);

    free(b);
}
