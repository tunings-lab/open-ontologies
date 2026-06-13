"""Open Ontologies Lite: a lightweight, pip-installable Python bridge to the
Oxigraph RDF/OWL engine. No Rust toolchain, no compilation, prebuilt wheels only.
"""

from .engine import OntologyEngine, ValidationResult, resolve_format

__version__ = "0.1.0"
__all__ = ["OntologyEngine", "ValidationResult", "resolve_format", "__version__"]
