#include "opendspc_export.h"
#include "opendspc_types.h"
#include "opendspc_pitch.h"
#include "dsp/polyfit.h"         // internal yl_fft_plan + backend interface
#include <stdlib.h>

/**
 * Create a polyfit context for a fixed degree and maximum sample count.
 *
 * Memory: one contiguous malloc for scratch (V + y + work) plus the ctx itself.
 * Returns NULL on allocation failure or invalid args.
 */
YL_EXPORT void* yl_polyfit_ctx_create_f64(int deg, int nmax) {
    return (yl_polyfit_ctx*) yl_polyfit_create_f64((size_t)deg, (size_t)nmax);
}

/**
 * Destroy polyfit context.
 */
// void yl_polyfit_destroy_f64(yl_polyfit_ctx* ctx);
YL_EXPORT void yl_polyfit_ctx_destroy_f64(void* ctx) {
    yl_polyfit_destroy_f64((yl_polyfit_ctx*)ctx);
}

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
// int yl_polyfit_fit_f64(yl_polyfit_ctx* ctx,
//                        const double* x,
//                        const double* y,
//                        size_t n,
//                        yl_polyfit_coeff_mode mode,
//                        double* a_out,       // length deg+1
//                        double* rmse_out);   // optional
YL_EXPORT int yl_polyfit_ctx_fit_f64(void* ctx,
                       const double* x,
                       const double* y,
                       int n,
                       unsigned int mode,
                       double* a_out,       // length deg+1
                       double* rmse_out // optional
) {
    return yl_polyfit_fit_f64(
        (yl_polyfit_ctx*)ctx, x, y, (size_t)n,
        (yl_polyfit_coeff_mode)mode, a_out, rmse_out);
} 

/**
 * Evaluate polynomial for SCALED coeffs (expects coeffs in xs domain).
 * Uses ctx->x_mean and ctx->x_scale from the last fit.
 *
 * Returns 0 on success, -1 on invalid args.
 */
YL_EXPORT int yl_polyfit_ctx_eval_scaled_f64(
    const void* ctx,
    const double* x,
    int n,
    const double* a_scaled,
    double* y_out
) {
    return yl_polyfit_eval_scaled_f64(
        (const yl_polyfit_ctx*)ctx,
        x,
        (size_t)n,
        a_scaled,
        y_out
    );
}

/**
 * Evaluate polynomial for ORIGINAL-X coeffs (expects coeffs in x domain).
 * Does not use ctx scaling (ctx is only used for deg/p and validation).
 *
 * Returns 0 on success, -1 on invalid args.
 */
YL_EXPORT int yl_polyfit_ctx_eval_xdomain_f64(
    const void* ctx,
    const double* x,
    int n,
    const double* a_x,
    double* y_out
) {
    return yl_polyfit_eval_xdomain_f64(
        (const yl_polyfit_ctx*)ctx,
        x,
        (size_t)n,
        a_x,
        y_out
    );
}
