{ ... }: {
  programs.chromium = {
    enable = true;

    extensions = [
      {
        # uBlock Origin
        id = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
      }
      {
        # Bitwarden
        id = "nngceckbapebfimnlniiiahkandclblb";
      }
      {
        # Phantom Wallet
        id = "bfnaelmomeimhlpmgjnjophhpkkoljpa";
      }
    ];
  };
}
