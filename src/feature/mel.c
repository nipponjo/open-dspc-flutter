/* src/feature/mel.c */
#include "feature/mel.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* -----------------------------
   Mel conversion: HTK
   ----------------------------- */
float yl_mel_htk_hz_to_mel(float hz) {
  /* mel = 2595 * log10(1 + f/700) */
  if (hz < 0.0f) hz = 0.0f;
  return 2595.0f * (log10f(1.0f + hz / 700.0f));
}

float yl_mel_htk_mel_to_hz(float mel) {
  /* f = 700 * (10^(mel/2595) - 1) */
  if (mel < 0.0f) mel = 0.0f;
  return 700.0f * (powf(10.0f, mel / 2595.0f) - 1.0f);
}

/* -----------------------------
   Mel conversion: Slaney (Auditory Toolbox / common librosa-style)
   Piecewise: linear below 1kHz, log above.
   ----------------------------- */
float yl_mel_slaney_hz_to_mel(float hz) {
  /* Reference parameters */
  const float f_sp       = 200.0f / 3.0f; /* ~66.6667 Hz per mel below 1k */
  const float min_log_hz = 1000.0f;
  const float min_log_mel = min_log_hz / f_sp; /* 15 */
  /* logstep chosen so that 6400 Hz is 27 mels above 1000 Hz (common convention) */
  const float logstep = logf(6.4f) / 27.0f;

  if (hz < 0.0f) hz = 0.0f;
  if (hz < min_log_hz) {
    return hz / f_sp;
  } else {
    return min_log_mel + logf(hz / min_log_hz) / logstep;
  }
}

float yl_mel_slaney_mel_to_hz(float mel) {
  const float f_sp       = 200.0f / 3.0f;
  const float min_log_hz = 1000.0f;
  const float min_log_mel = min_log_hz / f_sp; /* 15 */
  const float logstep = logf(6.4f) / 27.0f;

  if (mel < 0.0f) mel = 0.0f;
  if (mel < min_log_mel) {
    return mel * f_sp;
  } else {
    return min_log_hz * expf((mel - min_log_mel) * logstep);
  }
}

/* -----------------------------
   Internal helpers
   ----------------------------- */
static float clampf(float x, float lo, float hi) {
  if (x < lo) return lo;
  if (x > hi) return hi;
  return x;
}

static int clampi(int x, int lo, int hi) {
  if (x < lo) return lo;
  if (x > hi) return hi;
  return x;
}

static float hz_to_mel(float hz, yl_mel_scale scale) {
  return (scale == YL_MEL_SCALE_SLANEY) ? yl_mel_slaney_hz_to_mel(hz)
                                        : yl_mel_htk_hz_to_mel(hz);
}

static float mel_to_hz(float mel, yl_mel_scale scale) {
  return (scale == YL_MEL_SCALE_SLANEY) ? yl_mel_slaney_mel_to_hz(mel)
                                        : yl_mel_htk_mel_to_hz(mel);
}

static float maxf2(float a, float b) {
  return (a > b) ? a : b;
}

static float minf2(float a, float b) {
  return (a < b) ? a : b;
}

/* Center frequency in Hz for rfft bin k, matching librosa. */
static float fft_bin_hz(int k, int sr, int n_fft) {
  return ((float)sr * (float)k) / (float)n_fft;
}

struct yl_mel_ctx {
  int sr;
  int n_fft;
  int n_bins;
  int n_mels;
  float fmin;
  float fmax;
  yl_mel_scale scale;
  yl_mel_norm norm;

  /* Packed sparse storage: per mel band i:
     bins k in [start[i], start[i]+len[i]) have weights weights[offset[i] + (k-start[i])].
  */
  int* start;     /* n_mels */
  int* len;       /* n_mels */
  int* offset;    /* n_mels */
  float* weights; /* total_len */

  int total_len;

  /* Optional: store hz edges for normalization/debug */
  float* hz_points; /* n_mels+2 */
};

/* Public accessors */
int yl_mel_n_fft(const yl_mel_ctx* m)  { return m ? m->n_fft : 0; }
int yl_mel_n_bins(const yl_mel_ctx* m) { return m ? m->n_bins : 0; }
int yl_mel_n_mels(const yl_mel_ctx* m) { return m ? m->n_mels : 0; }

void yl_mel_apply(
  const yl_mel_ctx* m, 
  const float* power_bins, 
  float* mel_out
) {
  if (!m || !power_bins || !mel_out) return;

  for (int i = 0; i < m->n_mels; i++) {
    const int start = m->start[i];
    const int L = m->len[i];
    const float* w = &m->weights[m->offset[i]];
    const float* p = &power_bins[start];

    float acc = 0.0f;
    /* Tight contiguous dot-product */
    for (int j = 0; j < L; j++) {
      acc += p[j] * w[j];
    }
    mel_out[i] = acc;
  }
}

yl_mel_ctx* yl_mel_create(int sr, int n_fft, int n_mels,
                          float fmin, float fmax,
                          yl_mel_scale scale, yl_mel_norm norm)
{
  if (sr <= 0 || n_fft <= 0 || n_mels <= 0) return NULL;

  const int n_bins = n_fft / 2 + 1;
  const float nyquist = 0.5f * (float)sr;

  fmin = clampf(fmin, 0.0f, nyquist);
  fmax = clampf(fmax, fmin + 1e-6f, nyquist);

  yl_mel_ctx* m = (yl_mel_ctx*)calloc(1, sizeof(*m));
  if (!m) return NULL;

  m->sr = sr;
  m->n_fft = n_fft;
  m->n_bins = n_bins;
  m->n_mels = n_mels;
  m->fmin = fmin;
  m->fmax = fmax;
  m->scale = scale;
  m->norm = norm;

  /* Allocate per-band arrays */
  m->start  = (int*)malloc((size_t)n_mels * sizeof(int));
  m->len    = (int*)malloc((size_t)n_mels * sizeof(int));
  m->offset = (int*)malloc((size_t)n_mels * sizeof(int));
  m->hz_points = (float*)malloc((size_t)(n_mels + 2) * sizeof(float));

  if (!m->start || !m->len || !m->offset || !m->hz_points) {
    yl_mel_destroy(m);
    return NULL;
  }

  /* 1) Compute mel-spaced Hz points (n_mels + 2) */
  const float mel_min = hz_to_mel(fmin, scale);
  const float mel_max = hz_to_mel(fmax, scale);

  /* Linearly space mel points */
  for (int i = 0; i < n_mels + 2; i++) {
    float t = (n_mels + 1) > 0 ? ((float)i / (float)(n_mels + 1)) : 0.0f;
    float mel = mel_min + t * (mel_max - mel_min);
    m->hz_points[i] = mel_to_hz(mel, scale);
  }

  /* 2) FFT bin center frequencies in Hz */
  float* fftfreqs = (float*)malloc((size_t)n_bins * sizeof(float));
  if (!fftfreqs) {
    free(fftfreqs);
    yl_mel_destroy(m);
    return NULL;
  }
  for (int k = 0; k < n_bins; k++) {
    fftfreqs[k] = fft_bin_hz(k, sr, n_fft);
  }

  /* 3) Determine packed lengths and offsets from librosa-style weights */
  int total = 0;
  for (int i = 0; i < n_mels; i++) {
    const float f0 = m->hz_points[i];
    const float f1 = m->hz_points[i + 1];
    const float f2 = m->hz_points[i + 2];
    const float fdiff0 = f1 - f0;
    const float fdiff1 = f2 - f1;

    int start = -1;
    int end = -1;

    for (int k = 0; k < n_bins; k++) {
      const float lower = (fdiff0 > 0.0f) ? ((fftfreqs[k] - f0) / fdiff0) : 0.0f;
      const float upper = (fdiff1 > 0.0f) ? ((f2 - fftfreqs[k]) / fdiff1) : 0.0f;
      const float wk = maxf2(0.0f, minf2(lower, upper));

      if (wk > 0.0f) {
        if (start < 0) start = k;
        end = k;
      }
    }

    if (start < 0 || end < start) {
      m->start[i] = 0;
      m->len[i] = 0;
      m->offset[i] = total;
      continue;
    }

    const int L = (end - start + 1);
    m->start[i] = start;
    m->len[i] = L;
    m->offset[i] = total;
    total += L;
  }

  m->total_len = total;
  m->weights = (float*)malloc((size_t)total * sizeof(float));
  if (!m->weights) {
    free(fftfreqs);
    yl_mel_destroy(m);
    return NULL;
  }
  /* Initialize weights to 0 */
  memset(m->weights, 0, (size_t)total * sizeof(float));

  /* 4) Fill librosa-style triangular weights into packed storage */
  for (int i = 0; i < n_mels; i++) {
    const float f0 = m->hz_points[i];
    const float f1 = m->hz_points[i + 1];
    const float f2 = m->hz_points[i + 2];
    const float fdiff0 = f1 - f0;
    const float fdiff1 = f2 - f1;

    const int start = m->start[i];
    const int L = m->len[i];
    if (L <= 0) continue;

    float* w = &m->weights[m->offset[i]];
    for (int j = 0; j < L; j++) {
      const int k = start + j;
      const float lower = (fdiff0 > 0.0f) ? ((fftfreqs[k] - f0) / fdiff0) : 0.0f;
      const float upper = (fdiff1 > 0.0f) ? ((f2 - fftfreqs[k]) / fdiff1) : 0.0f;
      w[j] = maxf2(0.0f, minf2(lower, upper));
    }

    /* 5) Optional Slaney-style normalization.
       A common normalization is: scale each filter by 2 / (f_{i+2} - f_i)
       where f_i are the Hz points defining the triangle edges.
    */
    if (norm == YL_MEL_NORM_SLANEY) {
      const float f_left  = m->hz_points[i];
      const float f_right = m->hz_points[i + 2];
      const float width = f_right - f_left;
      if (width > 0.0f) {
        const float scale_norm = 2.0f / width;
        for (int j = 0; j < L; j++) {
          w[j] *= scale_norm;
        }
      }
    }
  }

  free(fftfreqs);
  return m;
}

void yl_mel_destroy(yl_mel_ctx* m) {
  if (!m) return;
  free(m->start);
  free(m->len);
  free(m->offset);
  free(m->weights);
  free(m->hz_points);
  free(m);
}
