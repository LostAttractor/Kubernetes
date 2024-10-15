{
  description = "ChaosAttractor's NixNAS Server Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
    homelab.url = "github:lostattractor/homelab";
    homelab.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, deploy-rs, ... }@inputs:
    let
      clusterInit = "node0";
    in
    rec {
      # Node@NUC9.home.lostattractor.net
      nixosConfigurations."node@nuc9.home.lostattractor.net" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs clusterInit;
          role = "server";
        };
        modules = [
          ./configuration
          (inputs.homelab + "/hardware/kvm/proxmox.nix")
          inputs.sops-nix.nixosModules.sops
          { networking.hostName = "node0"; }
        ];
      };
      # Node@Harvester0.home.lostattractor.net
      nixosConfigurations."node@harvester0.home.lostattractor.net" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs clusterInit;
        };
        modules = [
          ./configuration
          (inputs.homelab + "/hardware/kvm/kubevirt.nix")
          inputs.sops-nix.nixosModules.sops
          { networking.hostName = "node1"; }
        ];
      };
      # Node@PVE2.home.lostattractor.net
      nixosConfigurations."node@pve2.home.lostattractor.net" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs clusterInit;
        };
        modules = [
          ./configuration
          (inputs.homelab + "/hardware/kvm/proxmox.nix")
          inputs.sops-nix.nixosModules.sops
          { networking.hostName = "node2"; }
        ];
      };
      nixosConfigurations."node@ec2.lostattractor.net" = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {
          inherit inputs clusterInit;
          exitNode = true;
        };
        modules = [
          ./configuration
          (inputs.homelab + "/hardware/ec2")
          inputs.sops-nix.nixosModules.sops
          { networking.hostName = "ec2"; }
          { networking.nameservers = [ "1.1.1.1" ]; }
          { nixpkgs.buildPlatform.system = "x86_64-linux"; }
        ];
      };
      nixosConfigurations."node@lightsail.lostattractor.net" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs clusterInit;
          exitNode = true;
        };
        modules = [
          ./configuration
          (inputs.homelab + "/hardware/ec2")
          ({ lib, ... }: { boot.loader.grub.device = lib.mkForce "/dev/nvme0n1"; })
          inputs.sops-nix.nixosModules.sops
          { networking.hostName = "lightsail"; }
          { networking.nameservers = [ "1.1.1.1" ]; }
        ];
      };

      # Deploy-RS Configuration
      deploy = {
        sshUser = "root";
        magicRollback = false;

        nodes."node@nuc9.home.lostattractor.net" = {
          hostname = "node0.home.lostattractor.net";
          profiles.system.path =
            deploy-rs.lib.x86_64-linux.activate.nixos
              nixosConfigurations."node@nuc9.home.lostattractor.net";
        };
        nodes."node@harvester0.home.lostattractor.net" = {
          hostname = "node1.home.lostattractor.net";
          profiles.system.path =
            deploy-rs.lib.x86_64-linux.activate.nixos
              nixosConfigurations."node@harvester0.home.lostattractor.net";
        };
        nodes."node@pve2.home.lostattractor.net" = {
          hostname = "node2.home.lostattractor.net";
          profiles.system.path =
            deploy-rs.lib.x86_64-linux.activate.nixos
              nixosConfigurations."node@pve2.home.lostattractor.net";
        };
        nodes."node@ec2.lostattractor.net" = {
          hostname = "ec2.lostattractor.net";
          profiles.system.path =
            deploy-rs.lib.aarch64-linux.activate.nixos
              nixosConfigurations."node@ec2.lostattractor.net";
        };
        nodes."node@lightsail.lostattractor.net" = {
          hostname = "lightsail.lostattractor.net";
          profiles.system.path =
            deploy-rs.lib.x86_64-linux.activate.nixos
              nixosConfigurations."node@lightsail.lostattractor.net";
        };
      };

      # This is highly advised, and will prevent many possible mistakes
      checks = builtins.mapAttrs (_system: deployLib: deployLib.deployChecks deploy) deploy-rs.lib;

      hydraJobs = with nixpkgs.lib; {
        nixosConfigurations = mapAttrs' (
          name: config: nameValuePair name config.config.system.build.toplevel
        ) nixosConfigurations;
        VMA = mapAttrs' (
          name: config: nameValuePair name config.config.system.build.VMA
        ) nixosConfigurations;
        kubevirtImage = mapAttrs' (
          name: config: nameValuePair name config.config.system.build.kubevirtImage
        ) nixosConfigurations;
      };
    };
}
