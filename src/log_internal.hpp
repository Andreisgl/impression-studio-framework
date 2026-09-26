// Copyright 2026 Andrei Segal
// SPDX-License-Identifier: Apache-2.0

// Private interface between log.cpp (sinks, formatting) and log_serial.cpp
// (EE serial port and the libc stdout hook). Not installed.

#pragma once

#include <stddef.h>

namespace Impression {
namespace detail {

/** Implemented in log_serial.cpp. */
void serialInit();
void serialWrite(const char* data, size_t length);
void installStdoutHook();
bool stdoutRedirected();

/** Implemented in log.cpp: sends raw text to every enabled sink. */
void routeRaw(const char* data, size_t length);

}  // namespace detail
}  // namespace Impression
