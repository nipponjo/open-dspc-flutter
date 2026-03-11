#pragma once

#ifdef _WIN32
  #ifdef OPENDSPC_BUILD
    #define YL_EXPORT __declspec(dllexport)
  #else
    #define YL_EXPORT __declspec(dllimport)
  #endif
#else
  #define YL_EXPORT __attribute__((visibility("default")))
#endif