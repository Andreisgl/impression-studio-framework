// Copyright 2026 Andrei Segal
// SPDX-License-Identifier: Apache-2.0

#include <tyra>

#include "hello_game.hpp"

int main() {
  // Log to <elf folder>/log.txt instead of the console, so the output is
  // available without any emulator console setting.
  Tyra::EngineOptions options;
  options.writeLogsToFile = true;

  Tyra::Engine engine(options);
  HelloGame game(&engine);
  engine.run(&game);
  return 0;
}
