#!/usr/bin/env ruby
# Minimal standalone SaneMaster for external contributors.

require 'fileutils'

PROJECT_ROOT = File.expand_path('..', __dir__)
WORKSPACE = File.join(PROJECT_ROOT, 'SaneHosts.xcworkspace')
SCHEME = 'SaneHosts'
DERIVED_DATA = File.join(PROJECT_ROOT, '.build', 'StandaloneDerivedData')
DESTINATION = 'platform=macOS'

def run!(command)
  puts "→ #{command.join(' ')}"
  success = system(*command)
  return if success

  status = $?.respond_to?(:exitstatus) ? $?.exitstatus : 1
  exit(status || 1)
end

def build_command(configuration: 'Debug')
  [
    'xcodebuild',
    '-workspace', WORKSPACE,
    '-scheme', SCHEME,
    '-configuration', configuration,
    '-destination', DESTINATION,
    '-derivedDataPath', DERIVED_DATA,
    'CODE_SIGNING_ALLOWED=NO',
    'CODE_SIGNING_REQUIRED=NO',
    'build'
  ]
end

def built_app_path(configuration: 'Debug')
  File.join(DERIVED_DATA, 'Build', 'Products', "#{configuration}", "#{SCHEME}.app")
end

def verify!
  Dir.chdir(PROJECT_ROOT) do
    run!(['swift', 'test', '--package-path', 'SaneHostsPackage'])
    run!(build_command)
  end
end

def test_mode!
  Dir.chdir(PROJECT_ROOT) do
    run!(build_command)
    app_path = built_app_path
    unless File.directory?(app_path)
      warn "Standalone SaneMaster could not find built app at #{app_path}"
      exit 1
    end

    run!(['open', app_path])
  end
end

def usage
  <<~TEXT
    Usage: ./scripts/SaneMaster.rb <command>

    Commands:
      verify     Run package tests, then build the app
      test_mode  Build the app and launch it
  TEXT
end

command = ARGV.first

case command
when 'verify'
  verify!
when 'test_mode'
  test_mode!
else
  puts usage
  exit(command.nil? ? 0 : 1)
end
