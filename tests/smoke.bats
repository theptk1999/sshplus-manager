#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

@test "bin/sshplus has valid bash syntax" {
  run bash -n bin/sshplus
  [ "$status" -eq 0 ]
}

@test "all active source shell files have valid syntax" {
  run bash -c '
    set -e
    find src -type f -name "*.sh" ! -name "*.bak" -print0 |
    while IFS= read -r -d "" f; do
      bash -n "$f"
    done
    bash -n install.sh
  '

  [ "$status" -eq 0 ]
}

@test "build script completes" {
  run bash scripts/build.sh
  [ "$status" -eq 0 ]
}

@test "distribution and checksum are created" {
  run bash scripts/build.sh
  [ "$status" -eq 0 ]

  [ -s dist/sshplus.sh ]
  [ -s dist/sshplus.sh.sha256 ]
}

@test "distribution has valid bash syntax" {
  run bash scripts/build.sh
  [ "$status" -eq 0 ]

  run bash -n dist/sshplus.sh
  [ "$status" -eq 0 ]
}

@test "distribution checksum validates" {
  run bash scripts/build.sh
  [ "$status" -eq 0 ]

  run bash -c '
    cd dist
    sha256sum -c sshplus.sh.sha256
  '

  [ "$status" -eq 0 ]
}

@test "distribution exits cleanly without interactive stdin" {
  run bash scripts/build.sh
  [ "$status" -eq 0 ]

  run timeout 10 bash dist/sshplus.sh </dev/null
  [ "$status" -eq 0 ]
}
