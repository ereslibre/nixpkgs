{
  glibc,
  jq,
  lib,
  mounts,
  extra-mounts,
  nvidia-container-toolkit,
  nvidia-driver,
  runtimeShell,
  writeScriptBin,
}: let
  mkMount = {hostPath, containerPath, mountOptions ? null}: {
    inherit hostPath containerPath;
    options = (if mountOptions != null then mountOptions else [ "ro" "nosuid" "nodev" "bind" ]);
  };
  jqAddMountExpression = ".containerEdits.mounts[.containerEdits.mounts | length] |= . +";
  mountsToJq = mounts: (lib.concatMap
    (mount:
      ["${lib.getExe jq} '${jqAddMountExpression} ${builtins.toJSON (mkMount mount)}'"])
    mounts);
  allMounts = (mountsToJq mounts) ++ (mountsToJq extra-mounts);
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
  ${lib.concatStringsSep " | " allMounts} > $RUNTIME_DIRECTORY/nvidia-container-toolkit.json
''
