{ config, ... }:
let
  ingress_interface = "ens5";
  shadowsocks.port = 7000;
  hysteria2 = {
    port = 7001;
    from = 10000;
    to = 32767;
  };
in
{
  # The NixOS module reads these root-only files in ExecStartPre and writes
  # the final JSON under /run/sing-box, keeping plaintext out of the Nix store.
  sops.secrets = {
    "sing-box/shadowsocks-password".restartUnits = [ "sing-box.service" ];
    "sing-box/shadowsocks-2022-password".restartUnits = [ "sing-box.service" ];
    "sing-box/vmess-uuid".restartUnits = [ "sing-box.service" ];
    "sing-box/hysteria2-password".restartUnits = [ "sing-box.service" ];
    "sing-box/cloudflare-api-token".restartUnits = [ "sing-box.service" ];
  };

  services.sing-box = {
    enable = true;
    settings = {
      log.level = "info";
      inbounds = [
        {
          type = "shadowsocks";
          listen = "::";
          listen_port = shadowsocks.port;
          method = "aes-128-gcm";
          password._secret = config.sops.secrets."sing-box/shadowsocks-password".path;
          multiplex.enabled = true;
        }
        {
          type = "shadowsocks";
          listen = "::";
          listen_port = shadowsocks.port - 1;
          method = "2022-blake3-aes-128-gcm";
          password._secret = config.sops.secrets."sing-box/shadowsocks-2022-password".path;
          multiplex.enabled = true;
        }
        {
          type = "vmess";
          listen = "::";
          listen_port = shadowsocks.port - 2;
          users = [
            {
              uuid._secret = config.sops.secrets."sing-box/vmess-uuid".path;
              alterId = 0;
            }
          ];
          multiplex.enabled = true;
        }
        {
          type = "hysteria2";
          listen = "::";
          listen_port = hysteria2.port;
          users = [ { password._secret = config.sops.secrets."sing-box/hysteria2-password".path; } ];
          tls = {
            enabled = true;
            server_name = "${config.networking.hostName}.lostattractor.net";
            alpn = [ "h3" ];
            acme = {
              domain = [
                "${config.networking.hostName}.lostattractor.net"
                "${config.networking.hostName}4.lostattractor.net"
              ];
              email = "lostattractor@gmail.com";
              dns01_challenge = {
                provider = "cloudflare";
                api_token._secret = config.sops.secrets."sing-box/cloudflare-api-token".path;
              };
            };
          };
          masquerade = {
            type = "proxy";
            url = "https://lostattractor.net";
            rewrite_host = true;
          };
        }
      ];
      outbounds = [
        {
          type = "direct";
        }
      ];
    };
  };

  systemd.services.sing-box = {
    restartIfChanged = false;
    serviceConfig.UMask = "0077";
  };

  networking.firewall.allowedTCPPorts = [
    (shadowsocks.port - 2)
    (shadowsocks.port - 1)
    shadowsocks.port
  ];
  # Hysteria port hopping is redirected to this port before input filtering.
  networking.firewall.allowedUDPPorts = [
    (shadowsocks.port - 1)
    shadowsocks.port
    hysteria2.port
  ];

  networking.nftables.tables.hysteria_porthopping = {
    family = "inet";
    content = ''
      # table inet nixos-fw {
      #   set allow_ports {
      #     type inet_service
      #     timeout 180s
      #   }

      #   chain output {
      #     type filter hook output priority filter; policy accept;
      #     ct state new meta l4proto udp update @allow_ports { udp sport }
      #   }

      #   chain input-allow {
      #     udp dport @allow_ports accept
      #   }
      # }

        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          iifname ${ingress_interface} udp dport ${toString hysteria2.from}-${toString hysteria2.to} counter redirect to :${toString hysteria2.port}
          # 只有对新连接做 DNAT, 如果不是新连接, 说明可能是本机发起的连接
          # 32768-60999 是临时端口范围
          # TODO: ct state new / ct direction ?
        }
    '';
  };
}
