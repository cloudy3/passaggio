# Reproducible command-line workflow. Requires Xcode and XcodeGen (`brew install xcodegen`).
#
#   make bootstrap                 check tools, create Config/Local.xcconfig
#   make doctor                    compare the deployment target with the installed SDK
#   make test-core                 PassaggioCore unit tests (swift test)
#   make test                      core tests, then app tests on the simulator (SIM_DEST=... to change)
#   make build-sim                 build for the simulator
#   make build-device TEAM_ID=...  build for a device with Personal Team signing
#   make samples                   regenerate Fixtures/ (needs ffmpeg)

PROJECT      := Passaggio.xcodeproj
SCHEME       := Passaggio
DERIVED      := build/DerivedData
SIM_DEST     ?= platform=iOS Simulator,name=iPhone 16 Pro
DEPLOYMENT   := $(shell sed -n 's/^ *iOS: "\(.*\)"/\1/p' project.yml)

.PHONY: bootstrap project doctor test-core test build-sim build-device samples smoke clean

bootstrap:
	@command -v xcodebuild >/dev/null || { echo "Install Xcode from the App Store."; exit 1; }
	@command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen"; exit 1; }
	@test -f Config/Local.xcconfig || { \
		printf '// Your Personal Team ID (Xcode › Settings › Accounts › your Apple ID › Team).\nDEVELOPMENT_TEAM = %s\n' "$(TEAM_ID)" > Config/Local.xcconfig; \
		echo "Created Config/Local.xcconfig — set DEVELOPMENT_TEAM there (or pass TEAM_ID=...)."; }
	@$(MAKE) --no-print-directory project doctor

project:
	xcodegen generate --quiet

doctor:
	@sdk=$$(xcrun --sdk iphoneos --show-sdk-version); \
	echo "Deployment target: iOS $(DEPLOYMENT)   Installed iOS SDK: $$sdk   Xcode: $$(xcodebuild -version | head -1)"; \
	if [ "$$(printf '%s\n%s\n' "$(DEPLOYMENT)" "$$sdk" | sort -V | head -1)" != "$(DEPLOYMENT)" ]; then \
		echo "✗ The SDK is older than the deployment target. Update Xcode or lower iOS in project.yml."; exit 1; \
	else echo "✓ SDK supports the deployment target."; fi

test-core:
	cd Packages/PassaggioCore && swift test

test: test-core project
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(SIM_DEST)' -derivedDataPath $(DERIVED)

build-sim: project
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED)

build-device: project
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS' -derivedDataPath $(DERIVED) \
		-allowProvisioningUpdates $(if $(TEAM_ID),DEVELOPMENT_TEAM=$(TEAM_ID))

samples:
	python3 scripts/make_sample_lesson.py

smoke:
	python3 scripts/smoke_api.py

clean:
	rm -rf build $(PROJECT)
