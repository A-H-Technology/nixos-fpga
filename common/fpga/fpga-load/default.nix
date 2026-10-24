{
  stdenv,
  kernel,
  kernelModuleMakeFlags,
}:
stdenv.mkDerivation {
  pname = "fpga-load";
  version = "${kernel.version}-1";
  src = ./.;

  nativeBuildInputs = kernel.moduleBuildDependencies;
  makeFlags =
    kernelModuleMakeFlags
    ++ [
      "-C"
      "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "M=$(PWD)"
    ];
  buildFlags = ["modules"];
  installFlags = ["INSTALL_MOD_PATH=${placeholder "out"}"];
  installTargets = ["modules_install"];
}
