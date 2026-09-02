# Letter awards (E-X-T-R-A / A-R-T-X-E)

Executable-backed contract for the retail letter pickups, the strict
consecutive forward and reverse sequence awards, and the all-collected
award. Extracted from the pinned retail executable `ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef`.

Dispatcher: `0x00571c60` (bonus cases 0-4 are the
letters E, X, T, R, A).

## Banners

| Award | Banner | String VA | Dispatcher reference |
| --- | --- | --- | --- |
| extra | `*** E X T R A ***` | `0x0077db30` | `0x00574327` |
| super_extra | `*** S U P E R   E X T R A ***` | `0x0077db0c` | `0x00574554` |
| artxe | `*** A R T X E ***` | `0x0077db74` | `0x0057209d` |
| super_artxe | `*** S U P E R   A R T X E ***` | `0x0077db50` | `0x005720f7` |

## Contract

- A letter collect awards 100 points
  (score multiplier applies) only when the letter's flag is already
  set — a duplicate collect. A fresh collect scores nothing; it just
  sets the flag. Both paths update the two chain registers and run the
  completion checks.
- Two single-character chain registers per player (struct offsets
  `0x7cc` forward, `0x7cd` reverse) advance only when they hold the
  collected letter's exact predecessor: forward E-X-T-R-A, reverse A-R-T-X-E. E seeds the forward register
  and A seeds the reverse register unconditionally; any other mismatch
  clears the register.
- Completing a chain fills fighters and armour to their caps and shows
  the banner for 3000 ms; when both are already capped the SUPER
  variant instead awards 5000000 points
  (multiplied) with a floating score text. The forward and reverse
  completions use distinct retail voice slots (0x14 / 0x15).
- After every collect, when all five flags are set: one fighter is
  granted (plus ten bonus-time units through the clamped bonus-time
  path), or one armour when fighters are capped (ARMOUR banner,
  1000 ms), or 1000000 points (multiplied)
  when both are capped. The five flags are not cleared by the award,
  so later letters re-trigger it.

## Evidence-only observations

- `0x007d0b0c`: Initialized to 20 and matching the difficulty contract's bonus_time_start; the fighter branch of the all-collected award adds 10. The remake grants the ten units through its clamped bonus-time path.
- `0x007d1be0`: Initialized to 10; the armour branch adds 5. Its runtime meaning is unproven, so the remake mirrors no gameplay effect and keeps the observation as lossless evidence.

## Reproduction

```sh
python3 tools/letter_award_extract.py
python3 tools/letter_award_extract.py --check
python3 tools/letter_award_test.py
```
