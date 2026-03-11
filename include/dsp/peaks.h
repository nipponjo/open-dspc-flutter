#pragma once

#include <stddef.h>
#include <stdint.h>

#include "opendspc_export.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  int enabled;
  int use_array;
  float value;
  const float* values;  // Optional full-length `x`-shaped array.
} yl_peak_bound_f32;

typedef struct {
  yl_peak_bound_f32 min;
  yl_peak_bound_f32 max;
} yl_peak_interval_f32;

typedef struct {
  int enabled;
  int use_array;
  size_t value;
  const size_t* values;  // Optional full-length `x`-shaped array.
} yl_peak_bound_size;

typedef struct {
  yl_peak_bound_size min;
  yl_peak_bound_size max;
} yl_peak_interval_size;

typedef struct {
  yl_peak_interval_f32 height;
  yl_peak_interval_f32 threshold;
  int distance_enabled;
  float distance;
  yl_peak_interval_f32 prominence;
  yl_peak_interval_f32 width;
  int wlen_enabled;
  size_t wlen;
  int rel_height_enabled;
  float rel_height;  // SciPy default: 0.5
  yl_peak_interval_size plateau_size;
} yl_find_peaks_options;

enum {
  YL_PEAK_PROPS_PLATEAU = 1u << 0,
  YL_PEAK_PROPS_HEIGHT = 1u << 1,
  YL_PEAK_PROPS_THRESHOLD = 1u << 2,
  YL_PEAK_PROPS_PROMINENCE = 1u << 3,
  YL_PEAK_PROPS_WIDTH = 1u << 4
};

typedef struct {
  size_t count;
  size_t capacity;
  uint32_t properties;

  size_t* peaks;

  size_t* plateau_sizes;
  size_t* left_edges;
  size_t* right_edges;

  float* peak_heights;

  float* left_thresholds;
  float* right_thresholds;

  float* prominences;
  size_t* left_bases;
  size_t* right_bases;

  float* widths;
  float* width_heights;
  float* left_ips;
  float* right_ips;
} yl_find_peaks_result;

// `options == NULL` uses SciPy defaults.
// `out` receives owned buffers and must later be released with
// `yl_find_peaks_result_free()`. Reusing a non-empty result requires freeing it
// first.
// Return codes:
// 0 success
// 1 invalid arguments
// 2 allocation failure
// 3 invalid `distance`
// 4 invalid `rel_height`
// 5 invalid array-backed bound
YL_EXPORT int find_peaks(
    const float* x,
    size_t x_len,
    const yl_find_peaks_options* options,
    yl_find_peaks_result* out
);

YL_EXPORT int yl_find_peaks_f32(
    const float* x,
    size_t x_len,
    const yl_find_peaks_options* options,
    yl_find_peaks_result* out
);

YL_EXPORT void yl_find_peaks_result_free(yl_find_peaks_result* result);

#ifdef __cplusplus
}
#endif
