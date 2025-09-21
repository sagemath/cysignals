project('cysignals_example', 'cython', 'cpp')

py = import('python').find_installation()

cysignals = dependency('cysignals')

py.extension_module('cysignals_example',
  sources: ['cysignals_example.pyx'],
  install: true,
  dependencies: [cysignals],
  override_options: ['cython_language=cpp'],
  subdir: 'cysignals_example'
)
