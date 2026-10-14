# The user has a ~/.omo agent home, whichever module owns it: `omo`, or
# `limi-suite` (whose Nalum is omo). Both `requires` this, so modules that drop
# rules, skills, prompts or extensions into ~/.omo check this one flag.
{ mkUserModule, ... }:
mkUserModule {
  name = "omo-home";
}
