{ mkUserModule, ... }:
mkUserModule {
  name = "ssh";
  system.programs.ssh = {
    extraConfig = ''
      Host *
        IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    '';
  };
}
