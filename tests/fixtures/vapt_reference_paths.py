"""Historical pathname checks, test reference only, never serving authority.

Production serving is descriptor-based and rejects every symlink component.
"""
from pathlib import Path


def selected_directory(path):
    if not isinstance(path, str) or not path:
        raise ValueError('select an explicit directory')
    directory = Path(path).resolve(strict=True)
    if not directory.is_dir():
        raise ValueError('selection is not a directory')
    return directory


def confined_path(directory, relative):
    """Resolve a serving request beneath its selected root; refuse escapes.

    The serving slice must open/revalidate the selected file immediately before
    reading bytes; this helper is not an open file descriptor or race guarantee.
    """
    root = selected_directory(str(directory))
    if not isinstance(relative, str) or '\x00' in relative or Path(relative).is_absolute():
        raise ValueError('invalid relative serving path')
    candidate = (root / relative).resolve(strict=True)
    if not candidate.is_relative_to(root):
        raise ValueError('serving path escapes selected directory')
    return candidate
