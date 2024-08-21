{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    pam-reattach # for tmux
  ];

  environment.etc = {
    "pam.d/sudo_local" = {
      text = ''
        auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so
        auth       sufficient     pam_tid.so
      '';
    };
  };
}
