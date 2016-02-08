# Optional Makefile for easier development

PYTHON=python

all: build doc

build:
	$(PYTHON) setup.py build

install:
	$(PYTHON) setup.py install

dist:
	$(PYTHON) setup.py sdist

doc:
	cd docs && $(MAKE) html

clean: clean-doc clean-build

clean-build:
	rm -rf build

clean-doc:
	cd docs && $(MAKE) clean

distclean: clean

check: check-doctest check-example

check-doctest: install
	$(PYTHON) -m doctest src/cysignals/*.pyx

check-example: install
	cd example && $(PYTHON) setup.py build

test: check

.PHONY: all build doc install dist clean distclean check test
