"""Qubi: a persistent multi-tier router in front of `goose acp`."""
from .protocol import PROTOCOL, VERSION

__all__ = ["PROTOCOL", "VERSION"]
__version__ = VERSION
