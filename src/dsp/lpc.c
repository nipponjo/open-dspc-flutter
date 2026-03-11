#include "dsp/lpc.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <float.h>

struct yl_lpc_ctx {
    int m;
    float* r; // length m+1
    float* a; // length m+1
    float* a_next; // length m+1, used by Burg updates
    float* ef; // length burg_cap
    float* eb; // length burg_cap
    int burg_cap;
};

yl_lpc_ctx* yl_lpc_create(int m) {
    if (m <= 0) return NULL;

    yl_lpc_ctx* ctx = (yl_lpc_ctx*)malloc(sizeof(yl_lpc_ctx));
    if (!ctx) return NULL;

    ctx->m = m;
    ctx->r = (float*)malloc((size_t)(m + 1) * sizeof(float));
    ctx->a = (float*)malloc((size_t)(m + 1) * sizeof(float));
    ctx->a_next = (float*)malloc((size_t)(m + 1) * sizeof(float));
    ctx->ef = NULL;
    ctx->eb = NULL;
    ctx->burg_cap = 0;

    if (!ctx->r || !ctx->a || !ctx->a_next) {
        free(ctx->r);
        free(ctx->a);
        free(ctx->a_next);
        free(ctx);
        return NULL;
    }

    return ctx;
}

int yl_lpc_order(const yl_lpc_ctx* ctx) {
    return ctx ? ctx->m : 0;
}

static inline float lpc_frame_levinson_impl(
    const float* y, int L, int m, int sptk,
    float* out, float* r, float* a
) {
    // Autocorrelation r[0..m]
    float acc0 = 0.0f;
    for (int n = 0; n < L; ++n) {
        const float v = y[n];
        acc0 += v * v;
    }
    r[0] = acc0;

    // Silent frame fallback
    if (r[0] <= 0.0f) {
        memset(out, 0, (size_t)(m + 1) * sizeof(float));
        if (!sptk) out[0] = 1.0f;
        return 0.0f;
    }

    // r[k] = sum_{n=0}^{L-1-k} y[n]*y[n+k]
    const int kmax = (m < L) ? m : (L - 1);
    for (int k = 1; k <= m; ++k) r[k] = 0.0f;

    for (int k = 1; k <= kmax; ++k) {
        float acc = 0.0f;
        for (int n = 0; n < L - k; ++n) {
            acc += y[n] * y[n + k];
        }
        r[k] = acc;
    }

    // Levinson–Durbin
    a[0] = 1.0f;
    for (int i = 1; i <= m; ++i) a[i] = 0.0f;

    float E = r[0];

    // i=1
    if (m >= 1) {
        const float kappa = -r[1] / (E + 1e-18f);
        a[1] = kappa;
        E *= (1.0f - kappa * kappa + 1e-12f);
    }

    // i=2..m
    for (int i = 2; i <= m; ++i) {
        float acc = r[i];
        for (int j = 1; j < i; ++j) {
            acc += a[j] * r[i - j];
        }

        const float kappa = -acc / (E + 1e-18f);

        for (int j = 1; j <= (i / 2); ++j) {
            const float aj   = a[j];
            const float ai_j = a[i - j];
            const float tmp  = aj + kappa * ai_j;
            a[i - j] = ai_j + kappa * aj;
            a[j]     = tmp;
        }
        a[i] = kappa;

        E *= (1.0f - kappa * kappa + 1e-12f);
    }

    const float e_sqrt = (E > 0.0f) ? sqrtf(E) : 0.0f;

    if (sptk) {
        out[0] = e_sqrt;
        for (int j = 1; j <= m; ++j) out[j] = a[j];
    } else {
        out[0] = 1.0f;
        for (int j = 1; j <= m; ++j) out[j] = a[j];
    }

    return e_sqrt;
}

static int yl_lpc_ensure_burg_capacity(yl_lpc_ctx* ctx, int L) {
    float* ef_new;
    float* eb_new;
    if (ctx->burg_cap >= L) return 1;
    ef_new = (float*)realloc(ctx->ef, (size_t)L * sizeof(float));
    if (!ef_new) return 0;

    eb_new = (float*)realloc(ctx->eb, (size_t)L * sizeof(float));
    if (!eb_new) {
        if (ef_new != ctx->ef) free(ef_new);
        return 0;
    }

    ctx->ef = ef_new;
    ctx->eb = eb_new;
    ctx->burg_cap = L;
    return 1;
}

static inline float lpc_frame_burg_impl(
    yl_lpc_ctx* ctx,
    const float* y,
    int L,
    int m,
    int sptk,
    float* out
) {
    const float eps = FLT_MIN;
    int pmax;
    float den;
    float* a_prev;
    float* a_cur;
    int f_off = 0;
    int b_off = 0;
    int cur_len;

    if (!yl_lpc_ensure_burg_capacity(ctx, L)) return -1.0f;
    pmax = (m < (L - 1)) ? m : (L - 1);
    cur_len = L - 1;

    if (cur_len <= 0) {
        memset(out, 0, (size_t)(m + 1) * sizeof(float));
        if (!sptk) out[0] = 1.0f;
        return 0.0f;
    }

    den = 0.0f;
    for (int n = 0; n < cur_len; ++n) {
        const float f = y[n + 1];
        const float b = y[n];
        ctx->ef[n] = f;
        ctx->eb[n] = b;
        den += f * f + b * b;
    }

    if (den <= 0.0f) {
        memset(out, 0, (size_t)(m + 1) * sizeof(float));
        if (!sptk) out[0] = 1.0f;
        return 0.0f;
    }

    memset(ctx->a, 0, (size_t)(m + 1) * sizeof(float));
    memset(ctx->a_next, 0, (size_t)(m + 1) * sizeof(float));
    ctx->a[0] = 1.0f;
    ctx->a_next[0] = 1.0f;
    a_prev = ctx->a;
    a_cur = ctx->a_next;

    for (int i = 0; i < pmax; ++i) {
        float num = 0.0f;
        float refl;

        if (cur_len <= 0) break;

        for (int n = 0; n < cur_len; ++n) {
            num += ctx->eb[b_off + n] * ctx->ef[f_off + n];
        }

        refl = -2.0f * num / (den + eps);

        {
            float* t = a_prev;
            a_prev = a_cur;
            a_cur = t;
        }
        a_cur[0] = 1.0f;
        for (int j = 1; j <= i + 1; ++j) {
            a_cur[j] = a_prev[j] + refl * a_prev[i - j + 1];
        }
        for (int j = i + 2; j <= m; ++j) a_cur[j] = 0.0f;

        for (int n = 0; n < cur_len; ++n) {
            const float ef_old = ctx->ef[f_off + n];
            const float eb_old = ctx->eb[b_off + n];
            ctx->ef[f_off + n] = ef_old + refl * eb_old;
            ctx->eb[b_off + n] = eb_old + refl * ef_old;
        }

        {
            const float q = 1.0f - refl * refl;
            const float b_last = ctx->eb[b_off + cur_len - 1];
            const float f_first = ctx->ef[f_off];
            den = q * den - b_last * b_last - f_first * f_first;
        }

        f_off += 1;
        cur_len -= 1;

        if (den <= eps) {
            den = 0.0f;
            break;
        }
    }

    if (sptk) {
        out[0] = (den > 0.0f) ? sqrtf(0.5f * den) : 0.0f;
        for (int j = 1; j <= m; ++j) out[j] = a_cur[j];
    } else {
        out[0] = 1.0f;
        for (int j = 1; j <= m; ++j) out[j] = a_cur[j];
    }

    return (den > 0.0f) ? sqrtf(0.5f * den) : 0.0f;
}

float yl_lpc_process_frame(
    yl_lpc_ctx* ctx,
    const float* y,
    int L,
    int method,
    int sptk,
    float* out
) {
    if (!ctx || !y || !out || L <= 0) return -1.0f;
    if (method == YL_LPC_METHOD_BURG) {
        return lpc_frame_burg_impl(ctx, y, L, ctx->m, sptk, out);
    }
    return lpc_frame_levinson_impl(y, L, ctx->m, sptk, out, ctx->r, ctx->a);
}

void yl_lpc_destroy(yl_lpc_ctx* ctx) {
    if (!ctx) return;
    free(ctx->r);
    free(ctx->a);
    free(ctx->a_next);
    free(ctx->ef);
    free(ctx->eb);
    free(ctx);
}


