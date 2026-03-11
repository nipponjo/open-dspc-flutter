#include "opendspc_export.h"
#include "opendspc_types.h"
#include "opendspc_pitch.h"
#include "feature/pitch.h"         // internal yl_fft_plan + backend interface
#include <stdlib.h>

YL_EXPORT float yl_pitch_acf_frame(
    yl_fft_plan_handle plan_handle,
    const float* input,
    int input_len,
    float* out_acf,
    unsigned int mode,
    float sample_rate,
    float fmin, 
    float fmax
) {
    yl_fft_plan* p = (yl_fft_plan*)plan_handle;
    return yl_execute_pitch_acf_frame(p, input, (size_t)input_len, 
        out_acf, (yl_acf_mode)mode, sample_rate, fmin, fmax);
}
