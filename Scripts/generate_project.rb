#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'Cooksy.xcodeproj')
WORKSPACE_PATH = File.join(ROOT, 'Cooksy.xcworkspace')

FileUtils.rm_rf(PROJECT_PATH)
FileUtils.mkdir_p(File.join(WORKSPACE_PATH, 'xcshareddata'))

project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes['LastSwiftUpdateCheck'] = '2600'
project.root_object.attributes['LastUpgradeCheck'] = '2600'
project.root_object.attributes['TargetAttributes'] = {}

def ensure_group(root_group, relative_path)
  return root_group if relative_path == '.' || relative_path.empty?

  relative_path.split('/').reduce(root_group) do |group, component|
    group[component] || group.new_group(component, component)
  end
end

def add_reference(root_group, relative_path)
  parent_group = ensure_group(root_group, File.dirname(relative_path))
  parent_group.files.find { |file| file.path == File.basename(relative_path) } ||
    parent_group.new_file(File.basename(relative_path))
end

def configure_build_settings(target, settings)
  target.build_configurations.each do |config|
    config.build_settings.merge!(settings)
  end
end

main_group = project.main_group
app_root_group = ensure_group(main_group, 'Cooksy')
extension_root_group = ensure_group(main_group, 'CooksyShareExtension')

app_target = project.new_target(:application, 'Cooksy', :ios, '17.0')
extension_target = project.new_target(:app_extension, 'CooksyShareExtension', :ios, '17.0')

project.root_object.attributes['TargetAttributes'][app_target.uuid] = {
  'CreatedOnToolsVersion' => '26.3'
}
project.root_object.attributes['TargetAttributes'][extension_target.uuid] = {
  'CreatedOnToolsVersion' => '26.3'
}

common_settings = {
  'SWIFT_VERSION' => '6.0',
  'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
  'TARGETED_DEVICE_FAMILY' => '1',
  'CURRENT_PROJECT_VERSION' => '1',
  'MARKETING_VERSION' => '1.0',
  'CODE_SIGN_STYLE' => 'Automatic',
  'DEVELOPMENT_ASSET_PATHS' => '"Cooksy/Preview Content"',
  'ENABLE_PREVIEWS' => 'YES',
  'GENERATE_INFOPLIST_FILE' => 'NO',
  'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents' => 'YES',
  'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS' => 'YES',
  'COOKSY_APP_GROUP' => 'group.com.cooksy.shared'
}

configure_build_settings(app_target, common_settings.merge(
  'BACKEND_BASE_URL' => 'https://cooksy-production-bbd1.up.railway.app',
  'PRODUCT_BUNDLE_IDENTIFIER' => 'com.cooksy.app',
  'INFOPLIST_FILE' => 'Cooksy/App/Info.plist',
  'CODE_SIGN_ENTITLEMENTS' => 'Cooksy/Cooksy.entitlements',
  'PRODUCT_NAME' => 'Cooksy',
  'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
  'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
  'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/Frameworks',
  'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'YES',
  'INFOPLIST_KEY_CFBundleDisplayName' => 'Cooksy'
))

configure_build_settings(extension_target, common_settings.merge(
  'BACKEND_BASE_URL' => 'https://cooksy-production-bbd1.up.railway.app',
  'PRODUCT_BUNDLE_IDENTIFIER' => 'com.cooksy.app.shareextension',
  'INFOPLIST_FILE' => 'CooksyShareExtension/Info.plist',
  'CODE_SIGN_ENTITLEMENTS' => 'CooksyShareExtension/CooksyShareExtension.entitlements',
  'PRODUCT_NAME' => 'CooksyShareExtension',
  'APPLICATION_EXTENSION_API_ONLY' => 'YES',
  'SKIP_INSTALL' => 'YES',
  'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
))

app_source_files = %w[
  Cooksy/App/AppAppearance.swift
  Cooksy/App/CooksyApp.swift
  Cooksy/App/Info.plist
  Cooksy/App/RootTabView.swift
  Cooksy/Core/DesignSystem/CooksyTheme.swift
  Cooksy/Models/Recipe.swift
  Cooksy/Models/RecipeBook.swift
  Cooksy/Models/SharedImportDraft.swift
  Cooksy/Services/RecipeStore.swift
  Cooksy/Services/SharedLinkInbox.swift
  Cooksy/ViewModels/HomeViewModel.swift
  Cooksy/Views/Home/HomeView.swift
  Cooksy/Views/Home/ImportGuideBanner.swift
  Cooksy/Views/Home/RecipeBookCard.swift
  Cooksy/Views/Placeholders/PlaceholderView.swift
  Cooksy/Views/Shared/BrandHeaderView.swift
  Cooksy/Views/Shared/CooksyLogoMark.swift
]

shared_files_for_extension = %w[
  Cooksy/Models/Recipe.swift
  Cooksy/Models/RecipeBook.swift
  Cooksy/Models/RecipeEditorSeed.swift
  Cooksy/Models/SharedImportDraft.swift
  Cooksy/Services/RecipeValidationService.swift
  Cooksy/Services/SharedLinkInbox.swift
]

extension_source_files = %w[
  CooksyShareExtension/Info.plist
  CooksyShareExtension/ShareViewController.swift
]

resource_files = %w[
  Cooksy/Resources/Assets.xcassets
]

app_source_files.each do |relative_path|
  next if File.extname(relative_path) == '.plist'

  file_ref = add_reference(main_group, relative_path)
  app_target.add_file_references([file_ref])
end

shared_files_for_extension.each do |relative_path|
  file_ref = add_reference(main_group, relative_path)
  extension_target.add_file_references([file_ref])
end

extension_source_files.each do |relative_path|
  next if File.extname(relative_path) == '.plist'

  file_ref = add_reference(main_group, relative_path)
  extension_target.add_file_references([file_ref])
end

resource_files.each do |relative_path|
  file_ref = add_reference(main_group, relative_path)
  app_target.resources_build_phase.add_file_reference(file_ref, true)
end

app_target.add_dependency(extension_target)
embed_phase = app_target.copy_files_build_phases.find { |phase| phase.name == 'Embed App Extensions' } ||
  app_target.new_copy_files_build_phase('Embed App Extensions')
embed_phase.dst_subfolder_spec = '13'
embed_phase.dst_path = ''
embed_build_file = embed_phase.add_file_reference(extension_target.product_reference, true)
embed_build_file.settings = { 'ATTRIBUTES' => %w[RemoveHeadersOnCopy CodeSignOnCopy] }

project.recreate_user_schemes
project.save

File.write(
  File.join(WORKSPACE_PATH, 'contents.xcworkspacedata'),
  <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <Workspace
       version = "1.0">
       <FileRef
          location = "group:Cooksy.xcodeproj">
       </FileRef>
    </Workspace>
  XML
)

File.write(
  File.join(WORKSPACE_PATH, 'xcshareddata', 'IDEWorkspaceChecks.plist'),
  <<~PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>IDEDidComputeMac32BitWarning</key>
      <true/>
    </dict>
    </plist>
  PLIST
)

puts "Generated #{PROJECT_PATH}"
