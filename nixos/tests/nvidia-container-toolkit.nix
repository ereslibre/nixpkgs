import ./make-test-python.nix (
  { pkgs, lib, system, ... }: let
      unfreePkgs = import ../.. { inherit system; config.allowUnfree = true; };
      testContainerImage = let
        testCDIScript = pkgs.writeShellScriptBin "test-cdi" ''
            set -e

            # Check referential integrity
            check_referential_integrity() {
              echo "Checking referential integrity for $1"
              ${pkgs.coreutils}/bin/ls -la "$1"

              /usr/bin/nvidia-smi

              ${pkgs.glibc.bin}/bin/ldd "$1" | \
                ${pkgs.gnugrep}/bin/grep '=>' | \
                ${pkgs.gnused}/bin/sed "s/.* => //" | \
                ${pkgs.gnused}/bin/sed "s/ (.*//" | \
                ${pkgs.findutils}/bin/xargs -I{} ${pkgs.file}/bin/file "{}"
            }

            export -f check_referential_integrity

            ${pkgs.findutils}/bin/find /usr/bin -type f | \
              ${pkgs.findutils}/bin/xargs -I{} ${pkgs.runtimeShell} -c 'check_referential_integrity "{}"'

            exit 0
          '';
      in pkgs.dockerTools.buildImage {
        name = "cdi-test";
        tag = "latest";
        config = {
          Cmd = [ "${testCDIScript}/bin/test-cdi" ];
        };
        copyToRoot = (with pkgs; [
          unfreePkgs.linuxPackages.nvidia_x11
        ]) ++ (with pkgs.dockerTools; [
          usrBinEnv
          binSh
        ]);
      };
    in {
    name = "nvidia-container-toolkit";
    meta = with lib.maintainers; {
      maintainers = [ ereslibre ];
    };
    nodes = {
      no-nvidia-gpus = {
        environment.systemPackages = with pkgs; [ jq ];
        hardware.nvidia-container-toolkit.enable = true;
        nixpkgs.config.allowUnfree = true;
      };
      nvidia-one-gpu = { pkgs, ... }: let
        emptyCDISpec = ''
          #! ${pkgs.runtimeShell}
          cat <<CDI_DOCUMENT
            {
              "cdiVersion": "0.5.0",
              "kind": "nvidia.com/gpu",
              "devices": [
                {
                  "name": "all",
                  "containerEdits": {
                    "deviceNodes": [
                      {
                        "path": "/dev/urandom"
                      }
                    ],
                    "hooks": [],
                    "mounts": []
                  }
                }
              ],
              "containerEdits": {
                "deviceNodes": [],
                "hooks": [],
                "mounts": []
              }
            }
          CDI_DOCUMENT
        '';
      in {
        virtualisation.diskSize = 10240;
        environment.systemPackages = with pkgs; [ jq podman ];
        hardware = {
          nvidia-container-toolkit = {
            enable = true;
            package = pkgs.stdenv.mkDerivation {
              name = "nvidia-ctk-dummy";
              version = "1.0.0";
              phases = "installPhase";
              installPhase = ''
              mkdir -p $out/bin
              cat <<EOF > $out/bin/nvidia-ctk
                ${emptyCDISpec}
              EOF
              chmod +x $out/bin/nvidia-ctk
            '';
            };
          };
          opengl.enable = true;
        };
        nixpkgs.config.allowUnfree = true;
        services.xserver.videoDrivers = ["nvidia"];
        virtualisation.containers.enable = true;
      };
    };
    testScript = ''
      start_all()

      with subtest("Generate the CDI spec (empty) for a machine with no Nvidia GPU"):
        no_nvidia_gpus.wait_for_unit("nvidia-container-toolkit-cdi-generator.service")
        no_nvidia_gpus.succeed("cat /var/run/cdi/nvidia-container-toolkit.json | jq")

      with subtest("Generate the CDI spec for a machine with an Nvidia GPU"):
        nvidia_one_gpu.wait_for_unit("nvidia-container-toolkit-cdi-generator.service")
        nvidia_one_gpu.succeed("cat /var/run/cdi/nvidia-container-toolkit.json | jq")
        nvidia_one_gpu.succeed("podman load < ${testContainerImage}")
        print(nvidia_one_gpu.succeed("podman run --pull=never --device=nvidia.com/gpu=all cdi-test:latest"))
    '';
  }
)
