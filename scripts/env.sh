# Source from repository root: source scripts/env.sh
# Prefer a project-local OSS CAD Suite; otherwise use tools on PATH.
if [ -d "$PWD/work/tools/oss-cad-suite/bin" ]; then
    export PATH="$PWD/work/tools/oss-cad-suite/bin:$PATH"
    export XDG_CONFIG_HOME="$PWD/work/config"
    export XDG_DATA_HOME="$PWD/work/share"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
fi
