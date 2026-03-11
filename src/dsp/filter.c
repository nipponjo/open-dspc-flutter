#include "dsp/filter.h"
#include <stdlib.h>
#include <string.h>

struct yl_iir_ctx {
    size_t nb;
    size_t na;
    size_t L;      // max(nb, na)
    size_t order;  // L - 1

    float* bp;     // padded numerator, length L
    float* ap;     // padded denominator, length L (ap[0] == 1)
    float* z;      // state, length order
};

static int yl_validate_coeffs(const float* b, size_t nb, const float* a, size_t na) {
    if (!b || !a) return 1;
    if (nb == 0 || na == 0) return 2;
    if (a[0] == 0.0f) return 3;
    return 0;
}

yl_iir_ctx* yl_iir_create_df2t_f32(
    const float* b, size_t nb,
    const float* a, size_t na
) {
    if (yl_validate_coeffs(b, nb, a, na)) return NULL;

    yl_iir_ctx* ctx = (yl_iir_ctx*)calloc(1, sizeof(*ctx));
    if (!ctx) return NULL;

    ctx->nb = nb;
    ctx->na = na;
    ctx->L  = (nb > na) ? nb : na;
    ctx->order = (ctx->L > 0) ? (ctx->L - 1) : 0;

    // Allocate contiguous block: bp[L] + ap[L] + z[order]
    const size_t total = ctx->L + ctx->L + ctx->order;
    float* mem = (float*)malloc(total * sizeof(float));
    if (!mem) {
        free(ctx);
        return NULL;
    }

    ctx->bp = mem;
    ctx->ap = mem + ctx->L;
    ctx->z  = mem + 2 * ctx->L;

    // Normalize by a0 and pad to length L
    const float a0 = a[0];
    const float inv_a0 = (a0 == 1.0f) ? 1.0f : (1.0f / a0);

    for (size_t i = 0; i < ctx->L; ++i) {
        ctx->bp[i] = 0.0f;
        ctx->ap[i] = 0.0f;
    }

    for (size_t i = 0; i < nb; ++i) ctx->bp[i] = b[i] * inv_a0;
    for (size_t i = 0; i < na; ++i) ctx->ap[i] = a[i] * inv_a0;

    // Reset state
    if (ctx->order) {
        memset(ctx->z, 0, ctx->order * sizeof(float));
    }

    return ctx;
}

void yl_iir_destroy(yl_iir_ctx* ctx) {
    if (!ctx) return;
    if (ctx->bp) free(ctx->bp); // bp points to the start of the contiguous allocation
    free(ctx);
}

size_t yl_iir_order(const yl_iir_ctx* ctx) {
    return ctx ? ctx->order : 0;
}

void yl_iir_reset(yl_iir_ctx* ctx) {
    if (!ctx) return;
    if (ctx->order) memset(ctx->z, 0, ctx->order * sizeof(float));
}

int yl_iir_set_state_f32(yl_iir_ctx* ctx, const float* zi, size_t zi_len) {
    if (!ctx) return 1;
    if (ctx->order == 0) return 0;
    if (!zi) return 2;
    if (zi_len != ctx->order) return 3;
    memcpy(ctx->z, zi, ctx->order * sizeof(float));
    return 0;
}

int yl_iir_get_state_f32(const yl_iir_ctx* ctx, float* zf, size_t zf_len) {
    if (!ctx) return 1;
    if (ctx->order == 0) return 0;
    if (!zf) return 2;
    if (zf_len != ctx->order) return 3;
    memcpy(zf, ctx->z, ctx->order * sizeof(float));
    return 0;
}

int yl_iir_process_df2t_f32(
    yl_iir_ctx* ctx, 
    const float* x, 
    float* y, // length (nx)
    size_t nx // length of x
) {
    if (!ctx || (!x && nx) || (!y && nx)) return 1;
    if (nx == 0) return 0;

    const size_t order = ctx->order;

    // order==0 => pure gain: y = b0*x (b0 already normalized)
    if (order == 0) {
        const float g = ctx->bp[0];
        for (size_t n = 0; n < nx; ++n) y[n] = g * x[n];
        return 0;
    }

    const float b0 = ctx->bp[0];
    float* z = ctx->z;
    const float* bp = ctx->bp;
    const float* ap = ctx->ap;

    // DF-II Transposed:
    // y[n] = b0*x[n] + z[0]
    // z[k] = z[k+1] + b[k+1]*x[n] - a[k+1]*y[n]
    // z[order-1] = b[order]*x[n] - a[order]*y[n]
    for (size_t n = 0; n < nx; ++n) {
        const float xn = x[n];
        const float yn = b0 * xn + z[0];
        y[n] = yn;

        for (size_t k = 0; k + 1 < order; ++k) {
            z[k] = z[k + 1] + bp[k + 1] * xn - ap[k + 1] * yn;
        }
        z[order - 1] = bp[order] * xn - ap[order] * yn;
    }

    return 0;
}