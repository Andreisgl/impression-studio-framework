// Copyright 2026 Andrei Segal
// SPDX-License-Identifier: Apache-2.0

// Impression logging layer: categories, verbosity levels, printf-style messages,
// and live output to the EE serial port (PCSX2's EE console) and to bin/log.txt.
//
//   // header:  IMP_DECLARE_LOG_CATEGORY(Player);
//   // one .cpp: IMP_DEFINE_LOG_CATEGORY(Player, Info);   // default runtime level
//   IMP_LOG(Player, Warning, "health low: %d", hp);
//
// Output line format (stable, meant for tools): "[Category][Level] message\n".
// Lines without a bracket prefix come from raw stdout, e.g. Tyra's own TYRA_LOG.
// See docs/tooling-contract.md. Not thread-safe: log from the main thread only.

#pragma once

#include <stddef.h>

namespace Impression {

enum class LogLevel { Verbose = 0, Debug = 1, Info = 2, Warning = 3, Error = 4 };

/** One named source of log messages with its own runtime level. */
struct LogCategory {
  LogCategory(const char* t_name, LogLevel t_level);

  const char* name;
  LogLevel level;
  LogCategory* next;  // registry link, set by the constructor
};

struct LogConfig {
  /** Write every line to the EE serial port (shown live in PCSX2's EE console). */
  bool serial = true;
  /** Buffer lines and append them to <elf folder>/log.txt on flush(). */
  bool file = true;
  /**
   * Redirect libc stdout/stderr (so TYRA_LOG and printf) into the same sinks.
   * Create the Tyra Engine with EngineOptions::writeLogsToFile = false when on.
   */
  bool hookStdout = true;
};

namespace Log {

/** Optional. Without it, the first message initializes the defaults. */
void init(const LogConfig& config = LogConfig());

/** Sets the runtime level of a category by name. Returns false if unknown. */
bool setLevel(const char* category, LogLevel level);

/**
 * Applies "Category=Level,Other=Level" (level names are case-insensitive).
 * Returns how many entries were applied; unknown categories and levels are skipped.
 */
int applySpec(const char* spec);

/** Writes buffered lines to log.txt. Does nothing when nothing is buffered. */
void flush();

const char* levelName(LogLevel level);

inline bool enabled(const LogCategory& category, LogLevel level) {
  return static_cast<int>(level) >= static_cast<int>(category.level);
}

/** Use IMP_LOG instead. The format attribute makes -Wall check the arguments. */
void write(const LogCategory& category, LogLevel level, const char* format, ...)
    __attribute__((format(printf, 3, 4)));

}  // namespace Log
}  // namespace Impression

/**
 * Levels below this are compiled out entirely (their arguments are not
 * evaluated). Override with -DIMP_LOG_MIN_LEVEL=<0..4>; defaults to Warning in
 * NDEBUG builds and to everything otherwise.
 */
#ifndef IMP_LOG_MIN_LEVEL
#ifdef NDEBUG
#define IMP_LOG_MIN_LEVEL 3
#else
#define IMP_LOG_MIN_LEVEL 0
#endif
#endif

#define IMP_DECLARE_LOG_CATEGORY(name) \
  extern ::Impression::LogCategory ImpLogCategory_##name

#define IMP_DEFINE_LOG_CATEGORY(name, defaultLevel) \
  ::Impression::LogCategory ImpLogCategory_##name(  \
      #name, ::Impression::LogLevel::defaultLevel)

/** IMP_LOG(Category, Level, "format", args...) with Level one of Verbose..Error. */
#define IMP_LOG(name, level, ...)                                              \
  do {                                                                         \
    if (static_cast<int>(::Impression::LogLevel::level) >=                     \
            IMP_LOG_MIN_LEVEL &&                                               \
        ::Impression::Log::enabled(ImpLogCategory_##name,                      \
                                   ::Impression::LogLevel::level)) {           \
      ::Impression::Log::write(ImpLogCategory_##name,                          \
                               ::Impression::LogLevel::level, __VA_ARGS__);    \
    }                                                                          \
  } while (0)
