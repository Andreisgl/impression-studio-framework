// Copyright 2026 Andrei Segal
// SPDX-License-Identifier: Apache-2.0

#include <tyra>

#include "hello_game.hpp"

int main() {
  Tyra::Engine engine;
  HelloGame game(&engine);
  engine.run(&game);
  return 0;
}
