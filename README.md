# SSHPlus Manager

โครงสร้างแบบ modular สำหรับ SSHPlus Manager

## โครงสร้างไฟล์

```text
sshplus-manager/
├── .github/
│   └── workflows/
│       └── ci.yml
├── bin/
│   └── sshplus
├── scripts/
│   ├── build.sh
│   └── install.sh
├── src/
│   ├── lib/
│   │   ├── core/
│   │   │   ├── guard.sh
│   │   │   ├── log.sh
│   │   │   └── validation.sh
│   │   └── data/
│   │       └── user_db.sh
│   └── main.sh
├── tests/
│   └── smoke.bats
├── .editorconfig
├── .gitignore
├── Makefile
└── README.md
