// Copyright 2026 Andrei Segal
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <tyra>

class HelloGame : public Tyra::Game {
 public:
  explicit HelloGame(Tyra::Engine* engine);
  ~HelloGame();

  void init();
  void loop();

 private:
  Tyra::Engine* engine;
  unsigned frames;
};
