{ config, clusterInit, ... }:
{
  networking.firewall.allowedTCPPorts = [
    6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
    2379 # k3s, etcd clients: required if using a "High Availability Embedded etcd" configuration
    2380 # k3s, etcd peers: required if using a "High Availability Embedded etcd" configuration
  ];
  networking.firewall.allowedUDPPorts = [
    8472 # k3s, flannel: required if using multi-node for inter-node networking
  ];

  services.k3s = {
    enable = true;
    role = "server"; # Or "agent" for worker only nodes
    tokenFile = config.sops.secrets."kubernetes/token".path;
    clusterInit = (config.networking.hostName == clusterInit);
    serverAddr =
      if config.networking.hostName == clusterInit then
        ""
      else
        "https://${clusterInit}.home.lostattractor.net:6443";
    extraFlags = toString [
      "--tls-san ${config.networking.hostName}.home.lostattractor.net"
      # "--kubelet-arg=v=4" # Optionally add additional args to k3s
    ];
  };

  sops.secrets."kubernetes/token" = { };
}
