{ pkgs, ... }:

let
  fix-audio = pkgs.writeShellScriptBin "fix-audio" ''
    # Get the default sink name
    DEFAULT_SINK=$(${pkgs.pulseaudio}/bin/pactl get-default-sink)
    echo "Current default sink: $DEFAULT_SINK"

    # Find the card name (device.name) for this sink using jq
    CARD_NAME=$(${pkgs.pulseaudio}/bin/pactl -f json list sinks | \
      ${pkgs.jq}/bin/jq -r ".[] | select(.name == \"$DEFAULT_SINK\") | .properties.\"device.name\""
    )

    if [ -z "$CARD_NAME" ] || [ "$CARD_NAME" == "null" ]; then
      echo "Could not find card name for sink $DEFAULT_SINK"
      exit 1
    fi
    echo "Found card: $CARD_NAME"

    # Find the active profile for this card
    ACTIVE_PROFILE=$(${pkgs.pulseaudio}/bin/pactl -f json list cards | \
      ${pkgs.jq}/bin/jq -r ".[] | select(.name == \"$CARD_NAME\") | .active_profile")
      
    if [ -z "$ACTIVE_PROFILE" ] || [ "$ACTIVE_PROFILE" == "null" ]; then
      echo "Could not determine active profile for card $CARD_NAME"
      exit 1
    fi
    echo "Current profile: $ACTIVE_PROFILE"
    
    echo "Resetting audio card..."
    ${pkgs.pulseaudio}/bin/pactl set-card-profile "$CARD_NAME" off
    ${pkgs.coreutils}/bin/sleep 1
    ${pkgs.pulseaudio}/bin/pactl set-card-profile "$CARD_NAME" "$ACTIVE_PROFILE"
    echo "Audio card reset complete."
  '';
in
{
  home.packages = [
    fix-audio
  ];
}
