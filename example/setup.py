# meson.build

project('cysignals_example', 'python')

py3_mod = import('python').find_installation('python3')

py3_mod.extension_module('cysignals_example',
  sources: ['cysignals_example.pyx'],
  install: true,
  subdir: 'cysignals_example'
)
