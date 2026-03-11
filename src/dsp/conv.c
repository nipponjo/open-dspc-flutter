#include "dsp/conv.h"

#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "dsp/fft.h"
#include "third_party/pffft/simd/pf_float.h"

struct yl_fftconv_ctx {
  size_t nx_max;
  size_t nh_max;
  size_t ny_max;
  size_t nfft;
  size_t bins;
  yl_fft_plan* rfft;
  yl_fft_plan* irfft;
  float* time;
  float* Xr;
  float* Xi;
  float* Hr;
  float* Hi;
  float* Yr;
  float* Yi;
};

static size_t yl_min_size(size_t a, size_t b) {
  return (a < b) ? a : b;
}

static int yl_autocorr_bounds(
    size_t n,
    yl_corr_out_mode mode,
    size_t* start_full_idx,
    size_t* out_len
) {
  const size_t full_len = (n == 0) ? 0 : (2 * n - 1);
  if (!start_full_idx || !out_len) return 0;

  if (n == 0) {
    *start_full_idx = 0;
    *out_len = 0;
    return 1;
  }

  switch (mode) {
    case YL_CORR_MODE_FULL:
      *start_full_idx = 0;
      *out_len = full_len;
      return 1;
    case YL_CORR_MODE_VALID:
      *start_full_idx = n - 1;
      *out_len = 1;
      return 1;
    case YL_CORR_MODE_SAME:
      *start_full_idx = (full_len - n) / 2;
      *out_len = n;
      return 1;
    default:
      return 0;
  }
}

size_t yl_autocorr_out_len(size_t n, yl_corr_out_mode mode) {
  size_t start = 0;
  size_t out_len = 0;
  if (!yl_autocorr_bounds(n, mode, &start, &out_len)) return 0;
  (void)start;
  return out_len;
}

static float yl_dot_scalar(const float* a, const float* b, size_t n) {
  float acc = 0.0f;
  for (size_t i = 0; i < n; ++i) acc += a[i] * b[i];
  return acc;
}

static float yl_dot_simd(const float* a, const float* b, size_t n) {
#if defined(SIMD_SZ) && (SIMD_SZ == 4)
  size_t i = 0;
  v4sf vacc = VZERO();
  v4sf_union u;
  float acc;

  for (; i + 3 < n; i += 4) {
    const v4sf va = VLOAD_UNALIGNED(a + i);
    const v4sf vb = VLOAD_UNALIGNED(b + i);
    vacc = VMADD(va, vb, vacc);
  }

  u.v = vacc;
  acc = u.f[0] + u.f[1] + u.f[2] + u.f[3];
  for (; i < n; ++i) acc += a[i] * b[i];
  return acc;
#else
  return yl_dot_scalar(a, b, n);
#endif
}

static int yl_autocorr_direct_impl(
    const float* x,
    size_t n,
    float* y,
    yl_corr_out_mode mode,
    int use_simd
) {
  size_t start = 0;
  size_t out_len = 0;
  const size_t full_center = (n > 0) ? (n - 1) : 0;

  if (!yl_autocorr_bounds(n, mode, &start, &out_len)) return 2;
  if ((!x && n) || (!y && out_len)) return 1;
  if (n == 0) return 0;

  for (size_t t = 0; t < out_len; ++t) {
    const size_t k = start + t; /* full-output index */
    const ptrdiff_t lag = (ptrdiff_t)k - (ptrdiff_t)full_center;
    size_t ix = 0;
    size_t jx = 0;
    size_t seg_len = 0;

    if (lag >= 0) {
      ix = (size_t)lag;
      jx = 0;
      seg_len = n - (size_t)lag;
    } else {
      ix = 0;
      jx = (size_t)(-lag);
      seg_len = n - (size_t)(-lag);
    }

    y[t] = use_simd
        ? yl_dot_simd(x + ix, x + jx, seg_len)
        : yl_dot_scalar(x + ix, x + jx, seg_len);
  }
  return 0;
}

int yl_autocorr_direct(
    const float* x,
    size_t n,
    float* y,
    yl_corr_out_mode mode
) {
  return yl_autocorr_direct_impl(x, n, y, mode, 0);
}

int yl_autocorr_direct_simd(
    const float* x,
    size_t n,
    float* y,
    yl_corr_out_mode mode
) {
  return yl_autocorr_direct_impl(x, n, y, mode, 1);
}

size_t yl_conv_out_len(size_t nx, size_t nh) {
  if (nx == 0 || nh == 0) return 0;
  return nx + nh - 1;
}

static int yl_conv_bounds(
    size_t nx,
    size_t nh,
    yl_corr_out_mode out_mode,
    size_t* start_full_idx,
    size_t* out_len
) {
  const size_t full_len = yl_conv_out_len(nx, nh);
  if (!start_full_idx || !out_len) return 0;
  if (full_len == 0) {
    *start_full_idx = 0;
    *out_len = 0;
    return 1;
  }

  switch (out_mode) {
    case YL_CORR_MODE_FULL:
      *start_full_idx = 0;
      *out_len = full_len;
      return 1;
    case YL_CORR_MODE_VALID: {
      const size_t nmin = (nx < nh) ? nx : nh;
      const size_t nmax = (nx > nh) ? nx : nh;
      *start_full_idx = nmin - 1;
      *out_len = nmax - nmin + 1;
      return 1;
    }
    case YL_CORR_MODE_SAME:
      *start_full_idx = (full_len - nx) / 2;
      *out_len = nx;
      return 1;
    default:
      return 0;
  }
}

size_t yl_conv_out_len_mode(size_t nx, size_t nh, yl_corr_out_mode out_mode) {
  size_t start = 0;
  size_t out_len = 0;
  if (!yl_conv_bounds(nx, nh, out_mode, &start, &out_len)) return 0;
  (void)start;
  return out_len;
}

static int yl_conv_direct_mode_impl_f32(
    const float* x,
    size_t nx,
    const float* h,
    size_t nh,
    float* y,
    yl_conv_mode mode,
    yl_corr_out_mode out_mode,
    int use_simd
) {
  size_t k_start = 0;
  size_t ny = 0;
  float* h_rev = NULL;
  const float* h_work = h;

  if (!yl_conv_bounds(nx, nh, out_mode, &k_start, &ny)) return 2;
  if ((!x && nx) || (!h && nh) || (!y && ny)) return 1;
  if (nx == 0 || nh == 0) return 0;

  if (use_simd && mode == YL_CONV_MODE_CONV) {
    h_rev = (float*)malloc(nh * sizeof(float));
    if (!h_rev) return 3;
    for (size_t i = 0; i < nh; ++i) h_rev[i] = h[nh - 1 - i];
    h_work = h_rev;
  }

  for (size_t t = 0; t < ny; ++t) {
    const size_t k = k_start + t;
    const size_t i_start = (k >= (nh - 1)) ? (k - (nh - 1)) : 0;
    const size_t i_end = yl_min_size(k + 1, nx);
    const size_t seg_len = i_end - i_start;

    if (!use_simd) {
      float acc = 0.0f;
      for (size_t i = i_start; i < i_end; ++i) {
        const size_t j = k - i;
        const size_t h_idx = (mode == YL_CONV_MODE_XCORR) ? (nh - 1 - j) : j;
        acc += x[i] * h[h_idx];
      }
      y[t] = acc;
    } else {
      const size_t h_base = nh - 1 - (k - i_start);
      y[t] = yl_dot_simd(x + i_start, h_work + h_base, seg_len);
    }
  }

  free(h_rev);
  return 0;
}

int yl_conv_direct_f32(
    const float* x,
    size_t nx,
    const float* h,
    size_t nh,
    float* y,
    yl_conv_mode mode
) {
  return yl_conv_direct_mode_impl_f32(
      x, nx, h, nh, y, mode, YL_CORR_MODE_FULL, 0);
}

int yl_conv_direct_mode_f32(
    const float* x,
    size_t nx,
    const float* h,
    size_t nh,
    float* y,
    yl_conv_mode mode,
    yl_corr_out_mode out_mode
) {
  return yl_conv_direct_mode_impl_f32(x, nx, h, nh, y, mode, out_mode, 0);
}

int yl_conv_direct_mode_simd_f32(
    const float* x,
    size_t nx,
    const float* h,
    size_t nh,
    float* y,
    yl_conv_mode mode,
    yl_corr_out_mode out_mode
) {
  return yl_conv_direct_mode_impl_f32(x, nx, h, nh, y, mode, out_mode, 1);
}

yl_fftconv_ctx* yl_fftconv_create_f32(size_t nx_max, size_t nh_max) {
  if (nx_max == 0 || nh_max == 0) return NULL;

  yl_fftconv_ctx* ctx = (yl_fftconv_ctx*)calloc(1, sizeof(*ctx));
  if (!ctx) return NULL;

  ctx->nx_max = nx_max;
  ctx->nh_max = nh_max;
  ctx->ny_max = yl_conv_out_len(nx_max, nh_max);
  ctx->nfft = yl_fft_backend_next_valid_size(ctx->ny_max, 0);
  if (ctx->nfft == 0) {
    free(ctx);
    return NULL;
  }
  ctx->bins = ctx->nfft / 2 + 1;

  ctx->rfft = yl_fft_create_r2c(ctx->nfft);
  ctx->irfft = yl_fft_create_c2r(ctx->nfft);
  if (!ctx->rfft || !ctx->irfft) {
    yl_fft_destroy(ctx->rfft);
    yl_fft_destroy(ctx->irfft);
    free(ctx);
    return NULL;
  }

  ctx->time = (float*)calloc(ctx->nfft, sizeof(float));
  ctx->Xr = (float*)calloc(ctx->bins, sizeof(float));
  ctx->Xi = (float*)calloc(ctx->bins, sizeof(float));
  ctx->Hr = (float*)calloc(ctx->bins, sizeof(float));
  ctx->Hi = (float*)calloc(ctx->bins, sizeof(float));
  ctx->Yr = (float*)calloc(ctx->bins, sizeof(float));
  ctx->Yi = (float*)calloc(ctx->bins, sizeof(float));

  if (!ctx->time || !ctx->Xr || !ctx->Xi || !ctx->Hr || !ctx->Hi ||
      !ctx->Yr || !ctx->Yi) {
    yl_fftconv_destroy(ctx);
    return NULL;
  }

  return ctx;
}

void yl_fftconv_destroy(yl_fftconv_ctx* ctx) {
  if (!ctx) return;
  free(ctx->time);
  free(ctx->Xr);
  free(ctx->Xi);
  free(ctx->Hr);
  free(ctx->Hi);
  free(ctx->Yr);
  free(ctx->Yi);
  yl_fft_destroy(ctx->rfft);
  yl_fft_destroy(ctx->irfft);
  free(ctx);
}

size_t yl_fftconv_nfft(const yl_fftconv_ctx* ctx) {
  return ctx ? ctx->nfft : 0;
}

size_t yl_fftconv_bins(const yl_fftconv_ctx* ctx) {
  return ctx ? ctx->bins : 0;
}

size_t yl_fftconv_x_max(const yl_fftconv_ctx* ctx) {
  return ctx ? ctx->nx_max : 0;
}

size_t yl_fftconv_h_max(const yl_fftconv_ctx* ctx) {
  return ctx ? ctx->nh_max : 0;
}

int yl_fftconv_process_f32(
    yl_fftconv_ctx* ctx,
    const float* x,
    size_t nx,
    const float* h,
    size_t nh,
    float* y,
    yl_conv_mode mode
) {
  const size_t ny = yl_conv_out_len(nx, nh);
  if (!ctx) return 1;
  if ((!x && nx) || (!h && nh) || (!y && ny)) return 2;
  if (nx == 0 || nh == 0) return 0;
  if (nx > ctx->nx_max || nh > ctx->nh_max) return 3;
  if (ny > ctx->ny_max) return 4;

  memset(ctx->time, 0, ctx->nfft * sizeof(float));
  memcpy(ctx->time, x, nx * sizeof(float));
  yl_fft_execute_r2c(ctx->rfft, ctx->time, ctx->Xr, ctx->Xi);

  memset(ctx->time, 0, ctx->nfft * sizeof(float));
  memcpy(ctx->time, h, nh * sizeof(float));
  yl_fft_execute_r2c(ctx->rfft, ctx->time, ctx->Hr, ctx->Hi);

  for (size_t k = 0; k < ctx->bins; ++k) {
    const float ar = ctx->Xr[k];
    const float ai = ctx->Xi[k];
    const float br = ctx->Hr[k];
    const float bi = ctx->Hi[k];

    if (mode == YL_CONV_MODE_XCORR) {
      ctx->Yr[k] = ar * br + ai * bi;
      ctx->Yi[k] = ai * br - ar * bi;
    } else {
      ctx->Yr[k] = ar * br - ai * bi;
      ctx->Yi[k] = ar * bi + ai * br;
    }
  }

  yl_fft_execute_c2r(ctx->irfft, ctx->Yr, ctx->Yi, ctx->time);
  if (mode == YL_CONV_MODE_XCORR) {
    const size_t neg_lags = nh - 1;
    memcpy(y, ctx->time + (ctx->nfft - neg_lags), neg_lags * sizeof(float));
    memcpy(y + neg_lags, ctx->time, nx * sizeof(float));
  } else {
    memcpy(y, ctx->time, ny * sizeof(float));
  }
  return 0;
}
