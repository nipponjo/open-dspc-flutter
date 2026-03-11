#include "feature/pitch.h"
#include <math.h>
#include <stdlib.h>

static inline int yl_clamp_i(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

float yl_execute_pitch_acf_frame(
    yl_fft_plan* plan,
    const float* input,
    size_t input_len,
    float* out_acf,
    yl_acf_mode mode,
    float sample_rate,
    float fmin,
    float fmax
) {
    if (!plan || !input || !out_acf) return 0.0f;
    if (input_len < 8) return 0.0f;

    // Basic parameter validation
    if (!(sample_rate > 0.0f) || !(fmin > 0.0f) || !(fmax > 0.0f)) return 0.0f;
    if (fmin >= fmax) return 0.0f;

    // Compute ACF up to input_len lags (0..input_len-1)
    yl_fft_execute_autocorr(plan, input, input_len, out_acf, input_len, mode);

    // Lag range for pitch
    int min_lag = (int)floorf(sample_rate / fmax);
    int max_lag = (int)ceilf(sample_rate / fmin);

    // Clamp to what we actually have in out_acf
    // Need +/-1 for parabolic interpolation and peak test, so clamp inside [1, input_len-2]
    const int max_valid = (int)input_len - 2;
    min_lag = yl_clamp_i(min_lag, 1, max_valid);
    max_lag = yl_clamp_i(max_lag, 1, max_valid);
    if (min_lag >= max_lag) return 0.0f;

    // Peak picking: look for local maxima in [min_lag, max_lag]
    int best_lag = 0;
    float best_val = -INFINITY;

    for (int lag = min_lag; lag <= max_lag; ++lag) {
        const float v = out_acf[lag];
        // Require local maximum to avoid just taking the ramp near lag=0
        if (v >= out_acf[lag - 1] && v >= out_acf[lag + 1]) {
            if (v > best_val) {
                best_val = v;
                best_lag = lag;
            }
        }
    }

    if (best_lag == 0) return 0.0f;

    // Voicing / confidence threshold:
    // If you're using NACF (normalized), values are typically [0..1].
    // For raw ACF, you should either use NACF mode or normalize here.
    const float thresh = (mode == YL_ACF_NORM_R0) ? 0.3f : 0.0f;
    if (best_val < thresh) return 0.0f;

    // Parabolic interpolation around best_lag
    {
        const float alpha = out_acf[best_lag - 1];
        const float beta  = out_acf[best_lag];
        const float gamma = out_acf[best_lag + 1];

        const float denom = (alpha - 2.0f * beta + gamma);
        float p = 0.0f;
        if (fabsf(denom) > 1e-12f) {
            p = 0.5f * (alpha - gamma) / denom;
            // Clamp p to reasonable range to avoid wild jumps
            if (p > 0.5f) p = 0.5f;
            if (p < -0.5f) p = -0.5f;
        }

        const float refined_lag = (float)best_lag + p;
        if (!(refined_lag > 0.0f)) return 0.0f;

        const float pitch = sample_rate / refined_lag;
        // Final sanity check: keep within [fmin,fmax]
        if (pitch < fmin || pitch > fmax) return 0.0f;
        return pitch;
    }
}