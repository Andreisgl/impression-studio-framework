# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# The one Makefile fragment every Impression project includes. A project Makefile
# is only this:
#
#   TARGET := game.elf
#   include $(IMPRESSION_HOME)/mk/project.mk
#
# IMPRESSION_HOME is set by the toolchain container (/work for framework
# development, /impression in the SDK). Build with `imp build`, which runs make
# in the project folder (/project).
#
# Conventions (override before the include if needed): sources in src/, headers in
# inc/, objects in obj/, the ELF in bin/, resources copied from res/. Add your own
# flags and libraries by setting CFLAGS, INC and LIB before the include; the
# framework and Tyra are appended after them.

ifndef IMPRESSION_HOME
$(error IMPRESSION_HOME is not set; build through the toolchain container (imp build))
endif
ifndef TARGET
$(error set TARGET (for example game.elf) before including project.mk)
endif

TYRADIR   := $(IMPRESSION_HOME)/extern/tyra
ENGINEDIR := $(TYRADIR)/engine

SRCDIR    ?= src
INCDIR    ?= inc
BUILDDIR  ?= obj
TARGETDIR ?= bin
RESDIR    ?= res
SRCEXT    := cpp
VSMEXT    := vsm
VCLEXT    := vcl
VCLPPEXT  := vclpp
DEPEXT    := d
OBJEXT    := o

CFLAGS    ?=
# Order matters: the framework depends on Tyra, so -limpression comes first.
LIB       := $(LIB) -limpression -ltyra
LIBDIRS   := $(LIBDIRS) -L$(IMPRESSION_HOME)/bin -L$(ENGINEDIR)/bin
INC       := -I$(INCDIR) $(INC) -I$(IMPRESSION_HOME)/inc -I$(ENGINEDIR)/inc
INCDEP    := $(INC)

include $(TYRADIR)/Makefile.base

# Build (or refresh) the framework and Tyra before linking the game. Order-only
# (after the |) because Makefile.base's link rule passes every normal prerequisite
# ($^) to the linker. The ELF is never a file at this path, so it always relinks.
framework:
	$(MAKE) -C $(IMPRESSION_HOME)

$(TARGET): | framework

.PHONY: framework
