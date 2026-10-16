ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
export WINEPREFIX ?= $(HOME)/.local/share/wineprefixes/ets5

.PHONY: all host host-server prefix dotnet mscoree fonts ets verify verify-cctor \
	launch desktop client-up client-down server-up server-down probe check

all: host prefix dotnet mscoree fonts

host:
	$(ROOT)/scripts/00-host.sh client

host-server:
	$(ROOT)/scripts/00-host.sh server

prefix:
	$(ROOT)/scripts/10-prefix.sh

dotnet: prefix
	$(ROOT)/scripts/20-dotnet.sh

mscoree: prefix
	$(ROOT)/scripts/30-mscoree.sh

fonts: prefix
	$(ROOT)/scripts/40-fonts.sh

ets: mscoree fonts
	$(ROOT)/scripts/50-ets.sh "$(ETS_SETUP)"

verify:
	$(ROOT)/scripts/60-verify.sh

verify-cctor:
	$(ROOT)/scripts/60-verify.sh --cctor

launch:
	$(ROOT)/bin/ets5

desktop:
	$(ROOT)/scripts/install-desktop.sh

client-up:
	$(ROOT)/scripts/compose.sh client up -d

client-down:
	$(ROOT)/scripts/compose.sh client down

server-up:
	$(ROOT)/scripts/compose.sh server up -d

server-down:
	$(ROOT)/scripts/compose.sh server down

probe:
	i686-w64-mingw32-gcc -O2 -o $(ROOT)/probe/hidparent-probe.exe \
		$(ROOT)/probe/hidparent-probe.c -lsetupapi -lcfgmgr32

check:
	@for s in $(ROOT)/scripts/*.sh $(ROOT)/bin/ets5; do bash -n "$$s"; done
	python3 $(ROOT)/scripts/import_dotnet40_com.py --self-test
	python3 $(ROOT)/scripts/ets5hash.py --self-test
