#!/usr/bin/env bats

# Why: ตรวจสอบว่า entrypoint มี syntax ถูกต้อง
@test "bin/sshplus has valid bash syntax" {
  run bash -n bin/sshplus
  [ "$status" -eq 0 ]
}

# Why: ตรวจสอบว่า build script รันผ่าน
@test "build script completes" {
  run bash scripts/build.sh
  [ "$status" -eq 0 ]
}

# Why: ตรวจสอบว่าไฟล์ dist ถูกสร้างจริง
@test "dist file exists after build" {
  run bash scripts/build.sh
  [ "$status" -eq 0 ]
  [ -f dist/sshplus.sh ]
}

# Why: ตรวจสอบ syntax ของไฟล์ distribution
@test "dist file has valid bash syntax" {
  run bash scripts/build.sh
  [ "$status" -eq 0 ]
  run bash -n dist/sshplus.sh
  [ "$status" -eq 0 ]
}

# Why: ตรวจสอบว่า dist รันในโหมด non-interactive ได้
@test "dist file runs in non-interactive mode" {
  run bash scripts/build.sh
  [ "$status" -eq 0 ]

  run bash dist/sshplus.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"SSHPlus Manager - Modular Scaffold"* ]]
}
