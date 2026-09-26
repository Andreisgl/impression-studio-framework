// Copyright 2026 Andrei Segal
// SPDX-License-Identifier: Apache-2.0

#include <tyra>

#include "hello_game.hpp"
#include "impression/log.hpp"

int main() {
  // Before the Engine, so its startup messages are captured too. The logging
  // layer writes <elf folder>/log.txt and the EE serial console, so Tyra's own
  // file logging stays off (the default).
  Impression::Log::init();

  Tyra::Engine engine;
  HelloGame game(&engine);
  engine.run(&game);
  return 0;
}
