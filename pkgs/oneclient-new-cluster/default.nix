{ writeShellApplication, sqlite }:
writeShellApplication {
  name = "oneclient-new-cluster";
  runtimeInputs = [ sqlite ];
  text = builtins.readFile ./oneclient-new-cluster.sh;
}
