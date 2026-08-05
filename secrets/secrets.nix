# secrets.nix — agenix key declarations
#
# Each entry maps a secret file to the set of age public keys that can decrypt it.
# Add the host SSH public key (age-keygen -y /etc/ssh/ssh_host_ed25519_key) for
# each Pi so that deploy-rs can activate secrets without your personal key present.
#
# Usage:
#   # Edit/create an encrypted secret (runs in your local shell):
#   nix run .#agenix -- -e secrets/wireless.env.age
#
#   # The plaintext contents of wireless.env should be:
#   #   SSID=YourNetworkName
#   #   PSK=YourWifiPassword

let
  # Your personal SSH public keys (age recipients).
  # These are the keys from your machines that you use to decrypt secrets locally.
  rjpc = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJNo24kFmOht87GEejqv4uWquucROWu4Fw8v8JaElomJ" # rjpc@zits
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRD43YeRHIv/H4S8Hj9bw0uoGRo0W9mCMMOZvtHPBLi" # rjpc@air
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMM2gabh4hExixOKrLfrG029dA5TiKyr4SZB5BsJB65o" # rjpc@YF21
  ];

  # Per-host SSH host keys (used by agenix on the remote to decrypt at activation time).
  # To obtain: ssh-keyscan <hostname> | grep ed25519
  # Populate these once your Pis are first booted (or from a known-good deployment).
  nemo      = "ssh-ed25519 AAAA<replace-with-nemo-host-key>";
  zerocool  = "ssh-ed25519 AAAA<replace-with-zerocool-host-key>";
  nintendo  = "ssh-ed25519 AAAA<replace-with-nintendo-host-key>";
  madison   = "ssh-ed25519 AAAA<replace-with-madison-host-key>";

  allHosts = [ nemo zerocool nintendo madison ];
in
{
  "wireless.env.age".publicKeys = rjpc ++ allHosts;
}
