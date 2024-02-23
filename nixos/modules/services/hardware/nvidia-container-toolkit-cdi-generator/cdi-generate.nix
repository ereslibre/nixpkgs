{
  addDriverRunpath,
  glibc,
  jq,
  lib,
  nvidia-container-toolkit,
  nvidia-driver,
  runtimeShell,
  writeScriptBin,
  mount-nvidia-binaries,
  mount-nvidia-docker-1-directories,
}:
let
  mountOptions = { options = ["ro" "nosuid" "nodev" "bind"]; };
  mounts = [
    # FIXME: use closureinfo
    {
      hostPath = addDriverRunpath.driverLink;
      containerPath = addDriverRunpath.driverLink;
    }
    { hostPath = "${lib.getLib glibc}/lib";
      containerPath = "${lib.getLib glibc}/lib"; }
    { hostPath = "${lib.getLib glibc}/lib64";
      containerPath = "${lib.getLib glibc}/lib64"; }
  ] ++ (
    lib.optionals mount-nvidia-binaries [
      { hostPath = lib.getExe' nvidia-driver "nvidia-smi";
        containerPath = "/usr/bin/nvidia-smi"; }
      { hostPath = lib.getExe' nvidia-driver "nvidia-cuda-mps-control";
        containerPath = "/usr/bin/nvidia-cuda-mps-control"; }
      { hostPath = lib.getExe' nvidia-driver "nvidia-cuda-mps-server";
        containerPath = "/usr/bin/nvidia-cuda-mps-server"; }
      { hostPath = lib.getExe' nvidia-driver "nvidia-debugdump";
        containerPath = "/usr/bin/nvidia-debugdump"; }
      { hostPath = lib.getExe' nvidia-driver "nvidia-powerd";
        containerPath = "/usr/bin/nvidia-powerd"; }
      { hostPath = lib.getExe' nvidia-container-toolkit "nvidia-ctk";
        containerPath = "/usr/bin/nvidia-ctk"; }
    ]
  ) ++ (
    # nvidia-docker 1.0 uses /usr/local/nvidia/lib{,64}
    #   e.g.
    #     - https://gitlab.com/nvidia/container-images/cuda/-/blob/e3ff10eab3a1424fe394899df0e0f8ca5a410f0f/dist/12.3.1/ubi9/base/Dockerfile#L44
    #     - https://github.com/NVIDIA/nvidia-docker/blob/01d2c9436620d7dde4672e414698afe6da4a282f/src/nvidia/volumes.go#L104-L173
    lib.optionals mount-nvidia-docker-1-directories [
      { hostPath = "${lib.getLib nvidia-driver}/lib";
        containerPath = "/usr/local/nvidia/lib"; }
      { hostPath = "${lib.getLib nvidia-driver}/lib";
        containerPath = "/usr/local/nvidia/lib64"; }
    ]);
  jqAddMountExpression = ".containerEdits.mounts[.containerEdits.mounts | length] |= . +";
  mountsToJq = lib.concatMap
    (mount:
      ["${lib.getExe jq} '${jqAddMountExpression} ${builtins.toJSON (mount // mountOptions)}'"])
    mounts;
in
writeScriptBin "nvidia-cdi-generator"
''
#! ${runtimeShell}

function cdiGenerate {
  ${lib.getExe' nvidia-container-toolkit "nvidia-ctk"} cdi generate \
    --format json \
    --ldconfig-path ${lib.getExe' glibc "ldconfig"} \
    --library-search-path ${lib.getLib nvidia-driver}/lib \
    --nvidia-ctk-path ${lib.getExe' nvidia-container-toolkit "nvidia-ctk"}
}

cdiGenerate | \
  ${lib.concatStringsSep " | " mountsToJq} > $RUNTIME_DIRECTORY/nvidia-container-toolkit.json
''
