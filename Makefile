SCHEME        = SwingCap
DESTINATION   = platform=iOS Simulator,name=iPhone 16 Pro,OS=latest
CONFIGURATION = Debug
XCODE_FLAGS   = CODE_SIGNING_ALLOWED=NO -configuration $(CONFIGURATION)

.PHONY: gen build test lint clean export-model help

help:          ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

gen:           ## Generate Xcode project from project.yml (requires xcodegen)
	xcodegen generate

build: gen     ## Build the app for the iOS Simulator
	xcodebuild build \
	  -scheme $(SCHEME) \
	  -destination '$(DESTINATION)' \
	  $(XCODE_FLAGS) \
	  | xcpretty

test: gen      ## Build and run unit tests in the iOS Simulator
	xcodebuild test \
	  -scheme $(SCHEME) \
	  -destination '$(DESTINATION)' \
	  $(XCODE_FLAGS) \
	  | xcpretty

lint:          ## Run SwiftLint (install via: brew install swiftlint)
	swiftlint lint

clean:         ## Remove derived data for this project
	xcodebuild clean \
	  -scheme $(SCHEME) \
	  -destination '$(DESTINATION)' \
	  $(XCODE_FLAGS) \
	  | xcpretty

export-model:  ## Export YOLOv8 Core ML model (requires Python 3.9+)
	python3 scripts/export_model.py
