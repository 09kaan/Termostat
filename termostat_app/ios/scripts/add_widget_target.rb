#!/usr/bin/env ruby
# This script adds the ThermostatWidget extension target to the Xcode project.
# Run this as a pre-build script in Codemagic.
#
# Usage: ruby ios/scripts/add_widget_target.rb

require 'xcodeproj'

project_path = File.join(__dir__, '..', 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)

# Check if widget target already exists
if project.targets.any? { |t| t.name == 'ThermostatWidgetExtension' }
  puts "[Widget] Target already exists, skipping."
  exit 0
end

puts "[Widget] Adding ThermostatWidgetExtension target..."

# Create the widget extension target
widget_target = project.new_target(
  :app_extension,
  'ThermostatWidgetExtension',
  :ios,
  '14.0'  # WidgetKit requires iOS 14+
)

# Set bundle identifier
widget_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.example.termostatApp.ThermostatWidget'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['INFOPLIST_FILE'] = 'ThermostatWidget/Info.plist'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['MARKETING_VERSION'] = '1.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks'
  ]
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  config.build_settings['ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME'] = 'WidgetBackground'
end

# Add swift source file
widget_dir = File.join(File.dirname(project_path), 'ThermostatWidget')
widget_group = project.main_group.new_group('ThermostatWidget', 'ThermostatWidget')

swift_file = widget_group.new_file('ThermostatWidget.swift')
widget_target.source_build_phase.add_file_reference(swift_file)

info_plist = widget_group.new_file('Info.plist')

# Add widget target as dependency of Runner
runner_target = project.targets.find { |t| t.name == 'Runner' }
if runner_target
  runner_target.add_dependency(widget_target)
  
  # Add embed extension phase
  embed_phase = runner_target.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.dst_subfolder_spec = '13' # PlugIns
  embed_phase.add_file_reference(widget_target.product_reference)
end

# Save
project.save
puts "[Widget] ThermostatWidgetExtension target added successfully!"
puts "[Widget] Bundle ID: com.example.termostatApp.ThermostatWidget"
