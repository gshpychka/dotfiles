let
  harborUsername = "pi";
  harborSshPort = 420;
  harborHost = "harbor";
  localDomain = "lan";
in
{
  inherit harborUsername harborSshPort harborHost localDomain;
}

