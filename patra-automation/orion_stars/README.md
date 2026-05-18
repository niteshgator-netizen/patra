# Orion Stars automation

Orion Stars automation. Cloned from `../panda_master/` on 2026-05-16. See `../milky_way/BUGS_FIXED.md` for the bug log — same fixes apply (same ASP.NET engine).

Run: `py -3.12 orion_stars.py login`

AdsPower profile: create `Orion_Stars_Pilot`, then copy its profile ID into `.env`. Uses `https://orionstars.vip:8781/default.aspx`.

Orion Stars has one extra login quirk: the Rocket Ramp announcement popup on `Store.aspx` is automatically closed when present.
