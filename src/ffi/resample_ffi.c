#include "opendspc_export.h"
#include "opendspc_types.h"
#include "dsp/resample.h"         // internal yl_fft_plan + backend interface
#include <stdlib.h>

YL_EXPORT void* yl_resample_ctx_create(
    int orig_freq, 
    int new_freq,
    int lowpass_filter_width,
    float rolloff,
    unsigned int method,
    float beta
) {
    return (yl_resample_ctx*)yl_resample_create(
        orig_freq, new_freq, lowpass_filter_width, 
        rolloff, 
        (yl_resampling_method)method, 
        beta
    );
}

YL_EXPORT void yl_resample_ctx_destroy(void* r
) {
    yl_resample_destroy((yl_resample_ctx*)r);
}

YL_EXPORT void yl_resample_reset_ffi(void* r
) {
    yl_resample_reset((yl_resample_ctx*)r);
}

YL_EXPORT int yl_resample_out_len_ffi(
    int orig_freq, 
    int new_freq, 
    int in_len
) {
    return (size_t)yl_resample_out_len(
        orig_freq, new_freq, (size_t)in_len);
}

YL_EXPORT int yl_resample_ctx_process(
    const void* r,
    const float* in, 
    int in_len,
    float* out
) {
    return (size_t)yl_resample_process(
        (yl_resample_ctx*)r,
        in, (size_t)in_len,
        out
    );
}