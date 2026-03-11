#include "opendspc_export.h"
#include "dsp/lpc.h"
#include <stdint.h>

YL_EXPORT void* yl_lpc_ctx_create(int m) {
    return (void*)yl_lpc_create(m);
}

YL_EXPORT int yl_lpc_ctx_order(void* ctx) {
    return yl_lpc_order((yl_lpc_ctx*)ctx);
}

YL_EXPORT float yl_lpc_ctx_process_frame(
    void* ctx,
    const float* y,
    int L,
    int method,
    int sptk,
    float* out
) {
    return yl_lpc_process_frame((yl_lpc_ctx*)ctx, y, L, method, sptk, out);
}

YL_EXPORT void yl_lpc_ctx_destroy(void* ctx) {
    yl_lpc_destroy((yl_lpc_ctx*)ctx);
}

YL_EXPORT float yl_lpc_process_single(
    const float* y,
    int L,
    int m,
    int method,
    int sptk,
    float* out // length (m + 1)
) {
    yl_lpc_ctx* ctx = yl_lpc_create(m);
    if (!ctx) return -1.0f;
    const float e_sqrt = yl_lpc_process_frame(ctx, y, L, method, sptk, out);
    yl_lpc_destroy(ctx);
    return e_sqrt;
}
