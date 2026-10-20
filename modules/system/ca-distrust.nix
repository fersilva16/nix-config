# Root CAs pulled from the Nix CA bundle (/etc/ssl/certs/ca-certificates.crt,
# NIX_SSL_CERT_FILE) ahead of nixpkgs shipping the fix. Names are the bundle
# labels. cacert fails the build on a name its store lacks, so once nixpkgs
# ships NSS >= 3.131.1 the rebuild breaks here: that is the cue to delete
# this module.
#
# eMudhra, 2026-10-20 (https://emudhra.we-have-a-problem.com/): the private
# keys of eight intermediates under "emSign ECC Root CA - G3" are factorable.
# Mirrors NSS 3.131.1, which also dropped the C1/C3 roots in the same release.
# This covers nix-built tools only; macOS Keychain trust (Safari, Apple's
# Security framework) is Apple's update to ship.
{ mkSystemModule, ... }:
mkSystemModule {
  name = "ca-distrust";
  config.security.pki.caCertificateBlacklist = [
    "emSign ECC Root CA - G3"
    "emSign ECC Root CA - C3"
    "emSign Root CA - C1"
  ];
}
