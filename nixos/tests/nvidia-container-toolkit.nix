import ./make-test-python.nix (
  { pkgs, lib, system, ... }: let
      unfreePkgs = import ../.. { inherit system; config.allowUnfree = true; };
      testContainerImage = let
        testCDIScript = pkgs.writeShellScriptBin "test-cdi" ''
            check_file_referential_integrity() {
              echo "checking file $1 referential integrity"

              filepath="$1"
              files=$( \
                ${pkgs.glibc.bin}/bin/ldd "$filepath" | \
                ${pkgs.coreutils}/bin/tee /dev/stderr | \
                ${pkgs.gnugrep}/bin/grep '=>' | \
                ${pkgs.gnused}/bin/sed "s/.* => //" | \
                ${pkgs.gnused}/bin/sed "s/ (.*//" \
              ) || exit 1

              for file in $files; do
                echo "Checking that $file is inside the container filesystem"
                ${pkgs.file}/bin/file -E "$file" || exit 1
              done
            }

            check_directory_referential_integrity() {
              echo "checking directory $1 referential integrity"
              ${pkgs.tree}/bin/tree $1 || exit 1
              for file in $(${pkgs.findutils}/bin/find $1 -type f); do
                check_file_referential_integrity "$file" || exit 1
              done
            }

            check_directory_referential_integrity "/usr/bin"
            check_directory_referential_integrity "${pkgs.addDriverRunpath.driverLink}"
            check_directory_referential_integrity "/usr/local/nvidia"
          '';
      in pkgs.dockerTools.buildImage {
        name = "cdi-test";
        tag = "latest";
        config = {
          Cmd = [ "${testCDIScript}/bin/test-cdi" ];
          Env = [
            "LD_LIBRARY_PATH=${unfreePkgs.linuxPackages.nvidia_x11}/lib:${lib.getLib pkgs.openssl}/lib"
          ];
        };
        copyToRoot = (with pkgs; [ openssl ]) ++ (with pkgs.dockerTools; [
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
        print(nvidia_one_gpu.succeed("podman run --pull=never --device=nvidia.com/gpu=all -v /run/opengl-driver:/run/opengl-driver:ro -v ${lib.getLib pkgs.openssl}/lib:${lib.getLib pkgs.openssl}/lib:ro cdi-test:latest"))
    '';
  }
)
