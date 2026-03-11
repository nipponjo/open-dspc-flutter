#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Output coefficient domain
typedef enum yl_polyfit_coeff_mode {
    // Coeffs for xs=(x-x_mean)*x_scale  (recommended/stable)
    YL_POLYFIT_COEFFS_SCALED_XS = 0,
    // Coeffs for original x domain
    YL_POLYFIT_COEFFS_ORIG_X    = 1
} yl_polyfit_coeff_mode;

// Polyfit context (double precision)
typedef struct yl_polyfit_ctx {
    size_t deg;     // polynomial degree
    size_t p;       // deg + 1
    size_t nmax;    // max supported n

    // last-fit scaling (used by yl_polyfit_eval_scaled_f64)
    double x_mean;
    double x_scale; // xs = (x - x_mean) * x_scale

    // contiguous scratch allocation
    double* V;      // nmax * p (row-major)
    double* y;      // nmax
    double* work;   // p (small scratch)
} yl_polyfit_ctx;

/**
 * Create a polyfit context for a fixed degree and maximum sample count.
 *
 * Memory: one contiguous malloc for scratch (V + y + work) plus the ctx itself.
 * Returns NULL on allocation failure or invalid args.
 */
yl_polyfit_ctx* yl_polyfit_create_f64(size_t deg, size_t nmax);

/**
 * Destroy polyfit context.
 */
void yl_polyfit_destroy_f64(yl_polyfit_ctx* ctx);

/**
 * Fit polynomial coefficients (least squares) with stable x scaling to ~[-1,1].
 *
 * On success:
 *  - ctx->x_mean / ctx->x_scale are updated (based on min/max of x in this fit)
 *  - a_out contains coefficients in the requested mode:
 *      - YL_POLYFIT_COEFFS_SCALED_XS: polynomial in xs=(x-x_mean)*x_scale
 *      - YL_POLYFIT_COEFFS_ORIG_X   : polynomial in original x domain
 *  - rmse_out (if non-NULL) gets RMSE in y units
 *
 * Returns 0 on success; otherwise:
 *  -1 invalid args
 *  -3 n > ctx->nmax
 *  -4 n < (deg+1)
 *  -5 zero x range (all x equal)
 *  -2 rank deficient / non-SPD in the small-degree path
 */
int yl_polyfit_fit_f64(yl_polyfit_ctx* ctx,
                       const double* x,
                       const double* y,
                       size_t n,
                       yl_polyfit_coeff_mode mode,
                       double* a_out,       // length deg+1
                       double* rmse_out);   // optional

/**
 * Fast-path fit for deg 0..3 only (normal equations in scaled domain + Cholesky).
 *
 * This is exposed in case you want to call it directly.
 * Typical usage: yl_polyfit_fit_f64() calls it internally when ctx->deg <= 3.
 */
int yl_polyfit_fit_small_f64(yl_polyfit_ctx* ctx,
                             const double* x,
                             const double* y,
                             size_t n,
                             yl_polyfit_coeff_mode mode,
                             double* a_out,       // length deg+1
                             double* rmse_out);   // optional

/**
 * Evaluate polynomial for SCALED coeffs (expects coeffs in xs domain).
 * Uses ctx->x_mean and ctx->x_scale from the last fit.
 *
 * Returns 0 on success, -1 on invalid args.
 */
int yl_polyfit_eval_scaled_f64(const yl_polyfit_ctx* ctx,
                               const double* x,
                               size_t n,
                               const double* a_scaled, // length deg+1
                               double* y_out);

/**
 * Evaluate polynomial for ORIGINAL-X coeffs (expects coeffs in x domain).
 * Does not use ctx scaling (ctx is only used for deg/p and validation).
 *
 * Returns 0 on success, -1 on invalid args.
 */
int yl_polyfit_eval_xdomain_f64(const yl_polyfit_ctx* ctx,
                                const double* x,
                                size_t n,
                                const double* a_x, // length deg+1
                                double* y_out);

#ifdef __cplusplus
} // extern "C"
#endif
