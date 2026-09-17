{ pkgs, lib, ... }:

let
  # Sibling to goose.nix, not folded into it or into ai-workstation.nix —
  # this is audio I/O, not GPU/model routing, and stays independently
  # useful even if the chat overlay's voice UI (VoiceSession.qml) changes
  # shape later. Push-to-talk only (record → transcribe once), not
  # continuous streaming — matches the plan's own caution to verify the
  # simpler shape first.
  whisperModelDir = "$HOME/.local/share/whisper-models";
  whisperModel = "base.en";
  whisperModelPath = "${whisperModelDir}/ggml-${whisperModel}.bin";

  # rhasspy/piper-voices on HuggingFace — lessac/medium is a standard,
  # good-quality US English voice. No downloader binary ships with piper
  # itself (unlike whisper-cpp's own whisper-cpp-download-ggml-model), so
  # this fetches the .onnx + its .onnx.json config directly; URL pattern
  # confirmed live (a HEAD request resolved, not guessed from docs).
  piperVoiceDir = "$HOME/.local/share/piper-voices";
  piperVoiceName = "en_US-lessac-medium";
  piperOnnxPath = "${piperVoiceDir}/${piperVoiceName}.onnx";
  piperConfigPath = "${piperVoiceDir}/${piperVoiceName}.onnx.json";
  piperBaseUrl = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium";

  # Downloads the whisper model on first real use (not at build/activation
  # time — this is a ~140MB network fetch, not something to force on
  # every home-manager switch) then transcribes the given WAV file to
  # plain text on stdout. Model presence is checked by the caller
  # (VoiceSession.qml) via a separate readiness probe before recording
  # even starts, so the download latency is visible to the user up front
  # rather than silently eating the first push-to-talk attempt.
  voiceTranscribe = pkgs.writeShellScriptBin "voice-transcribe" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.whisper-cpp
        pkgs.coreutils
      ]
    }:$PATH

    WAVFILE="''${1:?usage: voice-transcribe WAVFILE}"
    mkdir -p ${whisperModelDir}
    if [ ! -f ${whisperModelPath} ]; then
      echo "[voice-transcribe] downloading whisper model (${whisperModel}, first use only)…" >&2
      whisper-cpp-download-ggml-model ${whisperModel} ${whisperModelDir} >&2
    fi

    OUT=$(mktemp)
    whisper-cli -m ${whisperModelPath} -f "$WAVFILE" -nt -otxt -of "$OUT" >&2
    cat "$OUT.txt"
    rm -f "$OUT.txt" "$OUT"
  '';

  # Reads text from stdin (piper's own default input, matches how the
  # caller will pipe an assistant reply in via Process.write() rather
  # than an argv element — avoids argv length limits and shell-quoting
  # concerns for arbitrarily long chat replies), synthesizes it, and
  # plays it back immediately via pw-play (already present — same
  # PipeWire install pw-record already depends on).
  voiceSpeak = pkgs.writeShellScriptBin "voice-speak" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.piper-tts
        pkgs.pipewire
        pkgs.curl
        pkgs.coreutils
      ]
    }:$PATH

    mkdir -p ${piperVoiceDir}
    if [ ! -f ${piperOnnxPath} ]; then
      echo "[voice-speak] downloading piper voice (${piperVoiceName}, first use only)…" >&2
      curl -sL -o ${piperOnnxPath} "${piperBaseUrl}/${piperVoiceName}.onnx"
      curl -sL -o ${piperConfigPath} "${piperBaseUrl}/${piperVoiceName}.onnx.json"
    fi

    TMPWAV=$(mktemp --suffix=.wav)
    piper -m ${piperOnnxPath} -c ${piperConfigPath} -f "$TMPWAV"
    pw-play "$TMPWAV"
    rm -f "$TMPWAV"
  '';

  # Cheap readiness probe for the UI to check before starting a
  # recording, so "model not downloaded yet" shows as a clear message
  # instead of a silent multi-second stall on the first press.
  voiceModelsReady = pkgs.writeShellScriptBin "voice-models-ready" ''
    set -uo pipefail
    [ -f ${whisperModelPath} ] && [ -f ${piperOnnxPath} ]
  '';
in
{
  home.packages = [
    pkgs.whisper-cpp
    pkgs.piper-tts
    voiceTranscribe
    voiceSpeak
    voiceModelsReady
  ];
}
