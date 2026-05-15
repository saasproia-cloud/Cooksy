#!/usr/bin/env ruby
# Adds the 4 new Swift files created during the pre-launch refactor
# (Layout.swift, Typography.swift, PaywallFeatureComparisonView.swift,
# PaywallTrustStripView.swift) into the Cooksy Xcode project and target.
#
# Idempotent: re-running it after a successful add is a no-op.

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../../Cooksy.xcodeproj', __FILE__)
TARGET_NAME  = 'Cooksy'

# Each entry: [relative file path from project root, group path inside the project]
FILES_TO_ADD = [
  ['Cooksy/Core/DesignSystem/Layout.swift',                  %w[Cooksy Core DesignSystem]],
  ['Cooksy/Core/DesignSystem/Typography.swift',              %w[Cooksy Core DesignSystem]],
  ['Cooksy/Views/Premium/PaywallFeatureComparisonView.swift', %w[Cooksy Views Premium]],
  ['Cooksy/Views/Premium/PaywallTrustStripView.swift',        %w[Cooksy Views Premium]]
]

project = Xcodeproj::Project.open(PROJECT_PATH)
target  = project.targets.find { |t| t.name == TARGET_NAME }
abort "❌ Target #{TARGET_NAME} not found" unless target

def find_or_create_group(project, path_components)
  group = project.main_group
  path_components.each do |segment|
    child = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == segment }
    abort "❌ Group not found: #{path_components.join('/')} (missing '#{segment}')" unless child
    group = child
  end
  group
end

added = []
skipped = []

FILES_TO_ADD.each do |file_path, group_components|
  absolute_path = File.join(File.dirname(PROJECT_PATH), file_path)
  unless File.exist?(absolute_path)
    abort "❌ Source file missing on disk: #{absolute_path}"
  end

  group = find_or_create_group(project, group_components)
  basename = File.basename(file_path)

  # Skip if a file reference with the same name already lives in this group
  existing_ref = group.files.find { |f| f.display_name == basename }
  if existing_ref
    skipped << file_path
    next
  end

  file_ref = group.new_reference(absolute_path)
  target.add_file_references([file_ref])
  added << file_path
end

project.save

puts "✅ Added (#{added.size}):"
added.each { |f| puts "   + #{f}" }
unless skipped.empty?
  puts ""
  puts "↷ Already present (#{skipped.size}):"
  skipped.each { |f| puts "   = #{f}" }
end
