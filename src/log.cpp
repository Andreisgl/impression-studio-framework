// Copyright 2026 Andrei Segal
// SPDX-License-Identifier: Apache-2.0

#include "impression/log.hpp"

#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include <string>

#include "file/file_utils.hpp"
#include "log_internal.hpp"

namespace Impression {

namespace {

const size_t kMessageSize = 512;
const size_t kLineSize = kMessageSize + 96;  // "[Category][Level] " + message + '\n'
const size_t kFileBufferSize = 4096;

LogCategory* categories = nullptr;  // registry, filled by LogCategory constructors
LogConfig config;
bool initialized = false;
bool flushing = false;

char fileBuffer[kFileBufferSize];
size_t fileLength = 0;

bool equalsIgnoreCase(const char* a, size_t aLength, const char* b) {
  if (strlen(b) != aLength) return false;
  for (size_t i = 0; i < aLength; i++) {
    if (tolower(static_cast<unsigned char>(a[i])) !=
        tolower(static_cast<unsigned char>(b[i]))) {
      return false;
    }
  }
  return true;
}

bool parseLevel(const char* text, size_t length, LogLevel* out) {
  static const LogLevel levels[] = {LogLevel::Verbose, LogLevel::Debug,
                                    LogLevel::Info, LogLevel::Warning,
                                    LogLevel::Error};
  for (size_t i = 0; i < sizeof(levels) / sizeof(levels[0]); i++) {
    if (equalsIgnoreCase(text, length, Log::levelName(levels[i]))) {
      *out = levels[i];
      return true;
    }
  }
  return false;
}

void ensureInitialized() {
  if (!initialized) Log::init();
}

void appendToFileBuffer(const char* data, size_t length) {
  if (length > kFileBufferSize) length = kFileBufferSize;  // oversized raw chunk: keep the head
  if (fileLength + length > kFileBufferSize) Log::flush();
  memcpy(fileBuffer + fileLength, data, length);
  fileLength += length;
  if (fileLength >= kFileBufferSize / 4 * 3) Log::flush();
}

}  // namespace

LogCategory::LogCategory(const char* t_name, LogLevel t_level)
    : name(t_name), level(t_level), next(categories) {
  categories = this;
}

namespace detail {

void routeRaw(const char* data, size_t length) {
  if (length == 0) return;
  if (config.serial) serialWrite(data, length);
  if (config.file) appendToFileBuffer(data, length);
}

}  // namespace detail

namespace Log {

void init(const LogConfig& t_config) {
  config = t_config;
  initialized = true;
  if (config.serial) detail::serialInit();
  if (config.hookStdout) detail::installStdoutHook();
}

const char* levelName(LogLevel level) {
  switch (level) {
    case LogLevel::Verbose:
      return "Verbose";
    case LogLevel::Debug:
      return "Debug";
    case LogLevel::Info:
      return "Info";
    case LogLevel::Warning:
      return "Warning";
    case LogLevel::Error:
      return "Error";
  }
  return "Unknown";
}

bool setLevel(const char* category, LogLevel level) {
  for (LogCategory* c = categories; c != nullptr; c = c->next) {
    if (strcmp(c->name, category) == 0) {
      c->level = level;
      return true;
    }
  }
  return false;
}

int applySpec(const char* spec) {
  int applied = 0;
  const char* p = spec;
  while (*p != '\0') {
    while (*p == ' ' || *p == ',') p++;
    const char* nameStart = p;
    while (*p != '\0' && *p != '=' && *p != ',') p++;
    if (*p != '=') continue;  // no "=": skip this entry
    size_t nameLength = static_cast<size_t>(p - nameStart);
    while (nameLength > 0 && nameStart[nameLength - 1] == ' ') nameLength--;
    p++;  // '='
    while (*p == ' ') p++;
    const char* levelStart = p;
    while (*p != '\0' && *p != ',') p++;
    size_t levelLength = static_cast<size_t>(p - levelStart);
    while (levelLength > 0 && levelStart[levelLength - 1] == ' ') levelLength--;

    LogLevel level;
    if (nameLength == 0 || nameLength >= 64 ||
        !parseLevel(levelStart, levelLength, &level)) {
      continue;
    }
    char name[64];
    memcpy(name, nameStart, nameLength);
    name[nameLength] = '\0';
    if (setLevel(name, level)) applied++;
  }
  return applied;
}

void flush() {
  if (fileLength == 0 || flushing) return;
  flushing = true;
  // Open, append, close per flush: the same pattern Tyra's own file log uses,
  // which PCSX2's host: filesystem shows live.
  std::string path = Tyra::FileUtils::fromCwd("log.txt");
  FILE* file = fopen(path.c_str(), "a");
  if (file != nullptr) {
    fwrite(fileBuffer, 1, fileLength, file);
    fclose(file);
  } else if (config.serial) {
    // Say why the file is missing, once, on the serial console (not through the
    // log itself: this is the log's own file sink failing).
    static bool reported = false;
    if (!reported) {
      reported = true;
      char note[256];
      int n = snprintf(note, sizeof(note),
                       "[Impression] cannot open log file '%s' (errno %d); file logging is off\n",
                       path.c_str(), errno);
      if (n > 0) detail::serialWrite(note, static_cast<size_t>(n) < sizeof(note) ? static_cast<size_t>(n) : sizeof(note) - 1);
    }
  }
  fileLength = 0;  // dropped if the file could not be opened; never grow unbounded
  flushing = false;
}

void write(const LogCategory& category, LogLevel level, const char* format, ...) {
  ensureInitialized();

  char message[kMessageSize];
  va_list args;
  va_start(args, format);
  vsnprintf(message, sizeof(message), format, args);
  va_end(args);

  char line[kLineSize];
  int length = snprintf(line, sizeof(line), "[%s][%s] %s\n", category.name,
                        levelName(level), message);
  if (length < 0) return;
  if (static_cast<size_t>(length) >= sizeof(line)) {  // truncated: keep the newline
    length = static_cast<int>(sizeof(line)) - 1;
    line[length - 1] = '\n';
  }

  detail::routeRaw(line, static_cast<size_t>(length));
  if (level == LogLevel::Error) flush();
}

}  // namespace Log
}  // namespace Impression
