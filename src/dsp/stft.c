#include "dsp/stft.h"
#include <stdlib.h>
#include <string.h>

struct yl_stft_ctx {
  yl_fft_plan* fft;

  uint32_t n_fft;
  uint32_t win_len;
  uint32_t hop;
  uint32_t bins;

  int mean_subtract;
  int center;

  yl_window_type win_type;
  float* window;       // win_len

  // Streaming buffer of size win_len
  float* ring;         // win_len
  uint32_t ring_fill;  // 0..win_len

  // Scratch FFT input length n_fft (could later come from backend getter)
  float* time;         // n_fft
};

static uint32_t yl_stft_center_pad(const yl_stft_ctx* s) {
  if (!s || !s->center) return 0u;
  return s->win_len / 2u;
}

static void yl_stft_prime_ring(yl_stft_ctx* s) {
  if (!s) return;
  s->ring_fill = yl_stft_center_pad(s);
  if (s->ring_fill > 0u) {
    memset(s->ring, 0, (size_t)s->ring_fill * sizeof(float));
  }
}

yl_stft_ctx* yl_stft_create(const yl_stft_cfg* cfg) {
  if (!cfg) return NULL;
  if (cfg->n_fft == 0 || cfg->win_len == 0 || cfg->hop == 0) return NULL;
  if (cfg->win_len > cfg->n_fft) return NULL;

  yl_stft_ctx* s = (yl_stft_ctx*)calloc(1, sizeof(*s));
  if (!s) return NULL;

  s->n_fft = cfg->n_fft;
  s->win_len = cfg->win_len;
  s->hop = cfg->hop;
  s->bins = (cfg->n_fft / 2u) + 1u;
  s->mean_subtract = cfg->mean_subtract ? 1 : 0;
  s->center = cfg->center ? 1 : 0;
  s->win_type = cfg->win;

  s->fft = yl_fft_create_r2c((size_t)cfg->n_fft);
  if (!s->fft) goto fail;

  s->window = (float*)malloc((size_t)s->win_len * sizeof(float));
  if (!s->window) goto fail;
  yl_window_generate(s->window, (int)s->win_len, s->win_type);

  s->ring = (float*)malloc((size_t)s->win_len * sizeof(float));
  if (!s->ring) goto fail;
  yl_stft_prime_ring(s);

  s->time = (float*)malloc((size_t)s->n_fft * sizeof(float));
  if (!s->time) goto fail;

  return s;

fail:
  yl_stft_destroy(s);
  return NULL;
}

void yl_stft_destroy(yl_stft_ctx* s) {
  if (!s) return;
  if (s->fft) yl_fft_destroy(s->fft);
  free(s->window);
  free(s->ring);
  free(s->time);
  free(s);
}

void yl_stft_reset(yl_stft_ctx* s) {
  if (!s) return;
  yl_stft_prime_ring(s);
  memset(s->time, 0, (size_t)s->n_fft * sizeof(float));
}

uint32_t yl_stft_bins(const yl_stft_ctx* s) {
  return s ? s->bins : 0u;
}

uint32_t yl_stft_nfft(const yl_stft_ctx* s) {
  return s ? s->n_fft : 0u;
}

uint32_t yl_stft_hop(const yl_stft_ctx* s) {
  return s ? s->hop : 0u;
}

uint32_t yl_stft_win_len(const yl_stft_ctx* s) {
  return s ? s->win_len : 0u;
}

static void yl_stft_prepare_frame(yl_stft_ctx* s, const float* frame) {
  // Optional mean subtraction
  float mean = 0.0f;
  if (s->mean_subtract) {
    for (uint32_t i = 0; i < s->win_len; ++i) mean += frame[i];
    mean /= (float)s->win_len;
  }

  // Window into time buffer
  for (uint32_t i = 0; i < s->win_len; ++i) {
    float v = frame[i] - mean;
    s->time[i] = v * s->window[i];
  }

  // Zero pad
  if (s->win_len < s->n_fft) {
    memset(s->time + s->win_len, 0, (size_t)(s->n_fft - s->win_len) * sizeof(float));
  }
}

static void yl_stft_advance_ring_full(yl_stft_ctx* s) {
  if (s->hop >= s->win_len) {
    s->ring_fill = 0;
  } else {
    const uint32_t keep = s->win_len - s->hop;
    memmove(s->ring, s->ring + s->hop, (size_t)keep * sizeof(float));
    s->ring_fill = keep;
  }
}

size_t yl_stft_push_r2c(
  yl_stft_ctx* s,
  const float* input,
  size_t input_len,
  float* out_re,
  float* out_im,
  size_t out_frames_cap
) {
  if (!s || (!input && input_len)) return 0;
  if (out_frames_cap && (!out_re || !out_im)) return 0;

  size_t frames = 0;
  size_t idx = 0;

  while (idx < input_len) {
    const uint32_t need = s->win_len - s->ring_fill;
    const size_t take = (input_len - idx < (size_t)need) ? (input_len - idx) : (size_t)need;

    memcpy(s->ring + s->ring_fill, input + idx, take * sizeof(float));
    s->ring_fill += (uint32_t)take;
    idx += take;

    if (s->ring_fill < s->win_len) break;
    if (frames >= out_frames_cap) break;

    // Prepare + FFT
    yl_stft_prepare_frame(s, s->ring);
    yl_fft_execute_r2c(s->fft, s->time,
                      out_re + frames * s->bins,
                      out_im + frames * s->bins);
    frames++;

    // Advance by hop
    yl_stft_advance_ring_full(s);
  }

  return frames;
}

size_t yl_stft_push_spec(
  yl_stft_ctx* s,
  const float* input,
  size_t input_len,
  float* out_bins,
  size_t out_frames_cap,
  yl_spec_mode mode,
  float db_floor
) {
  if (!s || (!input && input_len)) return 0;
  if (out_frames_cap && !out_bins) return 0;

  size_t frames = 0;
  size_t idx = 0;

  while (idx < input_len) {
    const uint32_t need = s->win_len - s->ring_fill;
    const size_t take = (input_len - idx < (size_t)need) ? (input_len - idx) : (size_t)need;

    memcpy(s->ring + s->ring_fill, input + idx, take * sizeof(float));
    s->ring_fill += (uint32_t)take;
    idx += take;

    if (s->ring_fill < s->win_len) break;
    if (frames >= out_frames_cap) break;

    yl_stft_prepare_frame(s, s->ring);
    yl_fft_execute_r2c_spec(
      s->fft,
      s->time,
      out_bins + frames * s->bins,
      mode,
      db_floor
    );
    frames++;

    yl_stft_advance_ring_full(s);
  }

  return frames;
}

size_t yl_stft_flush_r2c(
  yl_stft_ctx* s,
  float* out_re,
  float* out_im,
  size_t out_frames_cap
) {
  if (!s) return 0;
  if (out_frames_cap && (!out_re || !out_im)) return 0;

  size_t frames = 0;

  while (s->ring_fill > 0 && frames < out_frames_cap) {
    const uint32_t valid = s->ring_fill;

    // Pad remaining samples with zeros to complete a frame
    if (valid < s->win_len) {
      memset(s->ring + valid, 0,
             (size_t)(s->win_len - valid) * sizeof(float));
      s->ring_fill = s->win_len;
    }

    yl_stft_prepare_frame(s, s->ring);
    yl_fft_execute_r2c(s->fft, s->time,
                      out_re + frames * s->bins,
                      out_im + frames * s->bins);
    frames++;

    // Advance by hop
    if (s->hop >= valid) {
      s->ring_fill = 0;
    } else {
      const uint32_t keep = valid - s->hop;
      memmove(s->ring, s->ring + s->hop, (size_t)keep * sizeof(float));
      s->ring_fill = keep;
    }
  }

  return frames;
}

size_t yl_stft_flush_spec(
  yl_stft_ctx* s,
  float* out_bins,
  size_t out_frames_cap,
  yl_spec_mode mode,
  float db_floor
) {
  if (!s) return 0;
  if (out_frames_cap && !out_bins) return 0;

  size_t frames = 0;

  while (s->ring_fill > 0 && frames < out_frames_cap) {
    const uint32_t valid = s->ring_fill;

    if (valid < s->win_len) {
      memset(s->ring + valid, 0,
             (size_t)(s->win_len - valid) * sizeof(float));
      s->ring_fill = s->win_len;
    }

    yl_stft_prepare_frame(s, s->ring);
    yl_fft_execute_r2c_spec(
      s->fft,
      s->time,
      out_bins + frames * s->bins,
      mode,
      db_floor
    );
    frames++;

    if (s->hop >= valid) {
      s->ring_fill = 0;
    } else {
      const uint32_t keep = valid - s->hop;
      memmove(s->ring, s->ring + s->hop, (size_t)keep * sizeof(float));
      s->ring_fill = keep;
    }
  }

  return frames;
}

size_t yl_stft_process_r2c(
  yl_stft_ctx* s,
  const float* signal,
  size_t signal_len,
  float* out_re,
  float* out_im,
  size_t out_frames_cap
) {
  if (!s || (!signal && signal_len)) return 0;

  yl_stft_reset(s);

  size_t frames = 0;
  frames += yl_stft_push_r2c(s, signal, signal_len,
                             out_re, out_im,
                             out_frames_cap);

  if (frames < out_frames_cap) {
    frames += yl_stft_flush_r2c(s,
                                out_re + frames * s->bins,
                                out_im + frames * s->bins,
                                out_frames_cap - frames);
  }
  return frames;
}

size_t yl_stft_process_spec(
  yl_stft_ctx* s,
  const float* signal,
  size_t signal_len,
  float* out_bins,
  size_t out_frames_cap,
  yl_spec_mode mode,
  float db_floor
) {
  if (!s || (!signal && signal_len)) return 0;

  yl_stft_reset(s);

  size_t frames = 0;
  frames += yl_stft_push_spec(
    s,
    signal,
    signal_len,
    out_bins,
    out_frames_cap,
    mode,
    db_floor
  );

  if (frames < out_frames_cap) {
    frames += yl_stft_flush_spec(
      s,
      out_bins + frames * s->bins,
      out_frames_cap - frames,
      mode,
      db_floor
    );
  }
  return frames;
}
