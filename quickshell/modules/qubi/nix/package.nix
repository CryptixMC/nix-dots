{
  lib,
  python3Packages,
  sqlite,
}:

python3Packages.buildPythonApplication {
  pname = "qubi";
  version = "0.1.0";
  pyproject = true;

  # Only what the Python build reads, so editing QML or docs in the same
  # tree does not rebuild (and restart) the engine.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../pyproject.toml
      ../README.md
      ../python
    ];
  };

  build-system = [ python3Packages.setuptools ];

  dependencies = with python3Packages; [
    websockets
    pyyaml
  ];

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];

  # sqlite3: the engine reads goose's sessions.db through the CLI. `goose`,
  # `ollama` and `quickshell` are deliberately NOT pinned here -- they must
  # be the ones the user actually runs, so they come from the ambient PATH.
  makeWrapperArgs = [
    "--suffix"
    "PATH"
    ":"
    (lib.makeBinPath [ sqlite ])
  ];

  pythonImportsCheck = [ "qubi" ];

  meta = {
    description = "Persistent multi-tier router in front of `goose acp`";
    mainProgram = "qubi-engine";
    platforms = lib.platforms.linux;
  };
}
