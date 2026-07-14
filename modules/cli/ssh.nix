{ mkUserModule, forPlatform, ... }:
mkUserModule {
  name = "ssh";
  system.programs.ssh = {
    extraConfig = ''
      Host *
        IdentityAgent "${
          forPlatform {
            darwin = "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
            linux = "~/.1password/agent.sock";
          }
        }"
    '';
  };
}
