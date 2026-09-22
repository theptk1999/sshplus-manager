.RECIPEPREFIX = >

.PHONY: help lint fmt build test install clean

help:
> @echo "Available commands:"
> @echo "  make lint    Run ShellCheck"
> @echo "  make fmt     Format shell files with shfmt"
> @echo "  make build   Build single-file dist/sshplus.sh"
> @echo "  make test    Run bats smoke tests"
> @echo "  make install Install to /usr/local/sbin/sshplus"
> @echo "  make clean   Remove dist/"

lint:
> bash scripts/build.sh
> shellcheck --severity=warning -e SC2034 -x install.sh bin/sshplus scripts/*.sh
> shellcheck --severity=warning -e SC2034 -x dist/sshplus.sh

fmt:
> find . -type f \( -name '*.sh' -o -path './bin/sshplus' \) -print0 | xargs -0 shfmt -i 2 -ci -w

build:
> bash scripts/build.sh

test:
> bats tests

install:
> bash scripts/install.sh

clean:
> rm -rf dist
