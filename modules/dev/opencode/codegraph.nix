{ pkgs }:
{
  home = {
    # OMO_CODEGRAPH_BIN is the FIRST branch of oh-my-openagent's
    # resolveCodegraphCommand, and resolveOrProvisionCommand returns early on
    # `resolved.exists`. Setting it therefore skips two things that are
    # otherwise broken here:
    #
    #   1. The version pin. OMO provisions CODEGRAPH_PINNED_VERSION = 1.5.0,
    #      whose catch-up sync dies on "Maximum call stack size exceeded" and
    #      leaves the daemon spinning. There is no config knob for the version;
    #      the binary override is the only way past it.
    #   2. The Node gate. OMO checks `which node` against a supported range of
    #      20..24 BEFORE provisioning, and rejects this machine's Node 26 as
    #      unsupported — even though codegraph's own shim execs a bundled Node
    #      and never touches the system one. The early return means that check
    #      never runs, so no Node needs to be installed at all.
    home.sessionVariables.OMO_CODEGRAPH_BIN = "${pkgs.codegraph}/bin/codegraph";
  };
}
