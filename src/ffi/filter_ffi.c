#include "opendspc_export.h"
#include "opendspc_types.h"
#include "opendspc_filter.h"     // public prototypes
#include "dsp/filter.h"     
#include <stdlib.h>


YL_EXPORT void* yl_iir_ctx_create_df2t_f32(
    const float* b, int nb,
    const float* a, int na
) {
    return (void*)yl_iir_create_df2t_f32(b, (size_t)nb, a, (size_t)na);
}

YL_EXPORT int yl_iir_ctx_process_f32(
    void* ctx, 
    const float* x, 
    float* y, 
    int nx
) {
    return yl_iir_process_df2t_f32((yl_iir_ctx*)ctx, x, y, (size_t)nx);
}

YL_EXPORT void yl_iir_ctx_destroy(void* ctx) {
    yl_iir_destroy((yl_iir_ctx*)ctx);
}