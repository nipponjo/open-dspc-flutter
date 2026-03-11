#include <cmath>
#include <complex>
#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <vector>

#define POCKETFFT_NO_MULTITHREADING
#include "third_party/pocketfft-cpp/pocketfft_hdronly.h"

#include "dsp/fft.h"

#ifndef YL_DB_EPS
#define YL_DB_EPS 1e-20f
#endif

extern "C" {

typedef struct yl_fft_backend {
  int n;
  int kind;       /* 1 = real, 2 = complex */
  int is_inverse; /* real plan flavor: 0 = r2c, 1 = c2r */

  std::vector<float> real_time;
  std::vector<std::complex<float>> real_spec;
  std::vector<std::complex<float>> complex_time;
  std::vector<std::complex<float>> complex_spec;
} yl_fft_backend;

enum {
  YL_POCKETFFT_KIND_REAL = 1,
  YL_POCKETFFT_KIND_COMPLEX = 2,
};

static inline float yl_pow2(float x) { return x * x; }

static yl_fft_backend* yl_fft_backend_alloc(int n, int kind, int inverse) {
  if (n <= 0) return nullptr;

  yl_fft_backend* b = nullptr;
  try {
    b = new yl_fft_backend{};
    b->n = n;
    b->kind = kind;
    b->is_inverse = inverse ? 1 : 0;

    if (kind == YL_POCKETFFT_KIND_REAL) {
      b->real_time.resize(static_cast<size_t>(n));
      b->real_spec.resize(static_cast<size_t>(n / 2 + 1));
    } else {
      b->complex_time.resize(static_cast<size_t>(n));
      b->complex_spec.resize(static_cast<size_t>(n));
    }
  } catch (...) {
    delete b;
    return nullptr;
  }

  return b;
}

/* Create a real-to-complex backend plan. */
yl_fft_backend* yl_fft_backend_create_r2c(size_t n) {
  if (n > static_cast<size_t>(std::numeric_limits<int>::max())) return nullptr;
  return yl_fft_backend_alloc(static_cast<int>(n), YL_POCKETFFT_KIND_REAL, 0);
}

/* Create a complex-to-real backend plan. */
yl_fft_backend* yl_fft_backend_create_c2r(size_t n) {
  if (n > static_cast<size_t>(std::numeric_limits<int>::max())) return nullptr;
  return yl_fft_backend_alloc(static_cast<int>(n), YL_POCKETFFT_KIND_REAL, 1);
}

/* Create a complex-to-complex backend plan. */
yl_fft_backend* yl_fft_backend_create_c2c(size_t n) {
  if (n > static_cast<size_t>(std::numeric_limits<int>::max())) return nullptr;
  return yl_fft_backend_alloc(static_cast<int>(n), YL_POCKETFFT_KIND_COMPLEX, 0);
}

/* Return a pocketfft-friendly next size (supports all sizes, returns >= n). */
size_t yl_fft_backend_next_valid_size(size_t n, int complex_transform) {
  if (n == 0) return 0;
  if (n > static_cast<size_t>(std::numeric_limits<size_t>::max() / 2)) return n;
  return complex_transform ? pocketfft::detail::util::good_size_cmplx(n)
                           : pocketfft::detail::util::good_size_real(n);
}

/* Execute a forward real FFT into split real/imag arrays. */
void yl_fft_backend_execute_r2c(
    yl_fft_backend* b,
    const float* input,
    float* out_real,
    float* out_imag
) {
  if (!b || b->kind != YL_POCKETFFT_KIND_REAL || b->is_inverse) return;
  if (!input || !out_real || !out_imag) return;

  const size_t n = static_cast<size_t>(b->n);
  const size_t bins = static_cast<size_t>(b->n / 2 + 1);
  const pocketfft::shape_t shape{n};
  const pocketfft::stride_t stride_in{static_cast<ptrdiff_t>(sizeof(float))};
  const pocketfft::stride_t stride_out{static_cast<ptrdiff_t>(sizeof(std::complex<float>))};

  std::memcpy(b->real_time.data(), input, n * sizeof(float));

  try {
    pocketfft::r2c(shape, stride_in, stride_out, static_cast<size_t>(0), pocketfft::FORWARD,
                   b->real_time.data(), b->real_spec.data(), 1.0f, static_cast<size_t>(1));
  } catch (...) {
    return;
  }

  for (size_t k = 0; k < bins; ++k) {
    out_real[k] = b->real_spec[k].real();
    out_imag[k] = b->real_spec[k].imag();
  }
}

/* Return the number of non-redundant bins in a real FFT output. */
size_t yl_fft_backend_bins(const yl_fft_backend* b) {
  return b ? static_cast<size_t>(b->n / 2 + 1) : 0;
}

/* Compute magnitude, power, or dB bins from a real-input forward transform. */
void yl_fft_backend_execute_r2c_spec(
    yl_fft_backend* b,
    const float* input,
    float* out_bins,
    yl_spec_mode mode,
    float db_floor
) {
  if (!b || b->kind != YL_POCKETFFT_KIND_REAL || b->is_inverse) return;
  if (!input || !out_bins) return;

  const size_t n = static_cast<size_t>(b->n);
  const size_t bins = static_cast<size_t>(b->n / 2 + 1);
  const pocketfft::shape_t shape{n};
  const pocketfft::stride_t stride_in{static_cast<ptrdiff_t>(sizeof(float))};
  const pocketfft::stride_t stride_out{static_cast<ptrdiff_t>(sizeof(std::complex<float>))};

  std::memcpy(b->real_time.data(), input, n * sizeof(float));

  try {
    pocketfft::r2c(shape, stride_in, stride_out, static_cast<size_t>(0), pocketfft::FORWARD,
                   b->real_time.data(), b->real_spec.data(), 1.0f, static_cast<size_t>(1));
  } catch (...) {
    return;
  }

  if (mode == YL_SPEC_POWER) {
    for (size_t k = 0; k < bins; ++k) {
      const float re = b->real_spec[k].real();
      const float im = b->real_spec[k].imag();
      out_bins[k] = yl_pow2(re) + yl_pow2(im);
    }
    return;
  }

  if (mode == YL_SPEC_DB) {
    for (size_t k = 0; k < bins; ++k) {
      const float re = b->real_spec[k].real();
      const float im = b->real_spec[k].imag();
      float db = 10.0f * std::log10(yl_pow2(re) + yl_pow2(im) + YL_DB_EPS);
      if (db < db_floor) db = db_floor;
      out_bins[k] = db;
    }
    return;
  }

  for (size_t k = 0; k < bins; ++k) {
    const float re = b->real_spec[k].real();
    const float im = b->real_spec[k].imag();
    out_bins[k] = std::sqrt(yl_pow2(re) + yl_pow2(im));
  }
}

/* Estimate autocorrelation using FFT -> power spectrum -> inverse FFT. */
void yl_fft_backend_execute_autocorr(
    yl_fft_backend* b,
    const float* input,
    size_t input_len,
    float* out_acf,
    size_t out_len,
    yl_acf_mode mode
) {
  if (!b || b->kind != YL_POCKETFFT_KIND_REAL) return;
  if (!input || !out_acf) return;

  const size_t n = static_cast<size_t>(b->n);
  const size_t bins = static_cast<size_t>(b->n / 2 + 1);
  if (input_len > n) return;
  if (out_len > n) out_len = n;

  const pocketfft::shape_t shape_r{n};
  const pocketfft::stride_t stride_r{static_cast<ptrdiff_t>(sizeof(float))};
  const pocketfft::shape_t shape_c{bins};
  const pocketfft::stride_t stride_c{static_cast<ptrdiff_t>(sizeof(std::complex<float>))};

  std::memcpy(b->real_time.data(), input, input_len * sizeof(float));
  if (input_len < n) {
    std::memset(b->real_time.data() + input_len, 0, (n - input_len) * sizeof(float));
  }

  try {
    pocketfft::r2c(shape_r, stride_r, stride_c, static_cast<size_t>(0), pocketfft::FORWARD,
                   b->real_time.data(), b->real_spec.data(), 1.0f, static_cast<size_t>(1));
  } catch (...) {
    return;
  }

  for (size_t k = 0; k < bins; ++k) {
    const float re = b->real_spec[k].real();
    const float im = b->real_spec[k].imag();
    b->real_spec[k] = std::complex<float>(yl_pow2(re) + yl_pow2(im), 0.0f);
  }

  try {
    pocketfft::c2r(shape_r, stride_c, stride_r, static_cast<size_t>(0), pocketfft::BACKWARD,
                   b->real_spec.data(), b->real_time.data(), 1.0f / static_cast<float>(n),
                   static_cast<size_t>(1));
  } catch (...) {
    return;
  }

  if (mode == YL_ACF_NORM_R0) {
    const float r0 = b->real_time[0];
    const float inv_r0 = (std::fabs(r0) > 1e-20f) ? (1.0f / r0) : 0.0f;
    for (size_t i = 0; i < out_len; ++i) {
      out_acf[i] = b->real_time[i] * inv_r0;
    }
    return;
  }

  std::memcpy(out_acf, b->real_time.data(), out_len * sizeof(float));
}

/* Execute an inverse real FFT from split real/imag spectrum input. */
void yl_fft_backend_execute_c2r(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* output
) {
  if (!b || b->kind != YL_POCKETFFT_KIND_REAL || !b->is_inverse) return;
  if (!in_real || !in_imag || !output) return;

  const size_t n = static_cast<size_t>(b->n);
  const size_t bins = static_cast<size_t>(b->n / 2 + 1);
  const pocketfft::shape_t shape_r{n};
  const pocketfft::stride_t stride_r{static_cast<ptrdiff_t>(sizeof(float))};
  const pocketfft::stride_t stride_c{static_cast<ptrdiff_t>(sizeof(std::complex<float>))};

  for (size_t k = 0; k < bins; ++k) {
    b->real_spec[k] = std::complex<float>(in_real[k], in_imag[k]);
  }

  try {
    pocketfft::c2r(shape_r, stride_c, stride_r, static_cast<size_t>(0), pocketfft::BACKWARD,
                   b->real_spec.data(), b->real_time.data(), 1.0f / static_cast<float>(n),
                   static_cast<size_t>(1));
  } catch (...) {
    return;
  }

  std::memcpy(output, b->real_time.data(), n * sizeof(float));
}

/* Execute a forward complex FFT into split real/imag arrays. */
void yl_fft_backend_execute_c2c_forward(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
  if (!b || b->kind != YL_POCKETFFT_KIND_COMPLEX) return;
  if (!in_real || !in_imag || !out_real || !out_imag) return;

  const size_t n = static_cast<size_t>(b->n);
  const pocketfft::shape_t shape{n};
  const pocketfft::stride_t stride{static_cast<ptrdiff_t>(sizeof(std::complex<float>))};
  const pocketfft::shape_t axes{static_cast<size_t>(0)};

  for (size_t k = 0; k < n; ++k) {
    b->complex_time[k] = std::complex<float>(in_real[k], in_imag[k]);
  }

  try {
    pocketfft::c2c(shape, stride, stride, axes, pocketfft::FORWARD, b->complex_time.data(),
                   b->complex_spec.data(), 1.0f, static_cast<size_t>(1));
  } catch (...) {
    return;
  }

  for (size_t k = 0; k < n; ++k) {
    out_real[k] = b->complex_spec[k].real();
    out_imag[k] = b->complex_spec[k].imag();
  }
}

/* Execute an inverse complex FFT into split real/imag arrays, normalized by N. */
void yl_fft_backend_execute_c2c_backward(
    yl_fft_backend* b,
    const float* in_real,
    const float* in_imag,
    float* out_real,
    float* out_imag
) {
  if (!b || b->kind != YL_POCKETFFT_KIND_COMPLEX) return;
  if (!in_real || !in_imag || !out_real || !out_imag) return;

  const size_t n = static_cast<size_t>(b->n);
  const pocketfft::shape_t shape{n};
  const pocketfft::stride_t stride{static_cast<ptrdiff_t>(sizeof(std::complex<float>))};
  const pocketfft::shape_t axes{static_cast<size_t>(0)};

  for (size_t k = 0; k < n; ++k) {
    b->complex_time[k] = std::complex<float>(in_real[k], in_imag[k]);
  }

  try {
    pocketfft::c2c(shape, stride, stride, axes, pocketfft::BACKWARD, b->complex_time.data(),
                   b->complex_spec.data(), 1.0f / static_cast<float>(n), static_cast<size_t>(1));
  } catch (...) {
    return;
  }

  for (size_t k = 0; k < n; ++k) {
    out_real[k] = b->complex_spec[k].real();
    out_imag[k] = b->complex_spec[k].imag();
  }
}

/* Destroy backend and release owned buffers. */
void yl_fft_backend_destroy(yl_fft_backend* b) {
  delete b;
}

} /* extern "C" */
