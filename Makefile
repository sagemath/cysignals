# Optional Makefile for easier development

VERSION = $(shell cat VERSION)

PYTHON = python
PIP = $(PYTHON) -m pip -v
DOCTEST = $(PYTHON) -B rundoctests.py
LS_R = ls -Ra1


#####################
# Build
#####################

all: build doc

build: configure
	$(PYTHON) setup.py build

install: configure
	$(PIP) install --no-index --ignore-installed .

dist: configure
	chmod go+rX-w -R .
	umask 0022 && $(PYTHON) setup.py sdist --formats=bztar

doc:
	cd docs && $(MAKE) html


#####################
# Clean
#####################

clean: clean-doc clean-build

clean-build:
	rm -rf build example/build example/*.cpp

clean-doc:
	rm -rf docs/build

distclean: clean
	rm -rf autom4te.cache
	rm -f config.log config.status


#####################
# Check
#####################

test: check

check: check-tmp

check-all: check-tmp check-install

# Install and check
check-install: check-doctest check-example

check-doctest: install
	$(DOCTEST) src/cysignals/*.pyx

check-example: install
	cd example && $(PYTHON) setup.py clean build

check-gdb: install
	$(PYTHON) testgdb.py


#####################
# Check installation
#####################
#
# Test 2 installation scenarios without a real installation
# - prefix (with --prefix and --root)
# - user (with --user)

check-tmp: check-prefix check-user
	rm -rf tmp

prefix-install: configure
	rm -rf tmp/local tmp/build
	$(PYTHON) setup.py install --prefix="`pwd`/tmp/local" --root=tmp/build
	cd tmp && mv "build/`pwd`/local" local
	cd tmp && ln -s local/lib*/python*/site-packages site-packages

check-prefix: check-prefix-doctest check-prefix-example

check-prefix-doctest: prefix-install
	export PYTHONPATH="`pwd`/tmp/site-packages" && $(DOCTEST) src/cysignals/*.pyx

check-prefix-example: prefix-install
	rm -rf example/build
	export PYTHONPATH="`pwd`/tmp/site-packages" && cd example && $(PYTHON) setup.py clean build

check-user: check-user-doctest check-user-example

user-install: configure
	rm -rf tmp/user
	export PYTHONUSERBASE="`pwd`/tmp/user" && $(PYTHON) setup.py install --user --single-version-externally-managed --record=/dev/null

check-user-doctest: user-install
	export PYTHONUSERBASE="`pwd`/tmp/user" && $(DOCTEST) src/cysignals/*.pyx

check-user-example: user-install
	export PYTHONUSERBASE="`pwd`/tmp/user" && cd example && $(PYTHON) setup.py clean build

distcheck: dist
	rm -rf dist/check
	mkdir -p dist/check
	cd dist/check && tar xjf ../cysignals-$(VERSION).tar.bz2
	cd dist/check/cysignals-$(VERSION) && $(LS_R) >../dist0.ls
	cd dist/check/cysignals-$(VERSION) && $(MAKE) all
	cd dist/check/cysignals-$(VERSION) && $(MAKE) distclean
	cd dist/check/cysignals-$(VERSION) && $(LS_R) >../dist1.ls
	cd dist/check; diff -u dist0.ls dist1.ls || { echo >&2 "Error: distclean after all leaves garbage"; exit 1; }
	cd dist/check/cysignals-$(VERSION) && $(MAKE) check-tmp
	cd dist/check/cysignals-$(VERSION) && $(MAKE) distclean
	cd dist/check/cysignals-$(VERSION) && $(LS_R) >../dist2.ls
	cd dist/check; diff -u dist0.ls dist2.ls || { echo >&2 "Error: distclean after check-tmp leaves garbage"; exit 1; }
	cd dist/check/cysignals-$(VERSION) && $(MAKE) dist
	cd dist/check/cysignals-$(VERSION) && tar xjf dist/cysignals-$(VERSION).tar.bz2
	cd dist/check/cysignals-$(VERSION)/cysignals-$(VERSION) && $(LS_R) >../../dist3.ls
	cd dist/check; diff -u dist0.ls dist3.ls || { echo >&2 "Error: sdist is not reproducible"; exit 1; }
	rm -rf dist/check


#####################
# Maintain
#####################

configure: configure.ac
	autoconf
	autoheader
	@rm -f src/config.h.in~

.PHONY: all build doc install dist doc clean clean-build clean-doc \
	distclean test check check-all check-tmp check-install \
	check-doctest check-example \
	check-prefix prefix-install check-prefix-doctest check-prefix-example \
	check-user user-install check-user-doctest check-user-example
