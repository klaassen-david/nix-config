# Git access for implementer hosts (decisions/implementer-host.md)
# ================================================================
# dk can read ~/.ssh/id_priv, so a plain key on this account is the whole fleet.
# An implementer's key therefore gets a forced command: git fetch and push, on the
# repos allowlisted below, nothing else (`restrict`: no pty, forwarding or rc).
#
# The push policy is a pre-receive hook handed to this one receive-pack through
# `-c core.hooksPath`. It is deliberately NOT installed in the repos:
#   - a hook in olympus:code/orchestrator refusing `main` would also refuse the
#     release pipeline's own `git push origin main`, which arrives as dk with id_priv
#     (orch-release promote_push);
#   - nothing is written to a live repo's hooks or config, so other writers do not
#     see it. The orchestrator's merges on hestia are local `update-ref`s with
#     hooks off, and they are untouched either way.
# It also means the repos' own hooks do not run for these pushes.
#
# Pushes may only create or move `refs/heads/implementer/*`. "Anything but main"
# is not enough on hestia: the orchestrator owns `refs/heads/agents/*`, including
# the stewards' live branches, and its gc deletes those by tip; `refs/orch/*` holds
# integration and measurement state. No tags, no notes.
#
# Inert until common/keys/id_<host>.pub exists for a host in ../../implementers.nix:
# without a key this module defines nothing.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  keyFiles = lib.filter builtins.pathExists (
    map (name: ../../keys + "/id_${name}.pub") (lib.attrNames (import ../../implementers.nix))
  );

  # relative to dk's home; an absolute path under it is normalised first
  repos =
    {
      olympus = [ "code/orchestrator" ];
      hestia = [
        "work/orchestrator/repo"
        "work/ostt3/repo"
      ];
    }
    .${config.host.hostName};

  hooks = pkgs.writeTextFile {
    name = "implementer-git-hooks";
    destination = "/pre-receive";
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      refused=0
      while read -r _ _ ref; do
        case "$ref" in
          refs/heads/implementer/*) ;;
          *)
            echo "implementer-git: refusing $ref: push to refs/heads/implementer/* only" >&2
            refused=1
            ;;
        esac
      done
      exit "$refused"
    '';
  };

  forced = pkgs.writeShellScript "implementer-git" ''
    set -euo pipefail
    refuse() {
      echo "implementer-git: $1" >&2
      exit 1
    }

    pattern="^git-(upload-pack|receive-pack) '([^']+)'$"
    [[ "''${SSH_ORIGINAL_COMMAND:-}" =~ $pattern ]] || refuse "git fetch and push only"
    verb=''${BASH_REMATCH[1]}
    repo=''${BASH_REMATCH[2]}
    repo=''${repo#"$HOME"/}
    case "$repo" in
      ${lib.concatStringsSep "|" repos}) ;;
      *) refuse "$repo is not on the allowlist" ;;
    esac
    cd "$HOME"

    # sshd sessions sit outside the coordinator's slices: stay out of the way of builds
    low=(${pkgs.coreutils}/bin/nice -n 19 ${pkgs.util-linux}/bin/ionice -c 3)
    git=${lib.getExe pkgs.git}
    case "$verb" in
      upload-pack) exec "''${low[@]}" "$git" upload-pack "$repo" ;;
      # no autogc: a gc in a live repo is the orchestrator's to schedule
      receive-pack) exec "''${low[@]}" "$git" -c core.hooksPath=${hooks} -c receive.autogc=false receive-pack "$repo" ;;
    esac
  '';
in
lib.mkIf (keyFiles != [ ]) {
  users.users.dk.openssh.authorizedKeys.keys = map (
    keyFile: ''restrict,command="${forced}" ${lib.fileContents keyFile}''
  ) keyFiles;
}
