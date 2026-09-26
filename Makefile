# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Builds libimpression.a. Runs inside the toolchain container (see
# docker-compose.yml and scripts/make.sh|ps1), which provides PS2DEV and PS2SDK.
#
# Tyra's engine library is built on demand: every build calls the engine's own
# Makefile first, which is a no-op when libtyra.a is already up to date.
# Games link both libraries: -limpression -ltyra.

TARGET      := libimpression.a
TYRADIR     ?= extern/tyra
TYRA_ENGINE := $(TYRADIR)/engine
TYRA_LIB    := $(TYRA_ENGINE)/bin/libtyra.a

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
CFLAGS      :=
LIB         :=
LIBDIRS     :=
INC         := -I$(INCDIR) -I$(TYRA_ENGINE)/inc
INCDEP      := -I$(INCDIR) -I$(TYRA_ENGINE)/inc

include $(TYRADIR)/Makefile.base

# Build (or refresh) Tyra before the framework. Always delegated to the engine's
# Makefile so a changed submodule is picked up; it does nothing when up to date.
tyra:
	$(MAKE) -C $(TYRA_ENGINE)

clean-tyra:
	$(MAKE) -C $(TYRA_ENGINE) cleaner

$(TARGET): tyra

# log_serial.cpp reaches libc's _ps2sdk_write, which is outside the gp-relative
# small-data area; it must not be compiled with gp-relative access to externs.
$(BUILDDIR)/log_serial.$(OBJEXT): CFLAGS += -G0

# Static library instead of an executable (same override Tyra's engine/Makefile uses).
$(TARGET): $(OBJECTS) $(VCL_OBJECTS) $(VU_OBJECTS_VCL) $(VU_OBJECTS_VSM) $(IRXEM_OBJECTS)
	$(AR) rcs $(TARGETDIR)/$(TARGET) $(OBJECTS) $(VCL_OBJECTS) $(VU_OBJECTS_VCL) $(VU_OBJECTS_VSM) $(IRXEM_OBJECTS)

.PHONY: tyra clean-tyra
