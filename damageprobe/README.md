# Damage Probe

Developer probe, read-only. Five seconds after the hero appears in the world it writes `hlx/mods/damageprobe/probe.txt`:

- signatures (argument and return types) of the hit / damage methods of the hero's classes and of the skill classes;
- field types of `ent.Projectile`, `st.skill.SkillArea`, `st.skill.SkillContext`, `st.skill.BaseSkill`, `st.skill.DamageResult`, `st.skill.HitResult`;
- damage-related fields of the live hero, repeated every 15 s (20 snapshots at most).

Build: `haxe compile.hxml`, then copy `build/damageprobe/damageprobe.hl` to `hlx/mods/damageprobe/`.
