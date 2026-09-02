# Retail Player Static Trace

This trace records the bounded player facts used by the remake simulation. It is based on the retail `warblade.exe` with SHA-256 `ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef` and the bundled English manual.

## Coordinate convention and spawn

The retail player session stride is `0x4d8`. The current ship position is stored as top-left floats at:

- X: `0x8486ec + session * 0x4d8`
- Y: `0x8486f0 + session * 0x4d8`

The retail fighter atlas is 440x28 with eleven 40x28 frames. The remake uses entity centers, so retail top-left coordinates are converted by adding `(20, 14)`.

The player initializer at `0x623730` and respawn switch at `0x5eccd6` establish:

| Mode | Retail top-left X | Remake center X |
| --- | ---: | ---: |
| solo | `800 / 2 - 20 = 380` | 400 |
| alternating | `800 / 2 - 20 = 380` | 400 |
| retail simultaneous player 1 | `2 * (800 / 6) - 20 = 246` | 266 |
| retail simultaneous player 2 | `4 * (800 / 6) - 20 = 512` | 532 |

The remake preserves the retail split for duel. Its new same-team co-op mode intentionally uses explicit split centers at 330 and 470.

Retail Y is initialized from `0xe11ccc`. Its initializer computes `600 - 50 = 550`, so the remake center Y is 564 for a 28-pixel-tall frame.

## Horizontal movement

The movement consumer in `0x5eb550`:

1. reads player speed from session field `+0x10` (`0x8486fc` for session 0);
2. multiplies it by the global movement scale at `0x7cd034`;
3. caps it at 14;
4. multiplies it by the authoritative tick scale at `0xe11274`;
5. adds or subtracts the result from X.

The static defaults initialized near `0x59acad` are:

| Value | Address | Default |
| --- | --- | ---: |
| base lateral speed | `0x8f2080` | 4.0 |
| speed upgrade increment | `0x8f2084` | 0.75 |
| maximum upgrade count | `0x8f2088` | 16 |
| normal movement scale | `0x7cd034` | 1.0 |
| final movement cap | `0x77dc48` | 14.0 |

The same movement routine clamps retail top-left X to 64 through `800 - 104 = 696`. With a 40-pixel frame, the remake center bounds are therefore 84 through 716.

## Starting-fighter encoding

The bundled `Warblade_Manual_V1.34_Eng.txt` says: “You start with three lives / fighters. 1 in play and 2 on side bar.”

The retail player table initializes the encoded count to 3 with a maximum of
5. The HUD derives the same count and hides one icon for the active fighter,
so the initial sidebar contains two reserve icons. Death subtracts one encoded
step before testing the result; the first and second deaths respawn with two
and one total fighters remaining, while the third reaches the base value and
is terminal. The encoded value therefore counts total fighters, not reserves.
The executable addresses and arithmetic are recorded in
`DIFFICULTY_RULES.md` and `WEAPON_RUNTIME_TRACE.md`.

## Proven versus remake-specific

Proven retail facts:

- solo and alternating spawn center X 400;
- retail simultaneous centers 266 and 532;
- top-left Y 550 and center Y 564;
- visual and hit-mask frame dimensions 40x28;
- normal base speed 4 pixels per tick;
- center X bounds 84 through 716;
- three total starting fighters and five total fighters maximum;
- decrement-before-terminal-test death accounting, with the third initial
  death terminal;
- independent per-session fighter counts for retail two-player modes.

Intentional remake behavior or presentation policy:

- simultaneous same-team co-op split centers 330 and 470;
- a single shared-lives pool across participating seats;
- exact respawn presentation timing and invulnerability duration, which are
  not claimed as recovered retail cadence.
