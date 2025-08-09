# QLC module package init

# Import the compiled Cython extensions
try:
    from . import py
except ImportError as e:
    # If compiled modules are not available, this is expected during development
    pass
