configure_file(output: 'cysignals_config.h', configuration: config, install_dir: py.get_install_dir(pure: false) / 'cysignals', install: true)

py.install_sources(
    '__init__.py',
    'memory.pxd',
    'pysignals.pxd',
    'signals.pxd',
    'struct_signals.h',
    'macros.h',
    subdir: 'cysignals'
)

extensions = {
    'alarm': files('alarm.pyx'),
    'pselect': files('pselect.pyx'),
    'pysignals': files('pysignals.pyx'),
    'signals': files('signals.pyx'),
    'tests': files('tests.pyx'),
}

test_files = []

foreach name, pyx : extensions
    if name != 'signals' and is_windows
        # These modules are not supported on Windows
        continue
    endif

    test_files += pyx

    # Platform-specific source files
    extra_sources = []
    if is_cygwin and name == 'signals'
        extra_sources += files('implementation_cygwin.c')
    endif

    py.extension_module(name,
        pyx, extra_sources,
        include_directories: [include_directories('.'), src],
        dependencies: [py_dep, threads_dep],
        install: true,
        subdir: 'cysignals'
    )
endforeach
