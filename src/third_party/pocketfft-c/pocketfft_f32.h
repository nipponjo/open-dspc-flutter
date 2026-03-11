/*
 * This file is part of pocketfft.
 * Licensed under a 3-clause BSD style license - see LICENSE.md
 */

/*! \file pocketfft_f32.h
 *  Public single-precision interface of the pocketfft library
 */

#ifndef POCKETFFT_F32_H
#define POCKETFFT_F32_H

#include <stdlib.h>

struct cfft_plan_f32_i;
typedef struct cfft_plan_f32_i * cfft_plan_f32;
cfft_plan_f32 make_cfft_plan_f32 (size_t length);
void destroy_cfft_plan_f32 (cfft_plan_f32 plan);
int cfft_backward_f32(cfft_plan_f32 plan, float c[], float fct);
int cfft_forward_f32(cfft_plan_f32 plan, float c[], float fct);
size_t cfft_length_f32(cfft_plan_f32 plan);

struct rfft_plan_f32_i;
typedef struct rfft_plan_f32_i * rfft_plan_f32;
rfft_plan_f32 make_rfft_plan_f32 (size_t length);
void destroy_rfft_plan_f32 (rfft_plan_f32 plan);
int rfft_backward_f32(rfft_plan_f32 plan, float c[], float fct);
int rfft_forward_f32(rfft_plan_f32 plan, float c[], float fct);
size_t rfft_length_f32(rfft_plan_f32 plan);

#endif
