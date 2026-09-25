// Copyright 2026 Andrei Segal
// SPDX-License-Identifier: Apache-2.0

#include "hello_game.hpp"

#include "impression/version.hpp"

HelloGame::HelloGame(Tyra::Engine* t_engine) : engine(t_engine), frames(0) {}

HelloGame::~HelloGame() {}

void HelloGame::init() {
  TYRA_LOG("Hello from Impression Studio framework ", Impression::version());
}

void HelloGame::loop() {
  // Nothing is rendered yet, so the loop is not paced to the display: log the
  // first frame only, to prove loop() runs without flooding the log.
  if (frames == 0) {
    TYRA_LOG("Game loop is running");
  }
  frames++;
}
