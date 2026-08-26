#!/usr/bin/env ruby

require "fileutils"
require "xcodeproj"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "10x.xcodeproj")

resolved_relative = "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
resolved_path = File.join(project_path, resolved_relative)
preserved_resolved = File.exist?(resolved_path) ? File.read(resolved_path) : nil

FileUtils.rm_rf(project_path)

project = Xcodeproj::Project.new(project_path)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2660"

app = project.new_target(:application, "10x", :osx, "15.0")
tests = project.new_target(:unit_test_bundle, "TenXAppTests", :osx, "15.0")
tests.add_dependency(app)
test_dependency = tests.dependencies.last

app_group = project.main_group.new_group("App")
test_group = project.main_group.new_group("Tests")

Dir.glob(File.join(root, "App/**/*.swift")).sort.each do |path|
  reference = app_group.new_file(path.delete_prefix(root + "/"))
  app.source_build_phase.add_file_reference(reference)
end

Dir.glob(File.join(root, "Tests/**/*.swift")).sort.each do |path|
  reference = test_group.new_file(path.delete_prefix(root + "/"))
  tests.source_build_phase.add_file_reference(reference)
end

wordmark = app_group.new_file("App/Resources/10x-wordmark.svg")
app.resources_build_phase.add_file_reference(wordmark)

icon = app_group.new_file("App/Resources/AppIcon.icon")
icon.last_known_file_type = "folder.iconcomposer.icon"
app.resources_build_phase.add_file_reference(icon)

fonts = app_group.new_file("App/Resources/Fonts")
fonts.last_known_file_type = "folder"
app.resources_build_phase.add_file_reference(fonts)

file_type_icons = app_group.new_file("App/Resources/FileTypeIcons")
file_type_icons.last_known_file_type = "folder"
app.resources_build_phase.add_file_reference(file_type_icons)

snapshot_path = File.join(root, "Tests/TenXAppTests/ReferenceImages")
if File.directory?(snapshot_path)
  reference = test_group.new_file("Tests/TenXAppTests/ReferenceImages")
  reference.last_known_file_type = "folder"
  tests.resources_build_phase.add_file_reference(reference)
end

package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package.relative_path = "OmpKit"
project.root_object.package_references << package

product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.package = package
product.product_name = "OmpKit"
app.package_product_dependencies << product

build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = product
app.frameworks_build_phase.files << build_file

sparkle_package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
sparkle_package.repositoryURL = "https://github.com/sparkle-project/Sparkle"
sparkle_package.requirement = {
  "kind" => "upToNextMajorVersion",
  "minimumVersion" => "2.6.0",
}
project.root_object.package_references << sparkle_package

sparkle_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
sparkle_product.package = sparkle_package
sparkle_product.product_name = "Sparkle"
app.package_product_dependencies << sparkle_product

sparkle_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
sparkle_build_file.product_ref = sparkle_product
app.frameworks_build_phase.files << sparkle_build_file

sqlite = project.frameworks_group.new_file("usr/lib/libsqlite3.tbd")
sqlite.source_tree = "SDKROOT"
app.frameworks_build_phase.add_file_reference(sqlite)

app.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    "PRODUCT_BUNDLE_IDENTIFIER" => "com.nextstep.tenx",
    "PRODUCT_MODULE_NAME" => "TenXApp",
    "INFOPLIST_FILE" => "App/Info.plist",
    "GENERATE_INFOPLIST_FILE" => "NO",
    "MARKETING_VERSION" => "0.1.0",
    "CURRENT_PROJECT_VERSION" => "1",
    "SWIFT_VERSION" => "6.0",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "MACOSX_DEPLOYMENT_TARGET" => "15.0",
    "ENABLE_APP_SANDBOX" => "NO",
    "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME" => "",
    "DEVELOPMENT_TEAM" => "345S42BKPY",
  })

  if configuration.name == "Release"
    configuration.build_settings.merge!({
      "CODE_SIGN_STYLE" => "Manual",
      "CODE_SIGN_IDENTITY" => "Developer ID Application",
      "ENABLE_HARDENED_RUNTIME" => "YES",
    })
  else
    configuration.build_settings.merge!({
      "CODE_SIGN_STYLE" => "Manual",
      "CODE_SIGN_IDENTITY" => "-",
      "CODE_SIGNING_REQUIRED" => "YES",
      "CODE_SIGNING_ALLOWED" => "YES",
    })
  end
end

tests.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    "PRODUCT_BUNDLE_IDENTIFIER" => "com.nextstep.tenx.tests",
    "PRODUCT_MODULE_NAME" => "TenXAppTests",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "SWIFT_VERSION" => "6.0",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "MACOSX_DEPLOYMENT_TARGET" => "15.0",
    "TEST_HOST" => "$(BUILT_PRODUCTS_DIR)/10x.app/Contents/MacOS/10x",
    "BUNDLE_LOADER" => "$(TEST_HOST)",
    "DEVELOPMENT_TEAM" => "345S42BKPY",
    "CODE_SIGN_STYLE" => "Manual",
    "CODE_SIGN_IDENTITY" => "-",
  })
end

project.predictabilize_uuids

# Xcodeproj leaves this circular dependency pair out of its predictable UUID
# pass, so pin the final two generated identifiers as well.
test_dependency_uuid = "D4AC311B1DE3EA82606B7F7685E3A230"
test_proxy_uuid = "7405643B58C04A0D4C4F6864B6221DB8"
test_dependency.instance_variable_set(:@uuid, test_dependency_uuid)
test_dependency.target_proxy.instance_variable_set(:@uuid, test_proxy_uuid)
project.save

if preserved_resolved
  FileUtils.mkdir_p(File.dirname(resolved_path))
  File.write(resolved_path, preserved_resolved)
end

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(tests)
scheme.test_action.should_use_launch_scheme_args_env = false
scheme.test_action.environment_variables = Xcodeproj::XCScheme::EnvironmentVariables.new([
  { key: "RECORD_SNAPSHOTS", value: "$(RECORD_SNAPSHOTS)" },
])
scheme.save_as(project_path, "10x", true)
