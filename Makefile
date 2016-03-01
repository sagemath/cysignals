# Optional Makefile for easier development

PYTHON=python

all: build doc

build: configure
	$(PYTHON) setup.py build

install: build
	$(PYTHON) setup.py install

dist: configure
	chmod go+rX-w -R .
	umask 0022 && $(PYTHON) setup.py sdist --formats=bztar

distcheck: dist
	mkdir -p dist/check
	VERSION=`cat VERSION`; cd dist/check && tar xjf ../cysignals-$$VERSION.tar.bz2
	VERSION=`cat VERSION`; cd dist/check/cysignals-$$VERSION && ./configure && $(MAKE) all check
	rm -rf dist/check

doc:
	cd docs && $(MAKE) html

clean: clean-doc clean-build

clean-build:
	rm -rf build example/build example/*.c

clean-doc:
	cd docs && $(MAKE) clean

distclean: clean
	rm -rf autom4te.cache
	rm -f config.log config.status

check: check-doctest check-example

check-doctest: install
	$(PYTHON) -m doctest src/cysignals/*.pyx

check-example: install
	cd example && $(PYTHON) setup.py build

test: check

configure: configure.ac
	autoconf
	autoheader
	@rm -f src/config.h.in~

.PHONY: all build doc install dist doc clean clean-build clean-doc \
	distclean check check-doctest check-example test
