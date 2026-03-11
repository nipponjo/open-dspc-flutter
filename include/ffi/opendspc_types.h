#pragma once

typedef enum {
    YL_SPEC_MAG = 1,
    YL_SPEC_POWER = 2,
    YL_SPEC_DB = 3,
} yl_spec_mode;

typedef enum {
    YL_WIN_HANN = 1,
    YL_WIN_HAMMING = 2,
    YL_WIN_BLACKMAN = 3,
} yl_window_type;

typedef enum {
  YL_ACF_RAW = 0,        // just IFFT(|FFT(x)|^2)
  YL_ACF_NORM_R0 = 1     // divide by r[0] so r[0]=1
} yl_acf_mode;


typedef void* yl_fft_plan_handle;
