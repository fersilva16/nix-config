# The user has a ~/.omo agent home: limi-suite's Nalum, which is omo, uses it
# as its home and `requires` this. Modules that drop rules, skills, prompts or
# extensions into ~/.omo check this one flag.
{ mkUserModule, ... }:
mkUserModule {
  name = "omo-home";
}
