"""Python equivalent of lib/utils/signal_generator.dart.

All methods return ``numpy.ndarray`` with ``dtype=float32``.
Method names and parameter names intentionally follow the Dart API so tests can
reuse the same call patterns with minimal changes.
"""

from __future__ import annotations

import math
from typing import Optional

import numpy as np


class SignalGenerator:
    """Static-only signal generation utility mirroring the Dart implementation."""

    @staticmethod
    def sine(
        *,
        n: int,
        freqHz: float,
        sampleRate: float,
        amplitude: float = 1.0,
        phaseRad: float = 0.0,
    ) -> np.ndarray:
        i = np.arange(n, dtype=np.float64)
        w = 2.0 * math.pi * freqHz / sampleRate
        out = amplitude * np.sin(w * i + phaseRad)
        return out.astype(np.float32, copy=False)

    @staticmethod
    def cosine(
        *,
        n: int,
        freqHz: float,
        sampleRate: float,
        amplitude: float = 1.0,
        phaseRad: float = 0.0,
    ) -> np.ndarray:
        i = np.arange(n, dtype=np.float64)
        w = 2.0 * math.pi * freqHz / sampleRate
        out = amplitude * np.cos(w * i + phaseRad)
        return out.astype(np.float32, copy=False)

    @staticmethod
    def whiteNoise(n: int, *, amplitude: float = 1.0, seed: Optional[int] = None) -> np.ndarray:
        rng = np.random.default_rng(seed)
        out = amplitude * (2.0 * rng.random(n) - 1.0)
        return out.astype(np.float32, copy=False)

    @staticmethod
    def lcgNoise(n: int, *, amplitude: float = 1.0, seed: int = 123456789) -> np.ndarray:
        x = seed & 0x7FFFFFFF
        a = 1103515245
        c = 12345
        m = 0x7FFFFFFF

        out = np.empty(n, dtype=np.float32)
        for i in range(n):
            x = (a * x + c) & m
            out[i] = amplitude * (2.0 * (x / m) - 1.0)
        return out

    @staticmethod
    def pulseTrain(
        *,
        n: int,
        freqHz: float,
        sampleRate: float,
        amplitude: float = 1.0,
        dutyCycle: float = 0.5,
    ) -> np.ndarray:
        i = np.arange(n, dtype=np.float64)
        period = sampleRate / freqHz
        phase = np.mod(i, period) / period
        out = np.where(phase < dutyCycle, amplitude, 0.0)
        return out.astype(np.float32, copy=False)

    @staticmethod
    def sawtooth(
        *,
        n: int,
        freqHz: float,
        sampleRate: float,
        amplitude: float = 1.0,
    ) -> np.ndarray:
        i = np.arange(n, dtype=np.float64)
        period = sampleRate / freqHz
        phase = np.mod(i, period) / period
        out = amplitude * (2.0 * phase - 1.0)
        return out.astype(np.float32, copy=False)

    @staticmethod
    def linearSweep(
        *,
        n: int,
        fStart: float,
        fEnd: float,
        sampleRate: float,
        amplitude: float = 1.0,
    ) -> np.ndarray:
        i = np.arange(n, dtype=np.float64)
        t = i / sampleRate
        T = n / sampleRate
        k = (fEnd - fStart) / T
        phase = 2.0 * math.pi * (fStart * t + 0.5 * k * t * t)
        out = amplitude * np.sin(phase)
        return out.astype(np.float32, copy=False)

    @staticmethod
    def exponentialSweep(
        *,
        n: int,
        fStart: float,
        fEnd: float,
        sampleRate: float,
        amplitude: float = 1.0,
    ) -> np.ndarray:
        i = np.arange(n, dtype=np.float64)
        t = i / sampleRate
        T = n / sampleRate
        K = T * fStart / math.log(fEnd / fStart)
        L = math.log(fEnd / fStart)
        phase = 2.0 * math.pi * K * (np.exp(t * L / T) - 1.0)
        out = amplitude * np.sin(phase)
        return out.astype(np.float32, copy=False)

    @staticmethod
    def arange(startOrStop, stop=None, step=1) -> np.ndarray:
        if stop is None:
            start = 0
            end = startOrStop
        else:
            start = startOrStop
            end = stop
        out = np.arange(start, end, step, dtype=np.float64)
        return out.astype(np.float32, copy=False)

    @staticmethod
    def linspace(start: float, stop: float, *, num: int = 50, endpoint: bool = True) -> np.ndarray:
        if num < 2:
            return np.array([start], dtype=np.float32)
        out = np.linspace(start, stop, num=num, endpoint=endpoint, dtype=np.float64)
        return out.astype(np.float32, copy=False)
