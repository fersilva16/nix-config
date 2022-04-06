{ ... }:
{
  programs.ssh = {
    extraConfig = ''
      AddressFamily inet
    '';
  };
}
