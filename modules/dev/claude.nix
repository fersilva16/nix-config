# Claude Desktop. darwin: the cask. linux: Anthropic's official beta .deb via
# the claude-desktop flake input, built against the host's nixpkgs. Cowork
# runs its VM under QEMU/KVM and needs /dev/vhost-vsock, which only the kvm
# group can open.
{
  mkUserModule,
  forPlatform,
  inputs,
  pkgs,
  ...
}:
mkUserModule {
  name = "claude";
  casks = [ "claude" ];
  home.home.packages = forPlatform {
    linux = [ (pkgs.callPackage "${inputs.claude-desktop}/pkgs/claude-desktop" { }) ];
  };
  user = forPlatform { linux.extraGroups = [ "kvm" ]; };
}
