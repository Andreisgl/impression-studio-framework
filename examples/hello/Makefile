# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Sample game: links both libraries. Build from the repo root with
#   scripts/make.sh -C examples/hello
# (runs in the toolchain container; builds Tyra and the framework first).

TARGET      := hello.elf
FWDIR       := ../..
TYRADIR     ?= $(FWDIR)/extern/tyra
ENGINEDIR   := $(TYRADIR)/engine

#The Directories, Source, Includes, Objects, Binary and Resources
SRCDIR      := src
INCDIR      := inc
BUILDDIR    := obj
TARGETDIR   := bin
RESDIR      := res
SRCEXT      := cpp
VSMEXT      := vsm
VCLEXT      := vcl
VCLPPEXT    := vclpp
DEPEXT      := d
OBJEXT      := o

#Flags, Libraries and Includes
# Order matters: the framework depends on Tyra, so -limpression comes first.
CFLAGS      :=
LIB         := -limpression -ltyra
LIBDIRS     := -L$(FWDIR)/bin -L$(ENGINEDIR)/bin
INC         := -I$(INCDIR) -I$(FWDIR)/inc -I$(ENGINEDIR)/inc
INCDEP      := -I$(INCDIR) -I$(FWDIR)/inc -I$(ENGINEDIR)/inc

include $(TYRADIR)/Makefile.base

# Build (or refresh) the framework and Tyra before linking the game. Order-only
# (after the |) because Makefile.base's link rule passes every normal prerequisite
# ($^) to the linker. The ELF is never a file at this path, so it always relinks.
framework:
	$(MAKE) -C $(FWDIR)

$(TARGET): | framework

.PHONY: framework
