# Credits

## Bundled artwork

- **`Art/Parchment.tga`** -- the parchment-page texture used for the
  panel backdrop. Sourced from
  [Peterodox / YUI-Dialogue](https://github.com/Peterodox/YUI-Dialogue),
  file `Art/Theme_Brown/Parchment.png`, converted to uncompressed TGA
  for WoW Classic compatibility (`magick Parchment.png -compress none
  Parchment.tga`). Image content unmodified; only the container
  format changed. Attribution and gratitude to Peterodox.

- **`Art/OptionBackground-Hollow.tga`** -- the hand-painted hollow
  parchment cell-border framing each item row in the weekly plan.
  Sourced from
  [Peterodox / YUI-Dialogue](https://github.com/Peterodox/YUI-Dialogue),
  file `Art/Theme_Brown/OptionBackground-Hollow.png`, converted to
  uncompressed 32-bit TGA for WoW Classic compatibility (`magick
  OptionBackground-Hollow.png -alpha on -type TrueColorAlpha -depth 8
  -compress none OptionBackground-Hollow.tga`). Image content
  unmodified; only the container format changed. Attribution and
  gratitude to Peterodox.

  If the original author would prefer these assets removed or replaced,
  open an issue on the Routina repository and we will swap them for a
  CC0 alternative in the next release.

## Vendored libraries

- **Ace3** suite (AceAddon, AceDB, AceEvent, AceConfig, AceLocale,
  AceDBOptions). Fetched at package time via `.pkgmeta` externals;
  see [WoWAce / Ace3](https://www.wowace.com/projects/ace3).
- **LibStub** -- standard addon-shared library loader.
- **CallbackHandler-1.0** -- the event-emitter shared across Ace3.

## Fonts

Routina uses the WoW client's built-in `FRIZQT__.TTF` and `ARIALN.TTF`.
No fonts are bundled or vendored.
