// Copyright 2026 Andrei Segal
// SPDX-License-Identifier: Apache-2.0

// EE serial port output and the libc stdout redirect.
//
// libc's printf ends up in newlib's _write system call, which ps2sdk's libcglue
// implements. Defining _write here replaces that one function: stdout and stderr
// (fd 1 and 2) go to the logging sinks when the redirect is on, and every other
// file descriptor is forwarded to _ps2sdk_write, ps2sdk's own implementation, so
// files (log.txt, game data) keep working. This works with old and new ps2sdk
// (before 2024 _ps2sdk_write was a function pointer; it is called the same way).

#include <errno.h>
#include <sio.h>
#include <stdio.h>

extern "C" {
#include <ps2sdkapi.h>  // _ps2sdk_write
}

#include "log_internal.hpp"

namespace Impression {
namespace detail {

namespace {
bool sioReady = false;
bool redirected = false;
}  // namespace

void serialInit() {
  if (sioReady) return;
  sio_init(38400, 0, 0, 0, 0);
  sioReady = true;
}

void serialWrite(const char* data, size_t length) {
  if (!sioReady) return;
  sio_write(const_cast<char*>(data), length);
}

void installStdoutHook() {
  if (redirected) return;
  // Line-buffered, so each printf line reaches _write whole.
  setvbuf(stdout, nullptr, _IOLBF, 0);
  redirected = true;
}

bool stdoutRedirected() { return redirected; }

}  // namespace detail
}  // namespace Impression

// Replaces libcglue's _write (a separate object in libcglue.a, so no duplicate
// symbol). Not in a namespace: newlib looks it up by its C name.
extern "C" int _write(int fd, const void* buffer, size_t size) {
  if ((fd == 1 || fd == 2) && Impression::detail::stdoutRedirected()) {
    Impression::detail::routeRaw(static_cast<const char*>(buffer), size);
    return static_cast<int>(size);
  }
  int result = _ps2sdk_write(fd, buffer, static_cast<int>(size));
  if (result < 0) {  // ps2sdk returns -errno; newlib wants -1 with errno set
    errno = -result;
    return -1;
  }
  return result;
}
