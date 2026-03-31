{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "minikube";
  home.home.packages = with pkgs; [ minikube ];
}
