#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct yl_iir_ctx yl_iir_ctx;

/**
 * Create a single-precision IIR filter context using Direct Form II Transposed.
 *
 * The numerator coefficients `b` have length `nb`.
 * The denominator coefficients `a` have length `na` and must satisfy `a[0] != 0`.
 * Coefficients are normalized internally by `a[0]`, so the stored denominator
 * has `a[0] == 1`.
 *
 * Returns a newly allocated filter context, or `NULL` if arguments are invalid
 * or memory allocation fails.
 */
yl_iir_ctx* yl_iir_create_df2t_f32(
    const float* b, size_t nb,
    const float* a, size_t na
);

/**
 * Destroy an IIR filter context created by `yl_iir_create_df2t_f32()`.
 *
 * Passing `NULL` is allowed and has no effect.
 */
void yl_iir_destroy(yl_iir_ctx* ctx);

/**
 * Return the filter order, equal to `max(nb, na) - 1`.
 *
 * Returns `0` if `ctx` is `NULL`.
 */
size_t yl_iir_order(const yl_iir_ctx* ctx);

/**
 * Reset the internal filter delay state to zero.
 *
 * Passing `NULL` is allowed and has no effect.
 */
void yl_iir_reset(yl_iir_ctx* ctx);

/**
 * Replace the internal filter state.
 *
 * `zi` must contain exactly `yl_iir_order(ctx)` elements.
 * If the filter order is zero, this function is a no-op and returns `0`.
 *
 * Returns:
 * - `0` on success
 * - `1` if `ctx` is `NULL`
 * - `2` if `zi` is `NULL` for a non-zero-order filter
 * - `3` if `zi_len` does not match the filter order
 */
int yl_iir_set_state_f32(yl_iir_ctx* ctx, const float* zi, size_t zi_len);

/**
 * Copy the internal filter state into `zf`.
 *
 * `zf` must have space for exactly `yl_iir_order(ctx)` elements.
 * If the filter order is zero, this function is a no-op and returns `0`.
 *
 * Returns:
 * - `0` on success
 * - `1` if `ctx` is `NULL`
 * - `2` if `zf` is `NULL` for a non-zero-order filter
 * - `3` if `zf_len` does not match the filter order
 */
int yl_iir_get_state_f32(const yl_iir_ctx* ctx, float* zf, size_t zf_len);

/**
 * Process `nx` input samples through the IIR filter.
 *
 * `x` points to the input block and `y` points to the output block.
 * `y` must have space for `nx` samples and may alias `x` for in-place operation.
 *
 * Returns:
 * - `0` on success
 * - `1` if `ctx` is `NULL`, or if `x`/`y` is `NULL` while `nx > 0`
 */
int yl_iir_process_df2t_f32(yl_iir_ctx* ctx, const float* x, float* y, size_t nx);

#ifdef __cplusplus
}
#endif