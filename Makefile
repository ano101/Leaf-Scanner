DERIVED := ./DerivedData
DEVICE := platform=iOS Simulator,name=iPhone 17 Pro

.PHONY: project build test clean

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
