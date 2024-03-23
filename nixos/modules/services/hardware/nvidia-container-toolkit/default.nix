{ config, lib, pkgs, ... }:

{

  options = let
    mountType = {
      options = {
        hostPath = lib.mkOption {
          type = lib.types.str;
          description = lib.mdDoc "Host path.";
        };
        containerPath = lib.mkOption {
          type = lib.types.str;
          description = lib.mdDoc "Container path.";
        };
        mountOptions = lib.mkOption {
          default = [ "ro" "nosuid" "nodev" "bind" ];
          type = lib.types.listOf lib.types.str;
          description = lib.mdDoc "Mount options.";
        };
      };
    };
  in {

    hardware.nvidia-container-toolkit = {
      enable = lib.mkOption {
        default = false;
        type = lib.types.bool;
        description = lib.mdDoc ''
          Enable dynamic CDI configuration for NVidia devices by running
          nvidia-container-toolkit on boot.
        '';
      };

      extra-mounts = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule mountType);
        default = [];
        description = lib.mdDoc "Extra mounts to be added to every container under this CDI profile.";
      };

      mount-nvidia-executables = lib.mkOption {
        default = true;
        type = lib.types.bool;
        description = lib.mdDoc ''
          Mount executables nvidia-smi, nvidia-cuda-mps-control, nvidia-cuda-mps-server,
          nvidia-debugdump, nvidia-powerd and nvidia-ctk on containers.
        '';
      };

      mount-nvidia-docker-1-directories = lib.mkOption {
        default = true;
        type = lib.types.bool;
        description = lib.mdDoc ''
          Mount nvidia-docker-1 directories on containers: /usr/local/nvidia/lib and
          /usr/local/nvidia/lib64.
        '';
      };

    };

  };

  config = {

    systemd.services.nvidia-container-toolkit-cdi-generator = lib.mkIf config.hardware.nvidia-container-toolkit.enable {
      description = "Container Device Interface (CDI) for Nvidia generator";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-udev-settle.service" ];
      serviceConfig = {
        RuntimeDirectory = "cdi";
        RemainAfterExit = true;
        ExecStart =
          let
            script = pkgs.callPackage ./cdi-generate.nix {
              inherit (config.hardware.nvidia-container-toolkit) extra-mounts;
              nvidia-driver = config.hardware.nvidia.package;
            };
          in
          lib.getExe script;
        Type = "oneshot";
      };
    };

  };

}
