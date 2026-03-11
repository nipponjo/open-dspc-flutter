/* include/dsp/mel.h
   Portable C mel filterbank: HTK or Slaney mel scale + optional Slaney-style normalization.
*/
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  YL_MEL_SCALE_HTK    = 1,
  YL_MEL_SCALE_SLANEY = 2,
} yl_mel_scale;

typedef enum {
  YL_MEL_NORM_NONE   = 0,
  YL_MEL_NORM_SLANEY = 1,  /* area-ish normalization commonly used with Slaney-style FB */
} yl_mel_norm;

typedef struct yl_mel_ctx yl_mel_ctx;

/* Create a mel filterbank that maps power spectrum bins (n_fft/2+1) -> n_mels.
   - sr: sample rate (Hz)
   - n_fft: FFT size
   - n_mels: number of mel bands
   - fmin/fmax: band limits in Hz (fmax will be clamped to sr/2)
   - scale: HTK vs Slaney mel mapping
   - norm: optional normalization (common: Slaney)
*/
yl_mel_ctx* yl_mel_create(
  int sr, int n_fft, int n_mels,
  float fmin, float fmax,
  yl_mel_scale scale, 
  yl_mel_norm norm);

void yl_mel_destroy(yl_mel_ctx* m);

/* Apply filterbank to one frame of power bins (size n_bins = n_fft/2+1). */
void yl_mel_apply(
  const yl_mel_ctx* m, 
  const float* power_bins, 
  float* mel_out);

/* Useful accessors */
int yl_mel_n_fft(const yl_mel_ctx* m);
int yl_mel_n_bins(const yl_mel_ctx* m);
int yl_mel_n_mels(const yl_mel_ctx* m);

/* --- Mel conversion functions (Hz <-> mel) --- */
float yl_mel_htk_hz_to_mel(float hz);
float yl_mel_htk_mel_to_hz(float mel);

float yl_mel_slaney_hz_to_mel(float hz);
float yl_mel_slaney_mel_to_hz(float mel);

#ifdef __cplusplus
}
#endif