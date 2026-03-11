// opendspc_lpc.h
#pragma once
#include "opendspc_export.h"
#include "opendspc_types.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

YL_EXPORT void* yl_lpc_ctx_create(int m);
YL_EXPORT int yl_lpc_ctx_order(void* ctx);

YL_EXPORT float yl_lpc_ctx_process_frame(
    void* ctx,
    const float* y,
    int L,
    int method,
    int sptk,
    float* out
);

YL_EXPORT void yl_lpc_ctx_destroy(void* ctx);

YL_EXPORT float yl_lpc_process_single(
    const float* y,
    int L,
    int m,
    int method,
    int sptk,
    float* out // length (m + 1)
);

#ifdef __cplusplus
}
#endif
