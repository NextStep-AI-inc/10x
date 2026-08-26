# frozen_string_literal: true

source "https://rubygems.org"

# Pinned: each xcodeproj release ships different default build settings, and
# those settings feed the object UUIDs in 10x.xcodeproj/project.pbxproj.
# Generating with another version rewrites the whole file.
# scripts/generate_xcodeproj.rb asserts this version at runtime.
gem "xcodeproj", "1.27.0"
