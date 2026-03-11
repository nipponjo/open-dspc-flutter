#include "dsp/peaks.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

static void yl_zero_result(yl_find_peaks_result* out) {
  if (!out) return;
  memset(out, 0, sizeof(*out));
}

void yl_find_peaks_result_free(yl_find_peaks_result* result) {
  void* block_owner = NULL;
  if (!result) return;

  if (result->plateau_sizes) {
    block_owner = result->plateau_sizes;
  } else if (result->peak_heights) {
    block_owner = result->peak_heights;
  } else if (result->left_thresholds) {
    block_owner = result->left_thresholds;
  } else if (result->prominences) {
    block_owner = result->prominences;
  } else if (result->widths) {
    block_owner = result->widths;
  }

  free(result->peaks);
  free(block_owner);
  yl_zero_result(result);
}

static int yl_bound_array_ok_f32(const yl_peak_bound_f32* bound) {
  return !bound || !bound->enabled || !bound->use_array || bound->values;
}

static int yl_bound_array_ok_size(const yl_peak_bound_size* bound) {
  return !bound || !bound->enabled || !bound->use_array || bound->values;
}

static yl_find_peaks_options yl_default_options(void) {
  yl_find_peaks_options options;
  memset(&options, 0, sizeof(options));
  options.rel_height = 0.5f;
  return options;
}

static int yl_options_are_valid(const yl_find_peaks_options* options) {
  if (!options) return 1;
  if (!yl_bound_array_ok_f32(&options->height.min) ||
      !yl_bound_array_ok_f32(&options->height.max) ||
      !yl_bound_array_ok_f32(&options->threshold.min) ||
      !yl_bound_array_ok_f32(&options->threshold.max) ||
      !yl_bound_array_ok_f32(&options->prominence.min) ||
      !yl_bound_array_ok_f32(&options->prominence.max) ||
      !yl_bound_array_ok_f32(&options->width.min) ||
      !yl_bound_array_ok_f32(&options->width.max) ||
      !yl_bound_array_ok_size(&options->plateau_size.min) ||
      !yl_bound_array_ok_size(&options->plateau_size.max)) {
    return 0;
  }
  return 1;
}

static int yl_check_bounds(const yl_find_peaks_options* options, size_t x_len) {
  const yl_peak_bound_f32* f32_bounds[] = {
      &options->height.min, &options->height.max,
      &options->threshold.min, &options->threshold.max,
      &options->prominence.min, &options->prominence.max,
      &options->width.min, &options->width.max};
  const yl_peak_bound_size* size_bounds[] = {
      &options->plateau_size.min, &options->plateau_size.max};

  size_t i;
  for (i = 0; i < sizeof(f32_bounds) / sizeof(f32_bounds[0]); ++i) {
    if (f32_bounds[i]->enabled && f32_bounds[i]->use_array && !f32_bounds[i]->values) {
      return 0;
    }
  }
  for (i = 0; i < sizeof(size_bounds) / sizeof(size_bounds[0]); ++i) {
    if (size_bounds[i]->enabled && size_bounds[i]->use_array && !size_bounds[i]->values) {
      return 0;
    }
  }
  (void)x_len;
  return 1;
}

static float yl_bound_value_f32(const yl_peak_bound_f32* bound, size_t peak_index) {
  if (!bound || !bound->enabled) return 0.0f;
  return bound->use_array ? bound->values[peak_index] : bound->value;
}

static size_t yl_bound_value_size(const yl_peak_bound_size* bound, size_t peak_index) {
  if (!bound || !bound->enabled) return 0u;
  return bound->use_array ? bound->values[peak_index] : bound->value;
}

static int yl_interval_contains_f32(
    const yl_peak_interval_f32* interval,
    float value,
    size_t peak_index
) {
  if (!interval) return 1;
  if (interval->min.enabled && value < yl_bound_value_f32(&interval->min, peak_index)) {
    return 0;
  }
  if (interval->max.enabled && value > yl_bound_value_f32(&interval->max, peak_index)) {
    return 0;
  }
  return 1;
}

static int yl_interval_contains_size(
    const yl_peak_interval_size* interval,
    size_t value,
    size_t peak_index
) {
  if (!interval) return 1;
  if (interval->min.enabled && value < yl_bound_value_size(&interval->min, peak_index)) {
    return 0;
  }
  if (interval->max.enabled && value > yl_bound_value_size(&interval->max, peak_index)) {
    return 0;
  }
  return 1;
}

static void yl_compact_results(yl_find_peaks_result* out, const uint8_t* keep) {
  size_t src;
  size_t dst = 0;
  for (src = 0; src < out->count; ++src) {
    if (!keep[src]) continue;

    out->peaks[dst] = out->peaks[src];

    if (out->properties & YL_PEAK_PROPS_PLATEAU) {
      out->plateau_sizes[dst] = out->plateau_sizes[src];
      out->left_edges[dst] = out->left_edges[src];
      out->right_edges[dst] = out->right_edges[src];
    }
    if (out->properties & YL_PEAK_PROPS_HEIGHT) {
      out->peak_heights[dst] = out->peak_heights[src];
    }
    if (out->properties & YL_PEAK_PROPS_THRESHOLD) {
      out->left_thresholds[dst] = out->left_thresholds[src];
      out->right_thresholds[dst] = out->right_thresholds[src];
    }
    if (out->properties & YL_PEAK_PROPS_PROMINENCE) {
      out->prominences[dst] = out->prominences[src];
      out->left_bases[dst] = out->left_bases[src];
      out->right_bases[dst] = out->right_bases[src];
    }
    if (out->properties & YL_PEAK_PROPS_WIDTH) {
      out->widths[dst] = out->widths[src];
      out->width_heights[dst] = out->width_heights[src];
      out->left_ips[dst] = out->left_ips[src];
      out->right_ips[dst] = out->right_ips[src];
    }
    ++dst;
  }
  out->count = dst;
}

static int yl_alloc_result(
    yl_find_peaks_result* out,
    size_t capacity,
    uint32_t properties,
    int need_priority,
    int need_prominence_scratch
) {
  char* block;
  char* cursor;
  size_t block_size = 0u;
  yl_zero_result(out);
  out->capacity = capacity;
  out->properties = properties;

  if (capacity == 0) return 1;

  out->peaks = (size_t*)malloc(capacity * sizeof(size_t));

  if (properties & YL_PEAK_PROPS_PLATEAU) {
    block_size += 3u * capacity * sizeof(size_t);
  }

  if (need_priority) {
    block_size += capacity * sizeof(float);
  }

  if (properties & YL_PEAK_PROPS_THRESHOLD) {
    block_size += 2u * capacity * sizeof(float);
  }

  if (need_prominence_scratch) {
    block_size += capacity * sizeof(float);
    block_size += 2u * capacity * sizeof(size_t);
  }

  if (properties & YL_PEAK_PROPS_WIDTH) {
    block_size += 4u * capacity * sizeof(float);
  }

  block = block_size ? (char*)malloc(block_size) : NULL;
  cursor = block;

  if (properties & YL_PEAK_PROPS_PLATEAU) {
    out->plateau_sizes = (size_t*)cursor;
    cursor += capacity * sizeof(size_t);
    out->left_edges = (size_t*)cursor;
    cursor += capacity * sizeof(size_t);
    out->right_edges = (size_t*)cursor;
    cursor += capacity * sizeof(size_t);
  }

  if (need_priority) {
    out->peak_heights = (float*)cursor;
    cursor += capacity * sizeof(float);
  }

  if (properties & YL_PEAK_PROPS_THRESHOLD) {
    out->left_thresholds = (float*)cursor;
    cursor += capacity * sizeof(float);
    out->right_thresholds = (float*)cursor;
    cursor += capacity * sizeof(float);
  }

  if (need_prominence_scratch) {
    out->prominences = (float*)cursor;
    cursor += capacity * sizeof(float);
    out->left_bases = (size_t*)cursor;
    cursor += capacity * sizeof(size_t);
    out->right_bases = (size_t*)cursor;
    cursor += capacity * sizeof(size_t);
  }

  if (properties & YL_PEAK_PROPS_WIDTH) {
    out->widths = (float*)cursor;
    cursor += capacity * sizeof(float);
    out->width_heights = (float*)cursor;
    cursor += capacity * sizeof(float);
    out->left_ips = (float*)cursor;
    cursor += capacity * sizeof(float);
    out->right_ips = (float*)cursor;
    cursor += capacity * sizeof(float);
  }

  if (!out->peaks ||
      (block_size && !block) ||
      ((properties & YL_PEAK_PROPS_PLATEAU) &&
       (!out->plateau_sizes || !out->left_edges || !out->right_edges)) ||
      (need_priority && !out->peak_heights) ||
      ((properties & YL_PEAK_PROPS_THRESHOLD) &&
       (!out->left_thresholds || !out->right_thresholds)) ||
      (need_prominence_scratch &&
       (!out->prominences || !out->left_bases || !out->right_bases)) ||
      ((properties & YL_PEAK_PROPS_WIDTH) &&
       (!out->widths || !out->width_heights || !out->left_ips || !out->right_ips))) {
    yl_find_peaks_result_free(out);
    return 0;
  }
  return 1;
}

static void yl_find_local_maxima(
    const float* x,
    size_t x_len,
    yl_find_peaks_result* out
) {
  size_t i = 1;
  const size_t last = x_len - 1;

  out->count = 0;
  while (i < last) {
    if (x[i - 1] < x[i]) {
      size_t i_ahead = i + 1;
      while (i_ahead < last && x[i_ahead] == x[i]) {
        ++i_ahead;
      }
      if (x[i_ahead] < x[i]) {
        const size_t slot = out->count++;
        const size_t left_edge = i;
        const size_t right_edge = i_ahead - 1;
        out->peaks[slot] = (left_edge + right_edge) / 2;
        if (out->left_edges) out->left_edges[slot] = left_edge;
        if (out->right_edges) out->right_edges[slot] = right_edge;
        if (out->plateau_sizes) out->plateau_sizes[slot] = right_edge - left_edge + 1;
        i = i_ahead;
      }
    }
    ++i;
  }
}

static int yl_priority_higher(const yl_find_peaks_result* out, size_t lhs, size_t rhs) {
  const float pl = out->peak_heights[lhs];
  const float pr = out->peak_heights[rhs];
  if (pl > pr) return 1;
  if (pl < pr) return 0;
  return out->peaks[lhs] < out->peaks[rhs];
}

static void yl_sort_by_priority_desc(size_t* order, size_t n, const yl_find_peaks_result* out) {
  size_t i;
  for (i = 1; i < n; ++i) {
    size_t j = i;
    const size_t value = order[i];
    while (j > 0 && yl_priority_higher(out, value, order[j - 1])) {
      order[j] = order[j - 1];
      --j;
    }
    order[j] = value;
  }
}

static void yl_select_by_distance(yl_find_peaks_result* out, float distance) {
  size_t i;
  const size_t n = out->count;
  const size_t min_distance = (size_t)ceilf(distance);
  uint8_t* keep = (uint8_t*)malloc(n * sizeof(uint8_t));
  size_t* order = (size_t*)malloc(n * sizeof(size_t));

  if (n == 0) return;
  if (!keep || !order) goto cleanup;

  memset(keep, 1, n * sizeof(uint8_t));
  for (i = 0; i < n; ++i) {
    order[i] = i;
  }

  yl_sort_by_priority_desc(order, n, out);

  for (i = 0; i < n; ++i) {
    size_t center_pos;
    size_t left;
    size_t right;
    const size_t center = order[i];
    if (!keep[center]) continue;

    center_pos = out->peaks[center];

    left = center;
    while (left > 0) {
      const size_t prev = left - 1;
      if (center_pos - out->peaks[prev] >= min_distance) break;
      keep[prev] = 0;
      left = prev;
    }

    right = center + 1;
    while (right < n) {
      if (out->peaks[right] - center_pos >= min_distance) break;
      keep[right] = 0;
      ++right;
    }
    keep[center] = 1;
  }

  yl_compact_results(out, keep);

cleanup:
  free(keep);
  free(order);
}

static void yl_compute_prominences(
    const float* x,
    size_t x_len,
    yl_find_peaks_result* out,
    size_t wlen
) {
  size_t p;
  for (p = 0; p < out->count; ++p) {
    const size_t peak = out->peaks[p];
    size_t i_min = 0;
    size_t i_max = x_len - 1;
    size_t i;
    size_t left_base = peak;
    size_t right_base = peak;
    float left_min = x[peak];
    float right_min = x[peak];

    if (wlen >= 2) {
      const size_t half = wlen / 2;
      i_min = (peak > half) ? (peak - half) : 0;
      i_max = peak + half;
      if (i_max >= x_len) i_max = x_len - 1;
    }

    i = peak;
    while (1) {
      if (x[i] < left_min) {
        left_min = x[i];
        left_base = i;
      }
      if (i == i_min || x[i] > x[peak]) break;
      --i;
    }

    i = peak;
    while (1) {
      if (x[i] < right_min) {
        right_min = x[i];
        right_base = i;
      }
      if (i == i_max || x[i] > x[peak]) break;
      ++i;
    }

    out->left_bases[p] = left_base;
    out->right_bases[p] = right_base;
    out->prominences[p] = x[peak] - ((left_min > right_min) ? left_min : right_min);
  }
}

static void yl_compute_widths(
    const float* x,
    yl_find_peaks_result* out,
    float rel_height
) {
  size_t p;
  for (p = 0; p < out->count; ++p) {
    const size_t peak = out->peaks[p];
    const size_t left_base = out->left_bases[p];
    const size_t right_base = out->right_bases[p];
    const float height = x[peak] - out->prominences[p] * rel_height;
    size_t i;
    float left_ip;
    float right_ip;

    out->width_heights[p] = height;

    i = peak;
    while (i > left_base && height < x[i]) {
      --i;
    }
    left_ip = (float)i;
    if (x[i] < height && i + 1 <= peak) {
      left_ip += (height - x[i]) / (x[i + 1] - x[i]);
    }

    i = peak;
    while (i < right_base && height < x[i]) {
      ++i;
    }
    right_ip = (float)i;
    if (x[i] < height && i > peak) {
      right_ip -= (height - x[i]) / (x[i - 1] - x[i]);
    }

    out->left_ips[p] = left_ip;
    out->right_ips[p] = right_ip;
    out->widths[p] = right_ip - left_ip;
  }
}

static void yl_apply_plateau_condition(
    const yl_find_peaks_options* options,
    yl_find_peaks_result* out,
    uint8_t* keep
) {
  size_t i;
  for (i = 0; i < out->count; ++i) {
    keep[i] = (uint8_t)yl_interval_contains_size(
        &options->plateau_size, out->plateau_sizes[i], out->peaks[i]);
  }
  yl_compact_results(out, keep);
}

static void yl_apply_height_condition(
    const float* x,
    const yl_find_peaks_options* options,
    yl_find_peaks_result* out,
    uint8_t* keep
) {
  size_t i;
  for (i = 0; i < out->count; ++i) {
    out->peak_heights[i] = x[out->peaks[i]];
    keep[i] = (uint8_t)yl_interval_contains_f32(
        &options->height, out->peak_heights[i], out->peaks[i]);
  }
  yl_compact_results(out, keep);
}

static void yl_apply_threshold_condition(
    const float* x,
    const yl_find_peaks_options* options,
    yl_find_peaks_result* out,
    uint8_t* keep
) {
  size_t i;
  for (i = 0; i < out->count; ++i) {
    const size_t peak = out->peaks[i];
    const float left = x[peak] - x[peak - 1];
    const float right = x[peak] - x[peak + 1];
    const float min_threshold = (left < right) ? left : right;
    const float max_threshold = (left > right) ? left : right;

    out->left_thresholds[i] = left;
    out->right_thresholds[i] = right;
    keep[i] = 1;
    if (options->threshold.min.enabled &&
        min_threshold < yl_bound_value_f32(&options->threshold.min, peak)) {
      keep[i] = 0;
    }
    if (options->threshold.max.enabled &&
        max_threshold > yl_bound_value_f32(&options->threshold.max, peak)) {
      keep[i] = 0;
    }
  }
  yl_compact_results(out, keep);
}

static void yl_apply_prominence_condition(
    const yl_find_peaks_options* options,
    yl_find_peaks_result* out,
    uint8_t* keep
) {
  size_t i;
  for (i = 0; i < out->count; ++i) {
    keep[i] = (uint8_t)yl_interval_contains_f32(
        &options->prominence, out->prominences[i], out->peaks[i]);
  }
  yl_compact_results(out, keep);
}

static void yl_apply_width_condition(
    const yl_find_peaks_options* options,
    yl_find_peaks_result* out,
    uint8_t* keep
) {
  size_t i;
  for (i = 0; i < out->count; ++i) {
    keep[i] = (uint8_t)yl_interval_contains_f32(
        &options->width, out->widths[i], out->peaks[i]);
  }
  yl_compact_results(out, keep);
}

int find_peaks(
    const float* x,
    size_t x_len,
    const yl_find_peaks_options* options,
    yl_find_peaks_result* out
) {
  yl_find_peaks_options defaults;
  const yl_find_peaks_options* cfg = options;
  yl_find_peaks_result tmp;
  uint8_t* keep = NULL;
  uint32_t properties = 0u;
  int need_plateau;
  int need_height;
  int need_threshold;
  int need_distance;
  int need_prominence;
  int need_width;
  int need_priority;
  int need_prominence_scratch;
  float rel_height;

  if (!x || !out) return 1;
  if (!cfg) {
    defaults = yl_default_options();
    cfg = &defaults;
  }
  if (!yl_options_are_valid(cfg)) return 1;
  yl_zero_result(&tmp);

  if (!yl_check_bounds(cfg, x_len)) return 5;
  if (cfg->distance_enabled && cfg->distance < 1.0f) return 3;

  rel_height = cfg->rel_height_enabled ? cfg->rel_height : 0.5f;
  if (rel_height < 0.0f) return 4;

  if (x_len < 3) {
    yl_zero_result(out);
    return 0;
  }

  need_plateau = cfg->plateau_size.min.enabled || cfg->plateau_size.max.enabled;
  need_height = cfg->height.min.enabled || cfg->height.max.enabled;
  need_threshold = cfg->threshold.min.enabled || cfg->threshold.max.enabled;
  need_distance = cfg->distance_enabled;
  need_prominence = cfg->prominence.min.enabled || cfg->prominence.max.enabled;
  need_width = cfg->width.min.enabled || cfg->width.max.enabled;
  need_priority = need_height || need_distance;
  need_prominence_scratch = need_prominence || need_width;

  if (need_plateau) properties |= YL_PEAK_PROPS_PLATEAU;
  if (need_height) properties |= YL_PEAK_PROPS_HEIGHT;
  if (need_threshold) properties |= YL_PEAK_PROPS_THRESHOLD;
  if (need_prominence) properties |= YL_PEAK_PROPS_PROMINENCE;
  if (need_width) properties |= YL_PEAK_PROPS_WIDTH;

  if (!yl_alloc_result(&tmp, x_len / 2u + 1u, properties, need_priority, need_prominence_scratch)) {
    return 2;
  }
  keep = (uint8_t*)malloc(tmp.capacity * sizeof(uint8_t));
  if (!keep) {
    yl_find_peaks_result_free(&tmp);
    return 2;
  }

  yl_find_local_maxima(x, x_len, &tmp);

  if (need_plateau) {
    yl_apply_plateau_condition(cfg, &tmp, keep);
  }

  if (need_height) {
    yl_apply_height_condition(x, cfg, &tmp, keep);
  }

  if (need_threshold) {
    yl_apply_threshold_condition(x, cfg, &tmp, keep);
  }

  if (need_distance) {
    if (!need_height) {
      size_t i;
      for (i = 0; i < tmp.count; ++i) {
        tmp.peak_heights[i] = x[tmp.peaks[i]];
      }
    }
    yl_select_by_distance(&tmp, cfg->distance);
  }

  if (need_prominence) {
    yl_compute_prominences(x, x_len, &tmp, cfg->wlen_enabled ? cfg->wlen : 0u);
  }

  if (need_prominence) {
    yl_apply_prominence_condition(cfg, &tmp, keep);
  }

  if (need_width) {
    if (!need_prominence) {
      yl_compute_prominences(x, x_len, &tmp, cfg->wlen_enabled ? cfg->wlen : 0u);
    }
    yl_compute_widths(x, &tmp, rel_height);
    yl_apply_width_condition(cfg, &tmp, keep);
  }

  free(keep);
  *out = tmp;
  return 0;
}

int yl_find_peaks_f32(
    const float* x,
    size_t x_len,
    const yl_find_peaks_options* options,
    yl_find_peaks_result* out
) {
  return find_peaks(x, x_len, options, out);
}
