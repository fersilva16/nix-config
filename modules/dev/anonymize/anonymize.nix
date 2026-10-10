# anonymize: de-identify a clinical text file with a local ollama model.
#
#   anonymize note.txt            -> note.anon.txt
#   anonymize note.txt out.txt
#   anonymize note.txt note.txt   (in place, replaced only on success)
#   anonymize --field note.text notes.json
#                                 -> notes.anon.json, only that field changed
#
# Talks only to the ollama server on 127.0.0.1, so the text never leaves the
# machine and no account is involved. Needs a local server running and the
# model pulled; the script prints the exact fix when either is missing. The
# fixes pin OLLAMA_HOST=127.0.0.1 because the ollama module points the plain
# CLI at the fleet's GPU server.
{ mkUserModule, pkgs, ... }:
let
  anonymize = pkgs.writers.writePython3Bin "anonymize" {
    # The prompt is prose; wrapping it would change what the model reads.
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./anonymize.py);
in
mkUserModule {
  name = "anonymize";
  requires = [ "ollama" ];
  home.home.packages = [ anonymize ];
}
