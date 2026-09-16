# Nix safety invariants

- sudo NOPASSWD rules in security.sudo.extraRules match on the exact absolute store path of the command (e.g. ${pkgs.systemd}/bin/systemctl start foo.service). A PATH-resolved bare command like plain systemctl resolves to the same binary but does NOT match the rule and silently falls back to an interactive password prompt.
- Never put pkgs.sudo in a lib.makeBinPath list that gets prepended to PATH. That is the raw non-setuid store binary and it shadows /run/wrappers/bin/sudo, the real setuid wrapper, causing every sudo call in that script to fail.
- pkgs.writeShellScriptBin scripts should set an explicit PATH via lib.makeBinPath rather than relying on the inherited PATH, since they may run in restricted contexts like root systemd oneshots.
- yq reading a JSON or YAML value into a shell variable needs the -r flag, otherwise it preserves the quoted-string style tag and embeds literal quote characters in the output.
- home.activation scripts using lib.hm.dag.entryAfter with writeBoundary as the dependency do NOT run after home.file symlinks are placed. Home-manager real activation order is writeBoundary, then custom activation scripts, then linkGeneration. An activation script needing a home.file-managed path should instead depend on a direct Nix store path (e.g. via pkgs.writeText) rather than the live on-disk home.file symlink target.
