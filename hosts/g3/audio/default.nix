{ ... }:
{
  sound.enable = true;

  programs.noisetorch = {
    enable = true;
  };

  services.pipewire = {
    enable = true;

    pulse.enable = true;

    alsa = {
      enable = true;
      support32Bit = true;
    };
  };
}
