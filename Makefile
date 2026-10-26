APP_NAME := BetterGestures
BUILD_APP := build/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app
SUBSYSTEM := dev.ozberk.BetterGestures

STRINGS_DIR := .build/stringsdata

.PHONY: app install run settings debug logs test clean stop strings release

# build and sign the .app (build/BetterGestures.app)
app:
	./Support/build-app.sh

# copy to ~/Applications. permissions and launch at login belong to this copy.
install: app stop
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALLED_APP)
	ditto $(BUILD_APP) $(INSTALLED_APP)

# start the installed app normally (the accessibility permission belongs to this app).
run: install
	open $(INSTALLED_APP)

# install and start with the settings window open.
settings: install
	open $(INSTALLED_APP) --args --settings

# run in the terminal in debug mode; raw touches are printed here. ctrl-c to quit.
debug: install
	$(INSTALLED_APP)/Contents/MacOS/$(APP_NAME) --debug

# follow the logs of an app started with `open`.
logs:
	log stream --level info --style compact --predicate 'subsystem == "$(SUBSYSTEM)"'

test:
	swift test

# universal, developer id signed, notarized zip in build/ for a github release (see Support/release.sh).
release:
	./Support/release.sh

# add ui strings from the code to Support/Localizable.xcstrings (new keys in, stale ones marked).
# translate them in xcode or by editing the json.
strings:
	rm -rf $(STRINGS_DIR)
	swift build --product $(APP_NAME) -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc $(STRINGS_DIR)
	xcrun xcstringstool sync Support/Localizable.xcstrings --stringsdata $(STRINGS_DIR)/*.stringsdata

stop:
	-pkill -x $(APP_NAME) 2>/dev/null; true

clean:
	rm -rf build .build
