#define _USE_MATH_DEFINES
#include <math.h>
#include "dsp/window.h"

static inline void yl_window_coeffs(yl_window_type type, float* a0, float* a1, float* a2) {
  switch (type) {
    case YL_WIN_HANN:     *a0 = 0.5f;  *a1 = 0.5f;  *a2 = 0.0f;  break;
    case YL_WIN_HAMMING:  *a0 = 0.54f; *a1 = 0.46f; *a2 = 0.0f;  break;
    case YL_WIN_BLACKMAN: *a0 = 0.42f; *a1 = 0.5f;  *a2 = 0.08f; break;
    default:              *a0 = 1.0f;  *a1 = 0.0f;  *a2 = 0.0f;  break; // rect
  }
}

void yl_window_generate(float* w, int N, yl_window_type type) {
  if (type == 0) return;

  float a0, a1, a2;
  yl_window_coeffs(type, &a0, &a1, &a2);

  const float two_pi = 2.0f * (float)M_PI;
  const float phase_inc = two_pi / (float)N;   // periodic STFT form
  float phase = 0.0f;

  for (int n = 0; n < N; n++) {
    const float c1 = cosf(phase);
    const float c2 = cosf(2.0f * phase);
    w[n] = a0 - a1 * c1 + a2 * c2;
    phase += phase_inc;
  }
}

void yl_window_apply_inplace(float* input, int N, yl_window_type type) {
  if (type == 0) return;

  float a0, a1, a2;
  yl_window_coeffs(type, &a0, &a1, &a2);

  const float two_pi = 2.0f * (float)M_PI;
  const float phase_inc = two_pi / (float)N;   // periodic STFT form
  float phase = 0.0f;

  for (int n = 0; n < N; n++) {
    const float c1 = cosf(phase);
    const float c2 = cosf(2.0f * phase);
    const float wn = a0 - a1 * c1 + a2 * c2;
    input[n] = wn * input[n]; 
    phase += phase_inc;
  }
}
