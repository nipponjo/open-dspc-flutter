// opendspc_lpc.h
#pragma once
#include "opendspc_export.h"
#include "opendspc_types.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

YL_EXPORT void* yl_polyfit_ctx_create_f64(int deg, int nmax);
YL_EXPORT void yl_polyfit_ctx_destroy_f64(void* ctx);
YL_EXPORT int yl_polyfit_ctx_fit_f64(void* ctx,
                       const double* x,
                       const double* y,
                       int n,
                       unsigned int mode,
                       double* a_out,       // length deg+1
                       double* rmse_out // optional
);

YL_EXPORT int yl_polyfit_ctx_eval_scaled_f64(
    const void* ctx,
    const double* x,
    int n,
    const double* a_scaled,
    double* y_out
);

YL_EXPORT int yl_polyfit_ctx_eval_xdomain_f64(
    const void* ctx,
    const double* x,
    int n,
    const double* a_x,
    double* y_out
);

#ifdef __cplusplus
}
#endif