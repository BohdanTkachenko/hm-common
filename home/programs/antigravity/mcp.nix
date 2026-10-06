{
  config,
  lib,
  ...
}:
{
  # Antigravity (Gemini) can't expand env-var references in its MCP config, so
  # the real secret values must be baked into the rendered file. That rendering
  # (with a secret manager) belongs in the consumer's private config, which sets
  # this option to the rendered config's path. Null on a generic standalone build → no Gemini MCP config.
  options.my.antigravity.mcpConfigFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "Path to the rendered Gemini/Antigravity MCP config (with secrets baked in).";
  };

  config = lib.mkIf (config.my.antigravity.mcpConfigFile != null) {
    anti-drift.files.".gemini/config/mcp_config.json" = {
      source = config.my.antigravity.mcpConfigFile;
      json = true;
    };
  };
}
