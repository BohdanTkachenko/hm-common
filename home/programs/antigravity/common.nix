{ config, pkgs, ... }:
{
  imports = [ ../ai/permissions.nix ];

  anti-drift.files = {
    ".gemini/config/AGENTS.md" = {
      source = pkgs.writeText "AGENTS.md" ''
        # Global Jujutsu (jj) Guidelines
        - **Always use `--no-pager`**: Append `--no-pager` to all `jj` command invocations (e.g., `jj --no-pager status`, `jj --no-pager log`, `jj --no-pager describe`, `jj --no-pager git push`) to prevent TTY/pager hangs.
        - **Local Commands**: Execute local `jj` operations (`status`, `describe`, `bookmark`, `diff`) in standard sandboxed mode (`BypassSandbox: false`).
        - **Network Commands**: Use `BypassSandbox: true` only for commands requiring remote network access (`jj --no-pager git push` or `jj --no-pager git fetch`).
        - **Pushing Changes**: Always ensure your bookmark is updated to `@` (`jj --no-pager bookmark set main -r @`) before running `jj --no-pager git push`.
      '';
    };
    ".gemini/config/config.json" = {
      source = (pkgs.formats.json { }).generate "gemini-config.json" {
        userSettings = {
          browserJsExecutionPolicy = "BROWSER_JS_EXECUTION_POLICY_ALWAYS_ASK";
          globalPermissionGrants = {
            allow = config.lib.permissions.forAntigravity;
          };
          useAiCredits = false;
          verboseAgentChat = true;
        };
      };
      json = true;
      preserve = [ "userSettings.remoteControlHostname" ];
    };
  };
}
