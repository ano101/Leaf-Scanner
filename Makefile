DERIVED := ./DerivedData
DEVICE := platform=iOS Simulator,name=iPhone 17 Pro
# Телефон подписывается настоящим профилем команды, поэтому сборка под него
# отдельной целью: на симуляторе профиль не нужен и только замедляет.
PHONE_BUILD := id=00008150-001559C20141401C
PHONE_INSTALL := 55703092-8FF3-5E74-BCFC-BC7D31B75CA4
BUNDLE := ru.kotliar.leaf

.PHONY: project build test clean phone phone-run

project:
	xcodegen generate

build: project
	xcodebuild build -scheme Leaf -destination '$(DEVICE)' -derivedDataPath $(DERIVED) -quiet

test: project
	@set -o pipefail; xcodebuild test -scheme Leaf -destination '$(DEVICE)' -derivedDataPath $(DERIVED) 2>&1 \
		| grep -E "^(Test Suite|Test Case|.*Test run|◇|✔|✘|error:|warning: .*Leaf)|Executed|passed|failed" \
		| grep -v "^warning: Skipping" || true
	@set -o pipefail; xcodebuild test -scheme Leaf -destination '$(DEVICE)' -derivedDataPath $(DERIVED) -quiet > /dev/null

clean:
	rm -rf $(DERIVED) Leaf.xcodeproj

phone: project
	xcodebuild build -scheme Leaf -destination '$(PHONE_BUILD)' -derivedDataPath $(DERIVED) -allowProvisioningUpdates -quiet

phone-run: phone
	xcrun devicectl device install app --device $(PHONE_INSTALL) $(DERIVED)/Build/Products/Debug-iphoneos/Leaf.app
	xcrun devicectl device process launch --device $(PHONE_INSTALL) $(BUNDLE)
