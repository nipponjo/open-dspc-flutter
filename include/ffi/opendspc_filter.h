// opendspc_lpc.h
#pragma once
#include "opendspc_export.h"
#include "opendspc_types.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

YL_EXPORT void* yl_iir_ctx_create_df2t_f32(
    const float* b, int nb,
    const float* a, int na
);

YL_EXPORT int yl_iir_ctx_process_f32(
    void* ctx, 
    const float* x, 
    float* y, 
    int nx);

YL_EXPORT void yl_iir_ctx_destroy(void* ctx);

#ifdef __cplusplus
}
#endif