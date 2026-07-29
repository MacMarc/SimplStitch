# SimplStitch vendor patch: wx-free stub. See VENDOR_PATCHES.md.
#
# Original imports wx to load/save Inkscape swatch files for the Tartan-Fill
# GUI palette editor. SimplStitch never sets fill_method=tartan_fill, so
# Palette is imported by name (tartan/utils.py, elements/fill_stitch.py) but
# never instantiated in any code path SimplStitch exercises.


class Palette:
    def __init__(self, *args, **kwargs):
        raise NotImplementedError(
            "Tartan-Fill palette editing is not supported in SimplStitch's headless InkStitch build."
        )
