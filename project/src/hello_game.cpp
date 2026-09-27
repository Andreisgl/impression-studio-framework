// Copyright 2026 Andrei Segal
// SPDX-License-Identifier: Apache-2.0

#include "hello_game.hpp"

#include "impression/log.hpp"
#include "impression/version.hpp"

// Logging demo: two categories with different default runtime levels.
IMP_DEFINE_LOG_CATEGORY(Hello, Info);
IMP_DEFINE_LOG_CATEGORY(Frame, Warning);

HelloGame::HelloGame(Tyra::Engine* t_engine) : engine(t_engine), frames(0) {}

HelloGame::~HelloGame() {}

void HelloGame::init() {
  IMP_LOG(Hello, Info, "Hello from Impression Studio framework %s",
          Impression::version());
  IMP_LOG(Hello, Warning, "this is a warning, number %d", 42);
  IMP_LOG(Hello, Error, "this is an error, text '%s'", "flushed at once");
  IMP_LOG(Hello, Verbose, "verbose message: hidden while Hello is at Info");
  TYRA_LOG("a raw TYRA_LOG line, routed through the stdout hook");
}

void HelloGame::loop() {
  frames++;

  // The loop is not paced to the display yet (nothing renders), so these frame
  // numbers are reached almost instantly; the order of the lines is what matters.
  if (frames == 1) {
    IMP_LOG(Frame, Info, "hidden: Frame defaults to Warning");
    IMP_LOG(Frame, Warning, "Game loop is running");
  } else if (frames == 100) {
    Impression::Log::setLevel("Hello", Impression::LogLevel::Verbose);
    Impression::Log::applySpec("Frame=Info");
  } else if (frames == 101) {
    IMP_LOG(Hello, Verbose, "verbose message: visible after the runtime setLevel");
    IMP_LOG(Frame, Info, "visible: Frame raised to Info by applySpec");
  }

  Impression::Log::flush();  // free when nothing is buffered
}
