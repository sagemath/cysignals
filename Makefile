# Optional Makefile for easier development

PYTHON=python

all:
	$(PYTHON) setup.py build

install:
	$(PYTHON) setup.py install

dist:
	$(PYTHON) setup.py sdist

clean:
	rm -rf build

distclean: clean

check:
	$(PYTHON) -m doctest src/cysignals/*.pyx

test: check

.PHONY: all install dist clean distclean check test
