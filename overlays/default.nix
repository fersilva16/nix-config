self: super:
let
  inherit (super) lib;
in
{
  nvidia-vaapi-driver = lib.hiPrio super.nvidia-vaapi-driver;
}
