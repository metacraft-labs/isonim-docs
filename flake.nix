{
  description = "isonim-docs — self-contained dev shell for the IsoNim-powered docs SSG";

  inputs = {
    # isonim owns the unchanged docs toolchain; the additional input is hook source only.
    # It supplies the docs toolchain
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
    standard-hook-source = {
      url = "github:metacraft-labs/devops-modules/c8ef41d446e211892fe9775182b43d5d517554ac";
      flake = false;
    };
  };

  outputs =
    inputs@{ self, isonim, ... }:
    let
      # Reuse isonim's own nixpkgs + flake-utils pins so the toolchain versions
      # (nim 2.2.4, node, …) are byte-for-byte identical to isonim's dev shell.
      inherit (isonim.inputs) flake-utils nixpkgs git-hooks;
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
        preCommit = git-hooks.lib.${system}.run {
          src = ./.;
          hooks = import "${inputs.standard-hook-source}/git-hooks/standard-hooks.nix" {
            inherit pkgs;
            lib = pkgs.lib;
            src = inputs.standard-hook-source;
          };
        };
        expectedNativeHook =
          pkgs.runCommand "docs-native-pre-commit-hook"
            {
              nativeBuildInputs = [
                pkgs.git
                preCommit.config.package
              ];
            }
            ''
              export PRE_COMMIT_HOME="$TMPDIR/docs-native-hook-cache"
              mkdir -p "$PRE_COMMIT_HOME" fixture
              cd fixture
              export GIT_CONFIG_GLOBAL="$TMPDIR/docs-native-factory-gitconfig"
              export GIT_CONFIG_NOSYSTEM=1
              : > "$GIT_CONFIG_GLOBAL"
              git init --template= >/dev/null
              if git config --get core.hooksPath; then
                echo 'Unexpected native factory hooksPath authority' >&2
                exit 1
              fi
              test "$(git rev-parse --path-format=absolute --git-path hooks)" = "$PWD/.git/hooks"
              ln -s ${preCommit.config.configFile} ${preCommit.config.configPath}
              mkdir -p "$out"
              for hook in pre-commit pre-push; do
                ${preCommit.config.package}/bin/pre-commit install -c ${preCommit.config.configPath} -t "$hook"
                install -m 0755 ".git/hooks/$hook" "$out/$hook"
              done
            '';
        # Keep upstream's generated installer verbatim, as its normal shell
        # entry does. The owning application and ownership guards remain checked.
        nativeInstallerScript = pkgs.writeShellScript "docs-generated-native-installer" preCommit.shellHook;
        hookOwnershipGuard = ./nix/hook-ownership-guard.py;
        guardedHookInstall = ''
          (
            set -eu
            _own_hook_receipt="$(${pkgs.coreutils}/bin/mktemp)"
            trap '${pkgs.coreutils}/bin/rm -f "$_own_hook_receipt"' EXIT
            ${pkgs.python3}/bin/python3 ${hookOwnershipGuard} "$_own_repo_root" ${expectedNativeHook} prepare reserved ${pkgs.git}/share/git-core/templates > "$_own_hook_receipt"
            _own_matching_repro="$(${pkgs.python3}/bin/python3 ${hookOwnershipGuard} "$_own_repo_root" ${expectedNativeHook} tool reserved ${pkgs.git}/share/git-core/templates)"
            _own_install_needed=1
            if [ -L "$_own_repo_root/${preCommit.config.configPath}" ] \
              && [ "$(${pkgs.coreutils}/bin/readlink "$_own_repo_root/${preCommit.config.configPath}")" = "${preCommit.config.configFile}" ]; then
              _own_install_needed=0
            fi
            ${pkgs.bash}/bin/bash ${nativeInstallerScript}
            if [ "$_own_install_needed" -eq 1 ]; then
              ${pkgs.python3}/bin/python3 ${hookOwnershipGuard} "$_own_repo_root" ${expectedNativeHook} native reserved ${pkgs.git}/share/git-core/templates
            fi
            "$_own_matching_repro" hooks ensure --vcs "$_own_repo_root"
            ${pkgs.python3}/bin/python3 ${hookOwnershipGuard} "$_own_repo_root" ${expectedNativeHook} after "$_own_hook_receipt" ${pkgs.git}/share/git-core/templates
          )
          _own_hook_status=$?
          if [ "$_own_hook_status" -ne 0 ]; then
            unset _own_hook_status
            exit 1
          fi
          unset _own_hook_status
        '';

        explicitHookInstaller = pkgs.writeShellApplication {
          name = "docs-install-own-hooks";
          runtimeInputs = [
            pkgs.git
            pkgs.coreutils
            pkgs.python3
            preCommit.config.package
          ];
          text = ''
            _own_repo_root="$(git rev-parse --show-toplevel)"
            test "$(sha256sum "$_own_repo_root/flake.nix" | cut -d' ' -f1)" = "${builtins.hashFile "sha256" ./flake.nix}"
            if [ -e "$_own_repo_root/${preCommit.config.configPath}" ] || [ -L "$_own_repo_root/${preCommit.config.configPath}" ]; then
              test -L "$_own_repo_root/${preCommit.config.configPath}"
              test "$(readlink "$_own_repo_root/${preCommit.config.configPath}")" = "${preCommit.config.configFile}"
            fi
            ${guardedHookInstall}
          '';
        };
      in
      {
        checks.pre-commit = preCommit;
        apps.hooks-install = {
          type = "app";
          program = "${explicitHookInstaller}/bin/docs-install-own-hooks";
        };
        devShells.default = pkgs.mkShell {
          # Preserve the complete inherited C/JS docs toolchain.
          # The additive packages below provide only the named hook checks.
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

          packages = [
            pkgs.pre-commit
            pkgs.python3
          ]
          ++ preCommit.enabledPackages;
          shellHook = ''
            echo "isonim-docs dev shell — reusing isonim's toolchain (nim $(nim --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'), node $(node --version))"
          '';
        };
      }
    );
}
