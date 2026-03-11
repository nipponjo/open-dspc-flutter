#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stddef.h>
#include "dsp/polyfit.h"


/* ---------- internal helpers ---------- */

static int yl_polyfit_validate(size_t deg, size_t nmax) {
    if (nmax == 0) return 2;
    (void)deg;
    return 0;
}

static int yl_householder_qr_solve_rowmajor(double* V, double* y, size_t n, size_t p, double* a_out) {
    // In-place QR on V (row-major, size n x p), apply Q^T to y, then backsolve R a = Q^T y.
    // Returns:
    //  0 success
    // -2 rank deficiency (zero diagonal)
    for (size_t k = 0; k < p; k++) {
        double sigma = 0.0;
        for (size_t i = k; i < n; i++) {
            double vik = V[i*p + k];
            sigma += vik * vik;
        }
        double normx = sqrt(sigma);
        if (normx == 0.0) continue;

        double x0 = V[k*p + k];
        double alpha = (x0 >= 0.0) ? -normx : normx;

        double r2 = 0.5 * (alpha*alpha - x0*alpha);
        if (r2 <= 0.0) continue;
        double r = sqrt(r2);

        // store Householder vector v in V[k:n-1, k]
        V[k*p + k] = (x0 - alpha) / (2.0 * r);
        for (size_t i = k + 1; i < n; i++) {
            V[i*p + k] = V[i*p + k] / (2.0 * r);
        }

        // Apply reflector to columns j=k..p-1
        for (size_t j = k; j < p; j++) {
            double s = 0.0;
            for (size_t i = k; i < n; i++) s += V[i*p + k] * V[i*p + j];
            for (size_t i = k; i < n; i++) V[i*p + j] -= 2.0 * V[i*p + k] * s;
        }

        // Apply to y
        {
            double s = 0.0;
            for (size_t i = k; i < n; i++) s += V[i*p + k] * y[i];
            for (size_t i = k; i < n; i++) y[i] -= 2.0 * V[i*p + k] * s;
        }

        // set R diagonal explicitly
        V[k*p + k] = alpha;
        for (size_t i = k + 1; i < n; i++) V[i*p + k] = 0.0;
    }

    // back-substitution on leading p x p upper triangular
    for (ptrdiff_t ii = (ptrdiff_t)p - 1; ii >= 0; --ii) {
        size_t i = (size_t)ii;
        double diag = V[i*p + i];
        if (diag == 0.0) return -2;

        double s = y[i];
        for (size_t j = i + 1; j < p; j++) s -= V[i*p + j] * a_out[j];
        a_out[i] = s / diag;
    }
    return 0;
}

// Convert coefficients from scaled variable xs = s*x + t to original-x coefficients.
// Input:  a_xs[0..deg] for polynomial in xs
// Output: a_x [0..deg] for polynomial in x
// Uses affine composition with Horner:
//
// P(xs) = (...((a_deg)*xs + a_{deg-1})*xs + ... + a0)
// xs = s*x + t
//
// Maintain Q(x) coeffs; each step: Q <- Q*(s*x + t) + a_j
static void yl_polyfit_coeffs_xs_to_x(double s, double t,
                                      const double* a_xs, size_t deg,
                                      double* a_x,
                                      double* tmp /* size deg+1 */) {
    const size_t p = deg + 1;

    // Q = 0
    for (size_t i = 0; i < p; i++) a_x[i] = 0.0;

    // Horner from highest degree to lowest
    for (ptrdiff_t jj = (ptrdiff_t)deg; jj >= 0; --jj) {
        // tmp = Q*(s*x + t)
        // if Q(x)=sum_{k=0..d} q[k] x^k:
        // new[0] = t*q[0]
        // new[k] = t*q[k] + s*q[k-1]
        // new[d+1] = s*q[d]
        tmp[0] = t * a_x[0];
        for (size_t k = 1; k < p; k++) {
            tmp[k] = t * a_x[k] + s * a_x[k - 1];
        }

        // Q = tmp
        for (size_t k = 0; k < p; k++) a_x[k] = tmp[k];

        // add a_j to constant term
        a_x[0] += a_xs[(size_t)jj];
    }
}

/* ---------- public API ---------- */

// One contiguous allocation: V[nmax*p] + y[nmax] + work[p]
yl_polyfit_ctx* yl_polyfit_create_f64(size_t deg, size_t nmax) {
    if (yl_polyfit_validate(deg, nmax)) return NULL;

    yl_polyfit_ctx* ctx = (yl_polyfit_ctx*)calloc(1, sizeof(*ctx));
    if (!ctx) return NULL;

    ctx->deg = deg;
    ctx->p   = deg + 1;
    ctx->nmax = nmax;
    ctx->x_mean = 0.0;
    ctx->x_scale = 1.0;

    const size_t p = ctx->p;
    const size_t Vn = ctx->nmax * p;
    const size_t total = Vn + ctx->nmax + p;

    double* mem = (double*)malloc(total * sizeof(double));
    if (!mem) {
        free(ctx);
        return NULL;
    }

    ctx->V    = mem;
    ctx->y    = mem + Vn;
    ctx->work = mem + Vn + ctx->nmax;

    return ctx;
}

void yl_polyfit_destroy_f64(yl_polyfit_ctx* ctx) {
    if (!ctx) return;
    if (ctx->V) free(ctx->V);
    free(ctx);
}

// Fit polynomial coefficients.
// If mode == YL_POLYFIT_COEFFS_SCALED_XS:
//   returns a_out for xs=(x-x_mean)*x_scale, and yl_polyfit_eval_scaled_f64() can be used.
// If mode == YL_POLYFIT_COEFFS_ORIG_X:
//   returns a_out for original x domain, and yl_polyfit_eval_xdomain_f64() can be used.
//
// Errors:
//  -1 invalid args
//  -3 n > nmax
//  -4 n < p
//  -5 x range is zero
//  -2 rank deficient
int yl_polyfit_fit_f64(yl_polyfit_ctx* ctx,
                       const double* x,
                       const double* y_in,
                       size_t n,
                       yl_polyfit_coeff_mode mode,
                       double* a_out,
                       double* rmse_out /* optional */) {

    // fast path
    if (ctx->deg <= 3) {
        return yl_polyfit_fit_small_f64(ctx, x, y_in, n, mode, a_out, rmse_out);
    }


    if (!ctx || !x || !y_in || !a_out) return -1;
    if (n > ctx->nmax) return -3;

    const size_t p = ctx->p;
    if (n < p) return -4;


    // scale x to ~[-1,1]
    double xmin = x[0], xmax = x[0];
    for (size_t i = 1; i < n; i++) {
        if (x[i] < xmin) xmin = x[i];
        if (x[i] > xmax) xmax = x[i];
    }
    double range = xmax - xmin;
    if (range == 0.0) return -5;

    ctx->x_mean  = 0.5 * (xmin + xmax);
    ctx->x_scale = 2.0 / range;

    // copy y into scratch (will be overwritten)
    memcpy(ctx->y, y_in, n * sizeof(double));

    // build Vandermonde in scaled space into V (row-major)
    for (size_t i = 0; i < n; i++) {
        double xs = (x[i] - ctx->x_mean) * ctx->x_scale;
        double v = 1.0;
        double* row = &ctx->V[i * p];
        for (size_t j = 0; j < p; j++) {
            row[j] = v;
            v *= xs;
        }
    }

    // solve for a_xs (scaled coeffs) into either a_out directly or temp
    double* a_xs = a_out;
    if (mode == YL_POLYFIT_COEFFS_ORIG_X) {
        a_xs = ctx->work; // store scaled coeffs here first
    }

    for (size_t j = 0; j < p; j++) a_xs[j] = 0.0;

    int rc = yl_householder_qr_solve_rowmajor(ctx->V, ctx->y, n, p, a_xs);
    if (rc != 0) return rc;

    // Convert if needed: xs = s*x + t, where s=x_scale, t= -x_mean*x_scale
    if (mode == YL_POLYFIT_COEFFS_ORIG_X) {
        const double s = ctx->x_scale;
        const double t = -ctx->x_mean * ctx->x_scale;
        // use ctx->V first p doubles as temporary? Better: use ctx->V is big but may be used elsewhere.
        // We'll use the start of ctx->V as tmp safely after solve (caller doesn't rely on V contents).
        double* tmp = ctx->V; // at least p doubles available
        yl_polyfit_coeffs_xs_to_x(s, t, a_xs, ctx->deg, a_out, tmp);
    }

    // optional RMSE using the returned coefficient domain
    if (rmse_out) {
        double sse = 0.0;
        if (mode == YL_POLYFIT_COEFFS_SCALED_XS) {
            for (size_t i = 0; i < n; i++) {
                double xs = (x[i] - ctx->x_mean) * ctx->x_scale;
                // Horner in xs domain
                double yh = a_out[p - 1];
                for (ptrdiff_t jj = (ptrdiff_t)p - 2; jj >= 0; --jj) {
                    yh = yh * xs + a_out[(size_t)jj];
                }
                double e = y_in[i] - yh;
                sse += e * e;
            }
        } else { // ORIG_X
            for (size_t i = 0; i < n; i++) {
                // Horner in x domain
                double yh = a_out[p - 1];
                for (ptrdiff_t jj = (ptrdiff_t)p - 2; jj >= 0; --jj) {
                    yh = yh * x[i] + a_out[(size_t)jj];
                }
                double e = y_in[i] - yh;
                sse += e * e;
            }
        }
        *rmse_out = sqrt(sse / (double)n);
    }

    return 0;
}

// Eval for SCALED coeffs (expects coeffs in xs domain; uses ctx scaling)
int yl_polyfit_eval_scaled_f64(const yl_polyfit_ctx* ctx,
                               const double* x,
                               size_t n,
                               const double* a_scaled,
                               double* y_out) {
    if (!ctx || !x || !a_scaled || !y_out) return -1;

    const size_t p = ctx->p;
    for (size_t i = 0; i < n; i++) {
        double xs = (x[i] - ctx->x_mean) * ctx->x_scale;
        double yh = a_scaled[p - 1];
        for (ptrdiff_t jj = (ptrdiff_t)p - 2; jj >= 0; --jj) {
            yh = yh * xs + a_scaled[(size_t)jj];
        }
        y_out[i] = yh;
    }
    return 0;
}

// Eval for ORIGINAL-X coeffs (expects coeffs in x domain; no scaling)
int yl_polyfit_eval_xdomain_f64(const yl_polyfit_ctx* ctx,
                                const double* x,
                                size_t n,
                                const double* a_x,
                                double* y_out) {
    if (!ctx || !x || !a_x || !y_out) return -1;

    const size_t p = ctx->p;
    for (size_t i = 0; i < n; i++) {
        double yh = a_x[p - 1];
        for (ptrdiff_t jj = (ptrdiff_t)p - 2; jj >= 0; --jj) {
            yh = yh * x[i] + a_x[(size_t)jj];
        }
        y_out[i] = yh;
    }
    return 0;
}

// --- small-degree helpers (deg 0..3) ---

// Cholesky for 1..4 SPD matrix stored row-major in A[k*k].
// On success, A contains lower-triangular L such that A_orig = L L^T.
static int yl_chol_decomp_small(double* A, size_t k) {
    // unrolled-ish generic for k<=4
    for (size_t i = 0; i < k; i++) {
        for (size_t j = 0; j <= i; j++) {
            double sum = A[i*k + j];
            for (size_t r = 0; r < j; r++) {
                sum -= A[i*k + r] * A[j*k + r];
            }
            if (i == j) {
                if (sum <= 0.0) return -2; // not SPD / ill-conditioned
                A[i*k + i] = sqrt(sum);
            } else {
                A[i*k + j] = sum / A[j*k + j];
            }
        }
        // zero upper triangle for neatness
        for (size_t j = i + 1; j < k; j++) A[i*k + j] = 0.0;
    }
    return 0;
}

static void yl_chol_solve_small(const double* L, const double* b, size_t k, double* x) {
    // Solve L y = b
    double y[4] = {0,0,0,0};
    for (size_t i = 0; i < k; i++) {
        double sum = b[i];
        for (size_t j = 0; j < i; j++) sum -= L[i*k + j] * y[j];
        y[i] = sum / L[i*k + i];
    }
    // Solve L^T x = y
    for (ptrdiff_t ii = (ptrdiff_t)k - 1; ii >= 0; --ii) {
        size_t i = (size_t)ii;
        double sum = y[i];
        for (size_t j = i + 1; j < k; j++) sum -= L[j*k + i] * x[j];
        x[i] = sum / L[i*k + i];
    }
}

// Fits deg 0..3 using scaled-x normal equations + Cholesky.
// ctx scaling is computed & stored exactly like the QR path.
// Returns 0 on success, negative on failure (rank/conditioning).
int yl_polyfit_fit_small_f64(yl_polyfit_ctx* ctx,
                             const double* x,
                             const double* y_in,
                             size_t n,
                             yl_polyfit_coeff_mode mode,
                             double* a_out,
                             double* rmse_out /* optional */) {
    if (!ctx || !x || !y_in || !a_out) return -1;
    if (n > ctx->nmax) return -3;
    if (ctx->deg > 3) return -1;

    const size_t deg = ctx->deg;
    const size_t p = deg + 1;
    if (n < p) return -4;

    // scaling (same as main fit)
    double xmin = x[0], xmax = x[0];
    for (size_t i = 1; i < n; i++) {
        if (x[i] < xmin) xmin = x[i];
        if (x[i] > xmax) xmax = x[i];
    }
    double range = xmax - xmin;
    if (range == 0.0) return -5;

    ctx->x_mean  = 0.5 * (xmin + xmax);
    ctx->x_scale = 2.0 / range;

    // Build normal equations in scaled domain:
    // A = X^T X, b = X^T y, where columns are [1, xs, xs^2, xs^3]
    double A[16]; // max 4x4
    double bvec[4];
    for (size_t i = 0; i < 16; i++) A[i] = 0.0;
    for (size_t i = 0; i < 4; i++)  bvec[i] = 0.0;

    for (size_t i = 0; i < n; i++) {
        double xs = (x[i] - ctx->x_mean) * ctx->x_scale;

        // powers up to 3
        double v0 = 1.0;
        double v1 = xs;
        double v2 = xs * xs;
        double v3 = v2 * xs;

        const double v[4] = { v0, v1, v2, v3 };

        // accumulate
        for (size_t r = 0; r < p; r++) {
            bvec[r] += v[r] * y_in[i];
            for (size_t c = 0; c <= r; c++) { // fill lower triangle only
                A[r*4 + c] += v[r] * v[c];
            }
        }
    }

    // mirror lower -> full for chol code (expects full, will overwrite upper anyway)
    for (size_t r = 0; r < p; r++) {
        for (size_t c = r + 1; c < p; c++) {
            A[r*4 + c] = A[c*4 + r];
        }
    }

    // Cholesky on p x p (using leading block in A with stride 4)
    // We'll copy to a compact p×p buffer to simplify indexing.
    double Ac[16];
    for (size_t r = 0; r < p; r++) {
        for (size_t c = 0; c < p; c++) {
            Ac[r*p + c] = A[r*4 + c];
        }
    }

    int rc = yl_chol_decomp_small(Ac, p);
    if (rc != 0) return rc;

    // Solve for scaled coeffs
    double a_scaled[4] = {0,0,0,0};
    yl_chol_solve_small(Ac, bvec, p, a_scaled);

    if (mode == YL_POLYFIT_COEFFS_SCALED_XS) {
        for (size_t j = 0; j < p; j++) a_out[j] = a_scaled[j];
    } else {
        // Convert scaled -> original x: xs = s*x + t
        const double s = ctx->x_scale;
        const double t = -ctx->x_mean * ctx->x_scale;

        // tmp needs deg+1
        double tmp[4] = {0,0,0,0};
        yl_polyfit_coeffs_xs_to_x(s, t, a_scaled, deg, a_out, tmp);
    }

    // RMSE optional
    if (rmse_out) {
        double sse = 0.0;
        if (mode == YL_POLYFIT_COEFFS_SCALED_XS) {
            for (size_t i = 0; i < n; i++) {
                double xs = (x[i] - ctx->x_mean) * ctx->x_scale;
                double yh;
                if (deg == 0) {
                    yh = a_out[0];
                } else if (deg == 1) {
                    yh = a_out[1]*xs + a_out[0];
                } else if (deg == 2) {
                    yh = (a_out[2]*xs + a_out[1])*xs + a_out[0];
                } else { // deg==3
                    yh = ((a_out[3]*xs + a_out[2])*xs + a_out[1])*xs + a_out[0];
                }
                double e = y_in[i] - yh;
                sse += e*e;
            }
        } else {
            for (size_t i = 0; i < n; i++) {
                double xi = x[i];
                double yh;
                if (deg == 0) {
                    yh = a_out[0];
                } else if (deg == 1) {
                    yh = a_out[1]*xi + a_out[0];
                } else if (deg == 2) {
                    yh = (a_out[2]*xi + a_out[1])*xi + a_out[0];
                } else { // deg==3
                    yh = ((a_out[3]*xi + a_out[2])*xi + a_out[1])*xi + a_out[0];
                }
                double e = y_in[i] - yh;
                sse += e*e;
            }
        }
        *rmse_out = sqrt(sse / (double)n);
    }

    return 0;
}