// Copyright 2026 Andrei Segal
// SPDX-License-Identifier: Apache-2.0

// EE serial port output and the libc stdout hook. This file is compiled with -G0
// (see the Makefile): _ps2sdk_write lives outside the gp-relative small-data
// area, so a gp-relative access to it fails to link.

#include <sio.h>
#include <stdio.h>

extern "C" {
#include <ps2sdkapi.h>  // declares _ps2sdk_write; the header has no extern "C" guard
}

#include "log_internal.hpp"

namespace Impression {
namespace detail {

namespace {

typedef int (*WriteFn)(int, const void*, int);

WriteFn originalWrite = nullptr;
bool sioReady = false;
bool hooked = false;

// libc calls _ps2sdk_write for every file descriptor, so only stdout and stderr
// are redirected; everything else (log.txt, game files) goes to the original.
int hookedWrite(int fd, const void* buffer, int size) {
  if (fd == 1 || fd == 2) {
    routeRaw(static_cast<const char*>(buffer), static_cast<size_t>(size));
    return size;
  }
  if (originalWrite != nullptr) return originalWrite(fd, buffer, size);
  return -1;
}

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
  if (hooked) return;
  originalWrite = _ps2sdk_write;
  _ps2sdk_write = hookedWrite;
  // Line-buffered, so each printf line reaches the hook whole.
  setvbuf(stdout, nullptr, _IOLBF, 0);
  hooked = true;
}

}  // namespace detail
}  // namespace Impression
