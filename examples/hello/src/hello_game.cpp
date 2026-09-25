// Copyright 2026 Andrei Segal
// SPDX-License-Identifier: Apache-2.0

#include "hello_game.hpp"

#include "impression/version.hpp"

HelloGame::HelloGame(Tyra::Engine* t_engine) : engine(t_engine) {}

HelloGame::~HelloGame() {}

void HelloGame::init() {
  TYRA_LOG("Hello from Impression Studio framework ", Impression::version());
}

void HelloGame::loop() {}
