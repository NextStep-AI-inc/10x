#!/usr/bin/env ruby

require "fileutils"
require "xcodeproj"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "10x.xcodeproj")
FileUtils.rm_rf(project_path)

project = Xcodeproj::Project.new(project_path)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2660"

app = project.new_target(:application, "10x", :osx, "15.0")
tests = project.new_target(:unit_test_bundle, "TenXAppTests", :osx, "15.0")
tests.add_dependency(app)

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

app.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    "PRODUCT_BUNDLE_IDENTIFIER" => "com.tannerpham.tenx",
    "PRODUCT_MODULE_NAME" => "TenXApp",
    "INFOPLIST_FILE" => "App/Info.plist",
    "GENERATE_INFOPLIST_FILE" => "NO",
    "SWIFT_VERSION" => "6.0",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "MACOSX_DEPLOYMENT_TARGET" => "15.0",
    "ENABLE_APP_SANDBOX" => "NO",
    "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME" => "",
    "CODE_SIGN_STYLE" => "Automatic",
  })
end

tests.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    "PRODUCT_BUNDLE_IDENTIFIER" => "com.tannerpham.tenx.tests",
    "PRODUCT_MODULE_NAME" => "TenXAppTests",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "SWIFT_VERSION" => "6.0",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "MACOSX_DEPLOYMENT_TARGET" => "15.0",
    "TEST_HOST" => "$(BUILT_PRODUCTS_DIR)/10x.app/Contents/MacOS/10x",
    "BUNDLE_LOADER" => "$(TEST_HOST)",
  })
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(tests)
scheme.save_as(project_path, "10x", true)
