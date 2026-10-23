#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT_DIRECTORY="$REPO_ROOT/dist"
INSTANCE_ARCHIVE=""
MANAGEMENT_CODE=""
ARTIFACT_SUFFIX=""
FORCE=0

usage() {
  echo "Usage: $0 [--output DIRECTORY] [--instance-archive FILE] [--management-code CODE] [--artifact-suffix NAME] [--force]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      OUTPUT_DIRECTORY=$2
      shift 2
      ;;
    --instance-archive)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      INSTANCE_ARCHIVE=$2
      shift 2
      ;;
    --management-code)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      MANAGEMENT_CODE=$2
      shift 2
      ;;
    --artifact-suffix)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      ARTIFACT_SUFFIX=$2
      shift 2
      ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [ -n "$MANAGEMENT_CODE" ]; then
  case "$MANAGEMENT_CODE" in
    ??????) ;;
    *) echo "Management code must contain exactly six digits." >&2; exit 2 ;;
  esac
  case "$MANAGEMENT_CODE" in
    *[!0-9]*) echo "Management code must contain exactly six digits." >&2; exit 2 ;;
  esac
fi

if [ -n "$ARTIFACT_SUFFIX" ]; then
  case "$ARTIFACT_SUFFIX" in *[!a-z0-9-]*) echo "Invalid artifact suffix." >&2; exit 2 ;; esac
fi

if [ -n "$INSTANCE_ARCHIVE" ]; then
  [ -f "$INSTANCE_ARCHIVE" ] || { echo "Instance archive not found: $INSTANCE_ARCHIVE" >&2; exit 2; }
  case "$INSTANCE_ARCHIVE" in *.wakecanvas-instance) ;; *) echo "Instance archive must end in .wakecanvas-instance" >&2; exit 2 ;; esac
  INSTANCE_ARCHIVE=$(CDPATH= cd -- "$(dirname -- "$INSTANCE_ARCHIVE")" && pwd)/$(basename -- "$INSTANCE_ARCHIVE")
  [ -n "$ARTIFACT_SUFFIX" ] || ARTIFACT_SUFFIX=demo
fi

case "$(uname -s)" in
  Linux) ;;
  *) echo "Linux releases must be built on Linux." >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) TARGET=linux-x64 ;;
  aarch64|arm64) TARGET=linux-arm64 ;;
  *) echo "Unsupported Linux architecture: $(uname -m)" >&2; exit 1 ;;
esac

VERSION=$(sed -n 's/.*version: "\([^"]*\)".*/\1/p' "$REPO_ROOT/platform/mix.exs" | head -n 1)
[ -n "$VERSION" ] || { echo "Could not read the platform version." >&2; exit 1; }

mkdir -p "$REPO_ROOT/.tmp" "$OUTPUT_DIRECTORY"
STAGING_ROOT=$(mktemp -d "$REPO_ROOT/.tmp/linux-release.XXXXXX")
BUNDLE_ROOT="$STAGING_ROOT/WakeCanvas"
if [ -n "$ARTIFACT_SUFFIX" ]; then SUFFIX="-$ARTIFACT_SUFFIX"; else SUFFIX=""; fi
ARCHIVE_PATH="$OUTPUT_DIRECTORY/wakecanvas-$VERSION-$TARGET$SUFFIX.tar.gz"

cleanup() {
  case "$STAGING_ROOT" in
    "$REPO_ROOT/.tmp/"linux-release.*) rm -rf -- "$STAGING_ROOT" ;;
    *) echo "Refusing unsafe staging cleanup: $STAGING_ROOT" >&2 ;;
  esac
}

shutdown() {
  trap - EXIT INT TERM
  cleanup
  exit 130
}

trap cleanup EXIT
trap shutdown INT TERM

if [ -e "$ARCHIVE_PATH" ] && [ "$FORCE" -ne 1 ]; then
  echo "Release archive already exists: $ARCHIVE_PATH (use --force to replace it)" >&2
  exit 1
fi

export MIX_ENV=prod

(
  cd "$REPO_ROOT/experiences/living_gallery"
  npm ci --ignore-scripts
  mix deps.get --only prod
  mix assets.setup
  mix assets.deploy
)

if [ -n "$INSTANCE_ARCHIVE" ]; then
  mkdir -p "$BUNDLE_ROOT/seeds"
  cp "$INSTANCE_ARCHIVE" "$BUNDLE_ROOT/seeds/"
fi

if [ -n "$MANAGEMENT_CODE" ]; then
  mkdir -p "$BUNDLE_ROOT/data/config"
  printf '%s\n' "$MANAGEMENT_CODE" > "$BUNDLE_ROOT/data/config/management_code"
  chmod 0600 "$BUNDLE_ROOT/data/config/management_code"
fi

(
  cd "$REPO_ROOT/platform"
  mix deps.get --only prod
  mix assets.setup
  mix assets.deploy
  mix release wake_canvas --overwrite
)

mkdir -p "$BUNDLE_ROOT" "$BUNDLE_ROOT/packages" "$BUNDLE_ROOT/admin-tools"
cp -a "$REPO_ROOT/platform/_build/prod/rel/wake_canvas/." "$BUNDLE_ROOT/"
for script in start-wakecanvas.sh stop-wakecanvas.sh start-kiosk-mode.sh open-management.sh; do
  install -m 0755 "$REPO_ROOT/packaging/linux/$script" "$BUNDLE_ROOT/$script"
done
for script in initialize-wakecanvas.sh run-wakecanvas.sh stop-wakecanvas.sh install-autostart.sh uninstall-autostart.sh; do
  install -m 0755 "$REPO_ROOT/packaging/linux/admin-tools/$script" "$BUNDLE_ROOT/admin-tools/$script"
done
install -m 0644 "$REPO_ROOT/packaging/linux/README.txt" "$BUNDLE_ROOT/README.txt"
install -m 0644 "$REPO_ROOT/packaging/linux/admin-tools/README.txt" "$BUNDLE_ROOT/admin-tools/README.txt"

PACKAGE_PATH="$BUNDLE_ROOT/packages/living-gallery-0.2.0.wakecanvas"
(
  cd "$REPO_ROOT/experiences/living_gallery"
  mix wakecanvas.package --output "$PACKAGE_PATH"
)
(
  cd "$REPO_ROOT/platform"
  mix wakecanvas.package.verify "$PACKAGE_PATH"
)

if [ -e "$ARCHIVE_PATH" ]; then rm -f -- "$ARCHIVE_PATH"; fi
tar -C "$STAGING_ROOT" -czf "$ARCHIVE_PATH" WakeCanvas

if command -v sha256sum >/dev/null 2>&1; then
  HASH=$(sha256sum "$ARCHIVE_PATH" | cut -d ' ' -f 1)
else
  HASH=$(shasum -a 256 "$ARCHIVE_PATH" | cut -d ' ' -f 1)
fi

echo "Built $ARCHIVE_PATH"
echo "SHA-256 $HASH"
