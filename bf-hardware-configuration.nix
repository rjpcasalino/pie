{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usbhid" "sd_mod" "rtsx_pci_sdmmc" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/ed45d893-bc39-487b-9c37-b958db4839d6";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/EA2C-372D";
      fsType = "vfat";
    };
  
  fileSystems."/mnt/sdb1" =
    { device = "/dev/disk/by-uuid/5C67-9F0C";
      fsType = "exfat";
    };
  
  fileSystems."/mnt/sdc1" =
    { device = "/dev/disk/by-uuid/7BBF-B8D5";
      fsType = "exfat";
    };
  
  fileSystems."/mnt/sdd1" =
    { device = "/dev/disk/by-uuid/e78fd6ed-6186-408a-bf01-47f4f432e0ea";
      fsType = "ext4";
    };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
