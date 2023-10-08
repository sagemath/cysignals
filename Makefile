# Optional Makefile for easier development

VERSION = $(shell cat VERSION)

PYTHON = python3
PIP = $(PYTHON) -m pip -v
LS_R = ls -Ra1

DOCTEST = $(PYTHON) -B rundoctests.py


#####################
# Build
#####################

all: build doc

build: configure
	$(PIP) install build
	$(PYTHON) -m build

install: configure
	$(PIP) install .

dist: configure
	$(PIP) install build
	chmod -R go+rX-w .
	umask 0022 && $(PYTHON) -m build --sdist

doc: install
	cd docs && $(MAKE) html


#####################
# Clean
#####################

clean: clean-doc clean-build
	rm -rf tmp

clean-build:
	rm -rf build example/build example/*.cpp

clean-doc:
	rm -rf docs/build

distclean: clean
	rm -rf .eggs example/.eggs
	rm -rf autom4te.cache
	rm -f config.log config.status
	rm -f src/config.h src/cysignals/signals.pxd src/cysignals/cysignals_config.h


#####################
# Check
#####################

test: check

check: check-all

check-all:
	$(MAKE) check-install

# Install and check
check-install: check-doctest check-example

check-doctest: install
	$(DOCTEST) src/cysignals/*.pyx

check-example: install
	$(PYTHON) -m pip install -U build setuptools wheel Cython
	cd example && $(PYTHON) -m build --no-isolation .

check-gdb: install
	$(PYTHON) testgdb.py


#####################
# Maintain
#####################

configure: configure.ac
	autoconf
	autoheader
	@rm -f src/config.h.in~

.PHONY: all build doc install dist doc clean clean-build clean-doc \
	distclean test check check-all check-install \
	check-doctest check-example
