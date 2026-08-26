#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "xcodeproj"

# Every xcodeproj release ships different default build settings, and those
# settings feed the hash that seeds every object UUID. Generating with a
# different version rewrites the whole project file, so pin it.
REQUIRED_XCODEPROJ_VERSION = "1.27.0"
unless Xcodeproj::VERSION == REQUIRED_XCODEPROJ_VERSION
  abort <<~MESSAGE
    [generate_xcodeproj] xcodeproj #{Xcodeproj::VERSION} is loaded, but this project
    is generated with #{REQUIRED_XCODEPROJ_VERSION}. Other versions produce a
    different-but-equivalent project file, which shows up as a full-file diff.

      gem install xcodeproj -v #{REQUIRED_XCODEPROJ_VERSION}

    then re-run, or use `bundle exec ruby scripts/generate_xcodeproj.rb`.
  MESSAGE
end

# Xcodeproj's own `predictabilize_uuids` hashes a path built from each object's
# `to_tree_hash`, which embeds the object's siblings *and* the gem's default
# build settings. Both of those move: adding one Swift file rewrote ~1200 of
# 1268 lines, and each gem release shifted every UUID. Keying off semantic
# identity instead keeps a new file to its own two entries.
def stable_uuid_keys(project)
  keys = {}
  root_object = project.root_object

  keys[root_object] = "project"
  configuration_lists = { root_object.build_configuration_list => "project" }

  walk_group = lambda do |group, path|
    keys[group] = "group#{path}"
    group.children.each do |child|
      if child.is_a?(Xcodeproj::Project::Object::PBXGroup)
        walk_group.call(child, "#{path}/#{child.display_name}")
      else
        keys[child] = "file/#{child.source_tree}/#{child.path}"
      end
    end
  end
  walk_group.call(project.main_group, "")

  project.targets.each do |target|
    keys[target] = "target/#{target.name}"
    configuration_lists[target.build_configuration_list] = "target/#{target.name}"

    target.build_phases.each do |phase|
      keys[phase] = "phase/#{target.name}/#{phase.isa}"
      phase.files.each do |build_file|
        keys[build_file] = "buildfile/#{target.name}/#{phase.isa}/#{build_file_identity(build_file)}"
      end
    end

    target.dependencies.each do |dependency|
      keys[dependency] = "dependency/#{target.name}/#{dependency.target.name}"
      keys[dependency.target_proxy] = "proxy/#{target.name}/#{dependency.target.name}"
    end

    target.package_product_dependencies.each do |product|
      keys[product] = "packageproduct/#{target.name}/#{product.product_name}"
    end
  end

  root_object.package_references.each do |package|
    keys[package] = "package/#{package.relative_path}"
  end

  configuration_lists.each do |list, owner|
    keys[list] = "configlist/#{owner}"
    list.build_configurations.each do |configuration|
      keys[configuration] = "config/#{owner}/#{configuration.name}"
    end
  end

  keys
end

# A build file points at either a file reference or a Swift package product.
def build_file_identity(build_file)
  reference = build_file.file_ref
  return "product/#{build_file.product_ref.product_name}" if reference.nil?

  "#{reference.source_tree}/#{reference.path}"
end

def assign_stable_uuids!(project)
  keys = stable_uuid_keys(project)

  unmapped = project.objects - keys.keys
  unless unmapped.empty?
    raise "[generate_xcodeproj:assign_stable_uuids!] no stable key for objects — " \
          "{isas: #{unmapped.map(&:isa).uniq.sort.join(", ")}}"
  end

  by_key = {}
  keys.each do |object, key|
    clash = by_key[key]
    if clash
      raise "[generate_xcodeproj:assign_stable_uuids!] duplicate key — " \
            "{key: #{key.inspect}, objects: [#{clash.isa}, #{object.isa}]}"
    end
    by_key[key] = object
  end

  replacements = {}
  keys.each do |object, key|
    uuid = Digest::MD5.hexdigest(key).upcase
    replacements[object.uuid] = uuid
    object.instance_variable_set(:@uuid, uuid)
  end

  # `container_portal` and `remote_global_id_string` hold raw UUID strings
  # captured when the dependency was wired, so they do not follow the objects.
  project.objects.each do |object|
    [:container_portal, :remote_global_id_string].each do |attribute|
      next unless object.respond_to?(attribute)

      replacement = replacements[object.send(attribute)]
      object.send("#{attribute}=", replacement) if replacement
    end
  end

  objects_by_uuid = keys.keys.each_with_object({}) { |object, hash| hash[object.uuid] = object }
  project.instance_variable_set(:@objects_by_uuid, objects_by_uuid)
  project.mark_dirty!
end


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

assign_stable_uuids!(project)
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(tests)
scheme.test_action.should_use_launch_scheme_args_env = false
# Deliberately no TestAction EnvironmentVariables: any entry here wins over the
# values xcodebuild injects from TEST_RUNNER_-prefixed shell variables, so a
# `RECORD_SNAPSHOTS = $(RECORD_SNAPSHOTS)` entry silently overwrote
# TEST_RUNNER_RECORD_SNAPSHOTS=1 with "" and made CLI re-recording impossible.
# See docs/testing.md.
scheme.save_as(project_path, "10x", true)
