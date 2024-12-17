project('cysignals_example', 'cython', 'cpp')

py = import('python').find_installation()

inc_cysignals = run_command(
  py,
  [
    '-c',
    '''
import cysignals
print(cysignals.__file__.replace('__init__.py', ''))
    '''.strip(),
  ],
  check: true,
).stdout().strip()
cysignals = declare_dependency(include_directories: inc_cysignals)

py.extension_module('cysignals_example',
  sources: ['cysignals_example.pyx'],
  install: true,
  dependencies: [cysignals],
  override_options: ['cython_language=cpp'],
  subdir: 'cysignals_example'
)
