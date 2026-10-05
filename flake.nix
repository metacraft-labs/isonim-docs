{
  description = "isonim-docs — self-contained dev shell for the IsoNim-powered docs SSG";

  inputs = {
    # isonim is the ONLY declared dependency: it owns the docs toolchain
    # (nim, nimble, nodejs, yarn, esbuild, prefetch-yarn-deps, just, …) and
    # exposes it as ``devShells.default``. We reuse that dev shell verbatim so
    # isonim-docs is buildable from ITS OWN shell without anyone ever having to
    # ``nix develop ../isonim``.
    #
    # Pinned to the published ``isonim/dev`` for CI / standalone clones.
    # In the workspace, direnv's flake-overrides plugin (see .envrc) rewrites
    # this to the local sibling with ``--override-input isonim path:../isonim``
    # so a checkout of isonim next door is used automatically. To do it by
    # hand: ``nix develop --override-input isonim path:../isonim``.
    isonim.url = "github:metacraft-labs/isonim/dev";
  };

  outputs =
    { self, isonim }:
    let
      # Reuse isonim's own nixpkgs + flake-utils pins so the toolchain versions
      # (nim 2.2.4, node, …) are byte-for-byte identical to isonim's dev shell.
      inherit (isonim.inputs) flake-utils nixpkgs;
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        # ``allowUnfree`` mirrors isonim's flake: isonim's dev shell pulls in
        # the (unfree) claude-agent-acp compat wrapper; we import nixpkgs the
        # same way so aggregating its build inputs here doesn't trip the
        # unfree assertion.
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          # Inherit the entire isonim toolchain. isonim-docs adds no tools of
          # its own — the SSG builds with plain ``nim c`` / ``nim js`` + node,
          # all of which isonim's shell already provides.
          #
          # The toolchain only: isonim's ``shellHook`` is dropped. ``inputsFrom``
          # would otherwise run it here, and it installs isonim's git hooks
          # (``.pre-commit-config.yaml``, ``.git/hooks``) into the git checkout
          # the shell is entered from -- isonim-docs itself, or any other
          # repository ``nix develop /path/to/isonim-docs`` is run in.
          # tests/test_dev_shell_writes_nothing_elsewhere.sh
          inputsFrom = [
            (isonim.devShells.${system}.default.overrideAttrs (_: {
              shellHook = "";
            }))
          ];

          shellHook = ''
            echo "isonim-docs dev shell — reusing isonim's toolchain (nim $(nim --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'), node $(node --version))"
          '';
        };
      }
    );
}
