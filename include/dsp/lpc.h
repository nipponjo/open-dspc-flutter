#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>

typedef struct yl_lpc_ctx yl_lpc_ctx;

typedef enum yl_lpc_method {
    /** Autocorrelation + Levinson-Durbin recursion (Yule-Walker solution). */
    YL_LPC_METHOD_LEVINSON = 0,
    /** Burg / Marple-style recursion using forward/backward prediction errors. */
    YL_LPC_METHOD_BURG = 1,
} yl_lpc_method;

/**
 * Create an LPC context for order m (allocates scratch buffers r and a).
 * Returns NULL on failure.
 */
yl_lpc_ctx* yl_lpc_create(int m);

/**
 * Compute LPC for one frame.
 * - y: input frame length L
 * - ctx: must be created with same m you want
 * - method:
 *     - YL_LPC_METHOD_LEVINSON:
 *         Uses autocorrelation + Levinson-Durbin recursion.
 *         Fast and standard Yule-Walker LPC.
 *     - YL_LPC_METHOD_BURG:
 *         Uses Burg's method (Marple-style recursion) based on
 *         forward/backward prediction errors. Often yields good
 *         spectral estimates on short frames.
 * - sptk: if nonzero, out[0]=sqrt(E), out[1..m]=a[1..m]
 *         else out[0]=1, out[1..m]=a[1..m]
 * - out: length (m+1)
 * Returns sqrt(E) for the selected method.
 */
float yl_lpc_process_frame(
    yl_lpc_ctx* ctx,
    const float* y,
    int L,
    int method,
    int sptk,
    float* out
);

/** Destroy LPC context. */
void yl_lpc_destroy(yl_lpc_ctx* ctx);

/** Returns order m for this ctx. */
int yl_lpc_order(const yl_lpc_ctx* ctx);

#ifdef __cplusplus
}
#endif
