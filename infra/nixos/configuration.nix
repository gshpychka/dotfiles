{
  modulesPath,
  lib,
  pkgs,
  config,
  ...
}:
let
  dataMountPoint = "/mnt/data";
  ageKeySecretName = "sops-age-key";
  dataDiskDevice = "/dev/sdb";
  dataDirectoriesToBootstrap = [ "${dataMountPoint}/var-lib" ];
  authorizedSshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG";
  gcpProjectId = "status-glibsh";
in
{
  imports = [
    "${modulesPath}/virtualisation/google-compute-image.nix"
  ];

  virtualisation.googleComputeImage.efi = true;

  system.stateVersion = "25.11";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  # configure auth declaratively here instead of having GCP handle it
  security.googleOsLogin.enable = lib.mkForce false;

  users.users.root.openssh.authorizedKeys.keys = [
    authorizedSshKey
  ];

  # persistent disk
  fileSystems.data = {
    mountPoint = dataMountPoint;
    device = dataDiskDevice;
    fsType = "ext4";
    autoFormat = true;
    neededForBoot = true;
  };

  # fetch the age key from Secret Manager and write to the persistent disk
  systemd.services.fetch-sops-age-key = {
    description = "Fetch SOPS age key from GCP Secret Manager";
    wantedBy = [ "multi-user.target" ];
    requires = [ "network-online.target" ];
    after = [ "network-online.target" ];

    unitConfig.RequiresMountsFor = dataMountPoint;

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      KEY_FILE="${config.fileSystems.data.mountPoint}/${ageKeySecretName}.txt"

      echo "Fetching SOPS age key '${ageKeySecretName}' from Secret Manager..."
      ${pkgs.google-cloud-sdk}/bin/gcloud secrets versions access latest \
        --secret=${ageKeySecretName} \
        --project=${gcpProjectId} \
        --format='get(payload.data)' \
        --out-file="$KEY_FILE"

      chmod 600 "$KEY_FILE"
      echo "SOPS age key successfully written to $KEY_FILE"
    '';
  };

  # create directories on the persistent disk
  systemd.tmpfiles.rules = lib.forEach dataDirectoriesToBootstrap (dir: "d '${dir}' 0755 root root");
}
