{ ... }:
{
  programs.xmobar = {
    enable = true;
    extraConfig = ''
      Config {
         font = "xft:Iosevka:pixelsize=16"
       , position = BottomP 0 230
       , commands = [
                Run Cpu ["-L","3","-H","50","--normal","green","--high","red","-t","CPU <total>%"] 10,
                Run Memory ["-t","RAM <used>M/<total>M"] 10,
                Run DiskU [("/", "<used>/<size>"), ("/joguinhos", "<used>/<size>"), ("/coisas", "<used>/<size>")] ["-L", "20", "-H", "50", "-m", "1", "-p", "3"] 20,
                Run Date "%a %b %_d %l:%M" "date" 10,
                Run Volume "default" "Master" ["-t", "vol. <volume>%"] 10,
                Run StdinReader
              ]
       , sepChar = "%"
       , alignSep = "}{"
       , template = "%StdinReader% }{ %default:Master% | %cpu% | %memory% | %disku% | <fc=#ee9a00>%date%</fc>"
      }
    '';
  };
}
