{ config, ... }:
{
  boot.supportedFilesystems = [ "nfs" ];
  services.openiscsi = {
    enable = true;
    name = "${config.networking.hostName}-initiatorhost";
  };
}
