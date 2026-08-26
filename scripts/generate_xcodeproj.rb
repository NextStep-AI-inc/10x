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

# The provider account extension ships as a TypeScript source tree, not a
# compiled resource, so it needs its own Copy Files phase rather than the
# ordinary resources phase: only that phase type can place its contents at a
# `dst_path` nested under Resources/ (`omp-extensions/provider-accounts`)
# instead of a flat top-level folder named after the source directory. Only
# `index.ts` and `src/` are referenced (never `test/` or `node_modules/`), and
# `src` is a folder reference so future files added under it (e.g. a later
# task's `accounts.ts`/`events.ts`) are picked up without touching this script.
extension_group = project.main_group.new_group("OmpExtension")

extension_index = extension_group.new_file("OmpExtension/index.ts")

extension_src = extension_group.new_file("OmpExtension/src")
extension_src.last_known_file_type = "folder"

extension_copy_phase = app.new_copy_files_build_phase("Bundle Provider Account Extension")
extension_copy_phase.symbol_dst_subfolder_spec = :resources
extension_copy_phase.dst_path = "omp-extensions/provider-accounts"
extension_copy_phase.add_file_reference(extension_index)
extension_copy_phase.add_file_reference(extension_src)

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

sqlite = project.frameworks_group.new_file("usr/lib/libsqlite3.tbd")
sqlite.source_tree = "SDKROOT"
app.frameworks_build_phase.add_file_reference(sqlite)

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

project.predictabilize_uuids

# Xcodeproj leaves this circular dependency pair out of its predictable UUID
# pass, so pin the final two generated identifiers as well.
test_dependency_uuid = "D4AC311B1DE3EA82606B7F7685E3A230"
test_proxy_uuid = "7405643B58C04A0D4C4F6864B6221DB8"
test_dependency.instance_variable_set(:@uuid, test_dependency_uuid)
test_dependency.target_proxy.instance_variable_set(:@uuid, test_proxy_uuid)
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(tests)
scheme.test_action.should_use_launch_scheme_args_env = false
scheme.test_action.environment_variables = Xcodeproj::XCScheme::EnvironmentVariables.new([
  { key: "RECORD_SNAPSHOTS", value: "$(RECORD_SNAPSHOTS)" },
])
scheme.save_as(project_path, "10x", true)
