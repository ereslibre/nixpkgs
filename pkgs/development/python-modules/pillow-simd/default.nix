{
  lib,
  stdenv,
  buildPythonPackage,
  fetchFromGitHub,
  isPyPy,
  isPy3k,
  olefile,
  freetype,
  libjpeg,
  zlib,
  libtiff,
  libwebp,
  libxcrypt,
  tcl,
  lcms2,
  libxcb,
  tk,
  libX11,
  openjpeg,
  libimagequant,
  pyroma,
  numpy,
  defusedxml,
  pytestCheckHook,
  setuptools,
}@args:

import ../pillow/generic.nix (
  rec {
    pname = "Pillow-SIMD";
    # check for release version on https://pypi.org/project/Pillow-SIMD/#history
    # does not match the latest pillow release version!
    version = "9.0.0.post1";
    format = "setuptools";

    disabled = !isPy3k;

    src = fetchFromGitHub {
      owner = "uploadcare";
      repo = "pillow-simd";
      rev = "v${version}";
      hash = "sha256-qTZYhgHjVMXqoYl3mG1xVrFaWrPidSY8HlyFQizV27Y=";
    };

    meta = with lib; {
      broken =
        (stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64) || stdenv.hostPlatform.isDarwin;
      homepage = "https://python-pillow.github.io/pillow-perf/";
      description = "Friendly PIL fork - SIMD version";
      longDescription = ''
        Pillow-SIMD is "following" Pillow. Pillow-SIMD versions are 100% compatible drop-in replacements for Pillow of the same version.

        SIMD stands for "single instruction, multiple data" and its essence is in performing the same operation on multiple data points simultaneously by using multiple processing elements. Common CPU SIMD instruction sets are MMX, SSE-SSE4, AVX, AVX2, AVX512, NEON.

        Currently, Pillow-SIMD can be compiled with SSE4 (default) or AVX2 support.
      '';
      license = licenses.hpnd;
      maintainers = [ ];
    };
  }
  // args
)
