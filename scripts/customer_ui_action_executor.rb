#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'optparse'
require 'socket'
require 'time'
require 'yaml'

class SaneHostsUIActionExecutor
  ROOT = File.expand_path('..', __dir__)
  MANIFEST = File.join(ROOT, 'Tests', 'CustomerUIActions.yml')
  AX_SOURCE = File.join(__dir__, 'customer_ui_ax_driver.swift')
  SCREENSHOT_WRAPPER = File.expand_path('../../infra/SaneProcess/scripts/mini/capture-mini-screenshot.sh', ROOT)
  SCREENSHOT_HELPER_DIR = File.expand_path('~/.codex/skills/screenshot/scripts')
  MINI_GUI_RUNNER = File.expand_path('../../infra/SaneProcess/scripts/mini/mini-gui-run.sh', ROOT)
  APP_BUNDLE_ID = 'com.mrsane.SaneHosts'
  APP_EXECUTABLE = '/Applications/SaneHosts.app/Contents/MacOS/SaneHosts'
  FIXTURE_PROFILE = 'UI Proof Profile'
  FIXTURE_DUPLICATE = "#{FIXTURE_PROFILE} 1"
  FIXTURE_MERGED = "#{FIXTURE_PROFILE} + #{FIXTURE_DUPLICATE}"
  FIXTURE_PROFILE_SIDEBAR = "#{FIXTURE_PROFILE}, inactive, 0 entries"
  FIXTURE_HOST = 'proof.invalid'
  PROCESS_EXIT_TIMEOUT = 8
  MIN_SCREENSHOT_BYTES = 10_000

  SAFE_BOUNDARIES = {
    'menu-bar-profile-actions' => [
      'Stopped before administrator authorization, /etc/hosts mutation, update checks, support sends, and Quit.'
    ],
    'dock-and-app-menu-commands' => [
      'Stopped before deactivation, update checks, support sends, and Quit.'
    ],
    'profile-lifecycle-actions' => [
      'Export reached the save panel and was canceled; profile deletion reached confirmation and was canceled.'
    ],
    'preset-template-import-actions' => [
      'Custom import used an invalid local fixture URL and stopped before external network completion.'
    ],
    'activation-deactivation-hosts-write' => [
      'Opened the activation route but stopped before administrator authorization or real /etc/hosts mutation.'
    ],
    'bulk-entry-actions' => [
      'Bulk delete was not performed; enable and disable used only the isolated UI-proof profile.'
    ],
    'settings-license-about-update-support' => [
      'Stopped before live update checks, checkout, license activation, or support sends.'
    ],
    'persistence-security-and-release-surfaces' => [
      'Verified isolated profile persistence and safe customer surfaces without privileged writes.'
    ]
  }.freeze

  attr_reader :plans

  def initialize(argv = [])
    @execute = false
    OptionParser.new do |parser|
      parser.banner = 'Usage: customer_ui_action_executor.rb [--plan | --execute]'
      parser.on('--plan', 'Print the AX/control/readback/artifact plan without touching the GUI') {}
      parser.on('--execute', 'Run the real Mini action lane') { @execute = true }
    end.parse!(argv)
    @manifest = YAML.safe_load(File.read(MANIFEST), aliases: false)
    @actions = Array(@manifest.fetch('actions')).select { |action| action['release_required'] != false }
    @plans = build_plans
    @owned_processes = []
    validate_plan!
  end

  def run
    return puts(JSON.pretty_generate(plan_report)) unless @execute

    require_mini!
    require_clean_checkout!
    refuse_competing_gui!
    prepare_paths!
    execution_error = nil
    begin
      prepare_isolated_fixture!
      compile_ax_driver!
      validate_screenshot_route!
      start_live_log!
      launch_app!
      load_contract_identity!
      @actions.each { |action| execute_action!(action) }
      write_execution_evidence!
      ingest_evidence!
      puts @execution_path
    rescue StandardError => e
      execution_error = e
    ensure
      cleanup_error = cleanup_after_execution
      write_failure(execution_error || cleanup_error, cleanup_error: cleanup_error) if execution_error || cleanup_error
    end
    raise execution_error if execution_error
    raise cleanup_error if cleanup_error
  end

  def plan_report
    {
      app: 'SaneHosts',
      execution_mode: @execute ? 'executed' : 'not_executed',
      action_count: @actions.length,
      actions: @actions.map do |action|
        plan = @plans.fetch(action.fetch('id'))
        {
          id: action.fetch('id'),
          controls: plan.map { |step| step.fetch(:labels) },
          roles: plan.map { |step| step.fetch(:roles) },
          subroles: plan.map { |step| step.fetch(:subroles) },
          ax_actions: plan.map { |step| step.fetch(:action) },
          readbacks: plan.map { |step| step.fetch(:expected) },
          screenshot: "outputs/customer-ui/sweep-<timestamp>/visual/#{action.fetch('id')}.png",
          click_receipt: "outputs/customer-ui/sweep-<timestamp>/#{action.fetch('id')}-click.json",
          state_receipt: "outputs/customer-ui/sweep-<timestamp>/#{action.fetch('id')}-state.json",
          safe_boundaries: SAFE_BOUNDARIES.fetch(action.fetch('id'), [])
        }
      end
    }
  end

  private

  def step(labels, action:, expected:, app_name: 'SaneHosts', bundle_id: APP_BUNDLE_ID, roles: nil, subroles: nil, value: nil)
    {
      labels: Array(labels),
      action: action,
      expected: Array(expected).map { |group| Array(group) },
      app_name: app_name,
      bundle_id: bundle_id,
      roles: Array(roles).compact,
      subroles: Array(subroles).compact,
      value: value
    }
  end

  def build_plans
    {
      'onboarding-and-tutorial-entry' => [
        step(['Next', 'welcome-next'], action: 'press', roles: 'AXButton', expected: ['One quick walkthrough.']),
        step(['Next', 'welcome-next'], action: 'press', roles: 'AXButton', expected: ["One click, then you're protected."]),
        step(['Next', 'welcome-next'], action: 'press', roles: 'AXButton',
             expected: ['Try every feature for 14 days. Buy once if it works for you.']),
        step(['Next', 'welcome-next'], action: 'press', roles: 'AXButton', expected: ['Our Sane Philosophy']),
        step(['Next', 'welcome-next'], action: 'press', roles: 'AXButton', expected: ['Privacy First']),
        step(['Next', 'welcome-next'], action: 'press', roles: 'AXButton', expected: [['14-Day Trial', "You're all set"]]),
        step(['Continue Trial', 'Start Using SaneHosts'], action: 'press', roles: 'AXButton',
             expected: ['QUICK ACTIONS']),
        step('Help', action: 'press', roles: 'AXMenuBarItem', expected: ['Show Tutorial']),
        step('Show Tutorial', action: 'press', expected: [['Next step', 'Skip tutorial']]),
        step('Next step', action: 'press', expected: ['Finish tutorial']),
        step('Finish tutorial', action: 'press', expected: ['QUICK ACTIONS'])
      ],
      'menu-bar-profile-actions' => [
        step(%w[network status\ menu], action: 'show_menu', roles: 'AXMenuBarItem', subroles: 'AXMenuExtra',
             expected: [['Open SaneHosts'], ['Quit SaneHosts']]),
        step('Open SaneHosts', action: 'press', expected: ['QUICK ACTIONS'])
      ],
      'dock-and-app-menu-commands' => [
        step('SaneHosts', action: 'show_menu', app_name: 'Dock', bundle_id: 'com.apple.dock',
             roles: 'AXDockItem', expected: [['Open SaneHosts'], ['Settings']]),
        step('File', action: 'press', roles: 'AXMenuBarItem',
             expected: [['New Profile'], ['Import Blocklist']]),
        step('New Profile', action: 'press', expected: [['New Profile'], ['Create']]),
        step('Cancel', action: 'press', expected: ['QUICK ACTIONS'])
      ],
      'quick-actions-and-paid-access-gates' => [
        step('Open Essentials', action: 'press', expected: ['Essentials']),
        step('Import Blocklist', action: 'press', expected: ['Import Blocklists']),
        step('Cancel', action: 'press', expected: ['ADVANCED TOOLS']),
        step('Merge Profiles', action: 'press',
             expected: [['Create or import a second profile', 'Merge Profiles']])
      ],
      'profile-lifecycle-actions' => [
        step('Cancel', action: 'press', expected: ['New Empty Profile']),
        step('New Empty Profile', action: 'press', expected: [['New Profile'], ['My Profile']]),
        step('My Profile', action: 'set_value', value: FIXTURE_PROFILE, expected: [FIXTURE_PROFILE]),
        step('Create', action: 'press', expected: [FIXTURE_PROFILE_SIDEBAR]),
        step(FIXTURE_PROFILE_SIDEBAR, action: 'show_menu', expected: [['Duplicate'], ['Export'], ['Delete']]),
        step('Duplicate', action: 'pick', roles: 'AXMenuItem', expected: [FIXTURE_DUPLICATE]),
        step('Merge Profiles', action: 'press',
             expected: [['Merge Profiles'], ["Select #{FIXTURE_PROFILE}"], ["Deselect #{FIXTURE_DUPLICATE}"]]),
        step("Select #{FIXTURE_PROFILE}", action: 'press', expected: ["Deselect #{FIXTURE_PROFILE}"]),
        step('Merge', action: 'press', expected: ['Add new host entry']),
        step(FIXTURE_PROFILE, action: 'show_menu', expected: ['Export']),
        step('Export', action: 'pick', roles: 'AXMenuItem', expected: [['Save'], ['Cancel']]),
        step('Cancel', action: 'press', expected: [FIXTURE_PROFILE]),
        step(FIXTURE_PROFILE, action: 'show_menu', expected: ['Delete']),
        step('Delete', action: 'pick', roles: 'AXMenuItem', expected: ['This action cannot be undone']),
        step('Cancel', action: 'system_click', roles: 'AXButton', expected: [FIXTURE_PROFILE])
      ],
      'preset-template-import-actions' => [
        step('PROFILES', action: 'scroll_vertical', value: '1', expected: ['Family Safe protection level']),
        step('Family Safe protection level', action: 'press', expected: ['Add Family Safe']),
        step('PROTECTION LEVELS', action: 'scroll_vertical', value: '0', expected: ['From Template']),
        step('From Template', action: 'press', expected: ['Create from Template']),
        step('Cancel template selection', action: 'press', expected: ['ADVANCED TOOLS']),
        step('Import Blocklist', action: 'press', expected: ['Import Blocklists']),
        step('Show custom URL input', action: 'press', expected: ['Custom URL']),
        step('https://example.com/hosts', action: 'set_value', value: 'http://proof.invalid/hosts',
             expected: ['Only HTTPS URLs are supported']),
        step('Cancel', action: 'press', expected: ['ADVANCED TOOLS'])
      ],
      'activation-deactivation-hosts-write' => [
        step('PROFILES', action: 'scroll_vertical', value: '0', expected: ['Essentials']),
        step('Essentials', action: 'show_menu', expected: [['Activate'], ['Export']])
      ],
      'entry-crud-search-toggle-actions' => [
        step(FIXTURE_PROFILE, action: 'press', expected: ['Add new host entry']),
        step('Add new host entry', action: 'press', expected: [['Add Entry'], ['example.local']]),
        step('example.local', action: 'set_value', value: FIXTURE_HOST, expected: [FIXTURE_HOST]),
        step('Add Entry', action: 'press', expected: [FIXTURE_HOST]),
        step(FIXTURE_HOST, action: 'show_menu', expected: [['Edit'], ['Duplicate'], ['Delete']]),
        step('Duplicate', action: 'press', expected: [FIXTURE_HOST]),
        step("Disable #{FIXTURE_HOST}", action: 'press', expected: ["Enable #{FIXTURE_HOST}"]),
        step('Filter entries', action: 'set_value', value: FIXTURE_HOST, expected: [FIXTURE_HOST])
      ],
      'bulk-entry-actions' => [
        step('Enter selection mode', action: 'press', expected: [['Select all entries'], ['Done selecting']]),
        step("Select #{FIXTURE_HOST}", action: 'press', expected: ["Deselect #{FIXTURE_HOST}"]),
        step('Disable selected entries', action: 'press', expected: ['Enable selected entries']),
        step('Enable selected entries', action: 'press', expected: ['Disable selected entries']),
        step('Done selecting', action: 'press', expected: [FIXTURE_HOST])
      ],
      'settings-license-about-update-support' => [
        step('SaneHosts', action: 'press', roles: 'AXMenuBarItem', expected: ['Settings']),
        step('Settings', action: 'press', expected: [['General'], ['License'], ['About']]),
        step('License', action: 'press', expected: [['License Key', 'Buy Full Access']]),
        step('About', action: 'press', expected: [['Report a Bug'], ['Sparkle']])
      ],
      'persistence-security-and-release-surfaces' => [
        step('General', action: 'press', expected: [['Software Updates'], ['Startup']]),
        step('Open Essentials', action: 'press', expected: [['Profile status', 'Essentials']])
      ]
    }
  end

  def validate_plan!
    ids = @actions.map { |action| action.fetch('id') }
    difference = (@plans.keys - ids) + (ids - @plans.keys)
    raise "Plan ids differ from manifest: #{difference.join(', ')}" unless difference.empty?

    @plans.each do |id, action_steps|
      raise "#{id}: no AX steps" if action_steps.empty?
      raise "#{id}: no actual AX mutation" unless action_steps.any? { |item| item[:action] != 'read' }
      action_steps.each do |item|
        raise "#{id}: blank control selector" if item[:labels].empty?
        raise "#{id}: missing bound readback" if item[:expected].empty?
      end
    end
  end

  def require_mini!
    return if Socket.gethostname.downcase.include?('mini')

    raise 'Real SaneHosts action execution must run on the Mini'
  end

  def require_clean_checkout!
    out, status = Open3.capture2e('git', '-C', ROOT, 'status', '--porcelain')
    raise "SaneHosts checkout is not clean:\n#{out}" unless status.success? && out.strip.empty?
  end

  def refuse_competing_gui!
    raise 'SaneClick still owns the Mini GUI; stop it before running SaneHosts' if system('pgrep', '-x', 'SaneClick', out: File::NULL)
    raise 'SaneHosts is already running; live log must attach before launch' if system('pgrep', '-x', 'SaneHosts', out: File::NULL)
  end

  def prepare_paths!
    @timestamp = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
    @run_rel = "outputs/customer-ui/sweep-#{@timestamp}"
    @run_dir = File.join(ROOT, @run_rel)
    @visual_dir = File.join(@run_dir, 'visual')
    @live_log_rel = "outputs/live-logs/customer_ui_sanehosts_#{@timestamp}.log"
    @live_log = File.join(ROOT, @live_log_rel)
    @runtime_log = File.join(@run_dir, 'customer-ui-runtime-proof.log')
    @execution_path = File.join(@run_dir, 'execution-evidence.json')
    @fixture_home = File.join(@run_dir, 'fixture-home')
    FileUtils.mkdir_p([@visual_dir, File.dirname(@live_log), @fixture_home])
    @results = {}
    @screenshots = []
  end

  def prepare_isolated_fixture!
    @old_fixed_home = capture_launchctl_env('CFFIXED_USER_HOME')
    @old_disable_keychain = capture_launchctl_env('SANEAPPS_DISABLE_KEYCHAIN')
    @old_customer_ui_fixture = capture_launchctl_env('SANEHOSTS_CUSTOMER_UI_FIXTURE')
    @old_process_fixed_home = ENV['CFFIXED_USER_HOME']
    ENV['CFFIXED_USER_HOME'] = @fixture_home
    system!('launchctl', 'setenv', 'CFFIXED_USER_HOME', @fixture_home)
    system!('launchctl', 'setenv', 'SANEAPPS_DISABLE_KEYCHAIN', '1')
    system!('launchctl', 'setenv', 'SANEHOSTS_CUSTOMER_UI_FIXTURE', '1')
    hosts = File.join(@run_dir, 'isolated-hosts')
    File.write(hosts, "127.0.0.1 localhost\n0.0.0.0 #{FIXTURE_HOST}\n")
    @fixture_rel = relative(File.join(@run_dir, 'fixture-state.json'))
    write_json(File.join(ROOT, @fixture_rel), {
      status: 'established',
      actions: @actions.map { |action| action.fetch('id') },
      isolation: 'CFFIXED_USER_HOME',
      app_fixture_override: 'SANEHOSTS_CUSTOMER_UI_FIXTURE',
      fixture_home: relative(@fixture_home),
      hosts_fixture: relative(hosts),
      hosts_sha256: Digest::SHA256.file(hosts).hexdigest,
      real_hosts_mutated: false
    })
  end

  def compile_ax_driver!
    @ax_binary = File.join(@run_dir, 'customer_ui_ax_driver')
    system!('xcrun', 'swiftc', AX_SOURCE, '-o', @ax_binary)
  end

  def start_live_log!
    FileUtils.touch(@live_log)
    @log_io = File.open(@live_log, 'a')
    @log_pid = Process.spawn('/usr/bin/log', 'stream', '--style', 'compact', '--level', 'debug',
                             '--predicate', 'process == "SaneHosts"', out: @log_io, err: @log_io)
    register_owned_process!(:log, @log_pid)
    @log_started_at = Time.now.utc
  end

  def launch_app!
    before = process_pids('SaneHosts')
    raise "SaneHosts appeared before launch: #{before.join(', ')}" unless before.empty?

    launch_error = nil
    begin
      system!('./scripts/SaneMaster.rb', 'test_mode', '--release', '--no-logs', chdir: ROOT)
    rescue StandardError => e
      launch_error = e
    end
    deadline = Time.now + 30
    launched = []
    until Time.now >= deadline
      launched = process_pids('SaneHosts') - before
      break unless launched.empty? && launch_error.nil?
      sleep 0.2
    end
    launched.each do |pid|
      identity = process_identity(pid)
      register_owned_process!(:app, pid, identity: identity) if identity&.include?(APP_EXECUTABLE)
    end
    raise launch_error if launch_error
    raise 'SaneHosts did not launch' if launched.empty?
    raise "Expected one launched SaneHosts process, found: #{launched.join(', ')}" unless launched.one?

    @app_pid = launched.first
    owned_app = @owned_processes.find { |owned| owned[:kind] == :app && owned[:pid] == @app_pid }
    raise "Launched PID #{@app_pid} is not the canonical SaneHosts app" unless owned_app
    raise 'Live log was not attached before launch' unless @log_started_at
  end

  def load_contract_identity!
    out, err, status = Open3.capture3('./scripts/SaneMaster.rb', 'customer_ui_contract', '--json', '--no-exit', chdir: ROOT)
    raise "Could not read customer contract identity: #{out}#{err}" unless status.success?

    report = JSON.parse(out)
    @manifest_sha = report.fetch('manifest_sha256')
    @source_fingerprint = report.fetch('source_fingerprint')
    @app_sha = git_sha(ROOT)
    @saneui_sha = git_sha(File.expand_path('../../infra/SaneUI', ROOT))
  end

  def execute_action!(action)
    id = action.fetch('id')
    observations = @plans.fetch(id).map.with_index do |request, index|
      execute_ax_request!(id, index, request)
    end
    raise "#{id}: action has no executed AX mutations" if observations.none? { |item| item.fetch('action') != 'read' }
    fixture_assertions = action_fixture_assertions!(id)

    activate_for_screenshot!(id, observations.length, @plans.fetch(id).last.fetch(:expected))

    screenshot_rel = "#{@run_rel}/visual/#{id}.png"
    screenshot = File.join(ROOT, screenshot_rel)
    capture_screenshot!(screenshot)
    raise "#{id}: canonical screenshot missing" unless File.size?(screenshot)
    raise "#{id}: screenshot path was reused" if @screenshots.include?(screenshot_rel)

    @screenshots << screenshot_rel
    click_rel = "#{@run_rel}/#{id}-click.json"
    state_rel = "#{@run_rel}/#{id}-state.json"
    clicks = observations.map do |item|
      {
        control: item.fetch('control').fetch('label'),
        action: item.fetch('action'),
        observed_result: item.fetch('observedResult'),
        performed_at: item.fetch('performedAt')
      }
    end
    write_json(File.join(ROOT, click_rel), {
      app: 'SaneHosts', host: Socket.gethostname, status: 'passed', execution_mode: 'executed',
      action_id: id, screenshot: screenshot_rel, clicks: clicks
    })
    write_json(File.join(ROOT, state_rel), {
      state: 'passed', actions: [id], screenshot_sha256: Digest::SHA256.file(screenshot).hexdigest,
      readbacks: observations.map { |item| item.fetch('matchedReadbacks') },
      fixture_assertions: fixture_assertions,
      safe_boundaries: SAFE_BOUNDARIES.fetch(id, [])
    })
    evidence = [
      evidence('mini_click', "Executed #{clicks.length} AX mutations with bound readback", click_rel),
      evidence('screenshot', 'Unique canonical Mini app screenshot', screenshot_rel),
      evidence('fixture', 'Isolated fixed-home and hosts fixture', @fixture_rel),
      evidence('log', 'Live unified log attached before launch', @live_log_rel),
      evidence('state_receipt', 'Per-action AX readback and screenshot digest', state_rel)
    ]
    @results[id] = {
      status: 'passed',
      proof_level: action.fetch('required_proof_level'),
      workflow: {
        executed: true, runner: 'scripts/customer_ui_action_executor.rb',
        outcome: observations.map { |item| item.fetch('observedResult') }.join(' | '),
        steps_completed: action.fetch('steps'),
        artifacts: evidence.map { |item| item.fetch(:path) }
      },
      functional_state: {
        status: 'established',
        detail: (["Isolated fixture #{@fixture_rel}; no real /etc/hosts mutation"] + fixture_assertions).join('; ')
      },
      inputs: action.fetch('user_inputs'),
      output_assertions: action.fetch('expected_outputs'),
      live_log: @live_log_rel,
      safe_boundaries: SAFE_BOUNDARIES.fetch(id, []),
      evidence: evidence
    }
  end

  def execute_ax_request!(action_id, index, request)
    request_path = File.join(@run_dir, format('%s-%02d-request.json', action_id, index + 1))
    write_json(request_path, {
      appName: request.fetch(:app_name), bundleID: request.fetch(:bundle_id),
      action: request.fetch(:action), labels: request.fetch(:labels), roles: request.fetch(:roles),
      subroles: request.fetch(:subroles),
      value: request[:value], expected: request.fetch(:expected), timeoutSeconds: 12
    })
    out, err, status = Open3.capture3(@ax_binary, request_path)
    raise "#{action_id}: AX driver failed: #{out}#{err}" unless status.success?

    payload = JSON.parse(out)
    raise "#{action_id}: AX driver did not return passed" unless payload['status'] == 'passed'
    payload
  end

  def action_fixture_assertions!(action_id)
    return [] unless action_id == 'profile-lifecycle-actions'

    [verify_merged_profile_fixture!]
  end

  def verify_merged_profile_fixture!(timeout: 12)
    profiles_directory = File.join(@fixture_home, 'Library', 'Application Support', 'SaneHosts', 'Profiles')
    deadline = Time.now + timeout
    loop do
      profiles = Dir.glob(File.join(profiles_directory, '*.json')).filter_map do |path|
        JSON.parse(File.read(path))
      rescue JSON::ParserError, Errno::ENOENT
        nil
      end
      merged = profiles.find { |profile| profile['name'] == FIXTURE_MERGED }
      if merged&.dig('source', 'merged', 'sourceCount') == 2
        return "Persisted #{FIXTURE_MERGED} with exactly 2 merged sources"
      end
      break if Time.now >= deadline

      sleep 0.2
    end
    raise "Exact two-source merged profile did not persist: #{FIXTURE_MERGED}"
  end

  def activate_for_screenshot!(action_id, index, expected)
    script = <<~APPLESCRIPT
      tell application "System Events"
        set candidateProcess to first application process whose bundle identifier is "#{APP_BUNDLE_ID}"
        set frontmost of candidateProcess to true
        repeat 40 times
          if frontmost of candidateProcess then return name of candidateProcess
          delay 0.1
        end repeat
        error "SaneHosts did not become frontmost"
      end tell
    APPLESCRIPT
    out, err, status = capture_with_timeout('/usr/bin/osascript', '-e', script, timeout: 6)
    raise "#{action_id}: could not make SaneHosts frontmost: #{out}#{err}" unless status.success? && out.strip == 'SaneHosts'

    request = step([], action: 'read', expected: expected)
    execute_ax_request!(action_id, index, request)
  end

  def write_execution_evidence!
    raise 'Live app log is empty' unless File.size?(@live_log)
    payload = {
      app: 'SaneHosts', host: Socket.gethostname, status: 'passed', execution_mode: 'executed',
      generated_at: Time.now.utc.iso8601, manifest_sha256: @manifest_sha,
      source_fingerprint: @source_fingerprint, app_git_sha: @app_sha, saneui_git_sha: @saneui_sha,
      live_log: @live_log_rel, screenshots: @screenshots, action_results: @results
    }
    write_json(@execution_path, payload)
  end

  def ingest_evidence!
    system!('./scripts/SaneMaster.rb', 'customer_ui_sweep', '--execution-evidence', relative(@execution_path),
            '--json', chdir: ROOT)
  end

  def restore_gui_environment!
    return unless @fixture_home

    restore_launchctl_env('CFFIXED_USER_HOME', @old_fixed_home)
    restore_launchctl_env('SANEAPPS_DISABLE_KEYCHAIN', @old_disable_keychain)
    restore_launchctl_env('SANEHOSTS_CUSTOMER_UI_FIXTURE', @old_customer_ui_fixture)
    if @old_process_fixed_home
      ENV['CFFIXED_USER_HOME'] = @old_process_fixed_home
    else
      ENV.delete('CFFIXED_USER_HOME')
    end
  end

  def validate_screenshot_route!
    dependencies = [
      SCREENSHOT_WRAPPER,
      MINI_GUI_RUNNER,
      File.join(SCREENSHOT_HELPER_DIR, 'ensure_macos_permissions.sh'),
      File.join(SCREENSHOT_HELPER_DIR, 'take_screenshot.py')
    ]
    missing = dependencies.reject { |path| File.file?(path) }
    raise "Canonical Mini screenshot route is incomplete: #{missing.join(', ')}" unless missing.empty?
  end

  def screenshot_command(path)
    [SCREENSHOT_WRAPPER, '--app', 'SaneHosts', '--mode', 'temp', '--path', path]
  end

  def capture_screenshot!(path)
    out, err, status = Open3.capture3(*screenshot_command(path))
    $stdout.write(out)
    $stderr.write(err)
    raise "Screenshot command failed: #{out}#{err}" unless status.success?
    return path if File.size?(path)

    extension = File.extname(path)
    stem = path.delete_suffix(extension)
    candidates = Dir.glob("#{stem}-w*#{extension}").select { |candidate| File.file?(candidate) }
    substantial = candidates.select { |candidate| File.size(candidate) >= MIN_SCREENSHOT_BYTES }
    unique_substantial = substantial.group_by { |candidate| Digest::SHA256.file(candidate).hexdigest }.values.map(&:first)
    unless unique_substantial.one?
      details = candidates.map do |candidate|
        digest = Digest::SHA256.file(candidate).hexdigest[0, 12]
        "#{File.basename(candidate)}=#{File.size(candidate)}:#{digest}"
      end.join(', ')
      raise "Expected one unique substantial screenshot for #{File.basename(path)}; found #{details}"
    end

    FileUtils.mv(unique_substantial.first, path)
    path
  end

  def cleanup_after_execution
    errors = []
    @owned_processes.reverse_each do |owned|
      terminate_owned_process!(owned)
    rescue StandardError => e
      errors << "#{owned.fetch(:kind)} PID #{owned.fetch(:pid)}: #{e.message}"
    end
    begin
      @log_io&.close
    rescue StandardError => e
      errors << "log handle: #{e.message}"
    end
    begin
      restore_gui_environment!
    rescue StandardError => e
      errors << "environment: #{e.message}"
    end
    remaining = owned_processes_alive
    errors << "owned processes remain: #{remaining.map { |item| "#{item[:kind]}=#{item[:pid]}" }.join(', ')}" unless remaining.empty?
    write_cleanup_receipt(errors, remaining) if @run_dir
    errors.empty? ? nil : StandardError.new("Executor cleanup failed: #{errors.join('; ')}")
  end

  def register_owned_process!(kind, pid, identity: nil)
    resolved_identity = identity || process_identity(pid)
    raise "Could not identify owned #{kind} PID #{pid}" if resolved_identity.to_s.empty?

    @owned_processes << { kind: kind, pid: pid, identity: resolved_identity }
  end

  def terminate_owned_process!(owned)
    pid = owned.fetch(:pid)
    identity = owned.fetch(:identity)
    return unless process_matches?(pid, identity)

    signal_process('TERM', pid)
    wait_for_owned_exit(pid, identity)
    if process_matches?(pid, identity)
      signal_process('KILL', pid)
      wait_for_owned_exit(pid, identity)
    end
    raise "process did not exit after TERM/KILL" if process_matches?(pid, identity)
  rescue Errno::ESRCH
    nil
  ensure
    begin
      wait_process(pid)
    rescue Errno::ECHILD
      nil
    end
  end

  def wait_for_owned_exit(pid, identity)
    deadline = Time.now + PROCESS_EXIT_TIMEOUT
    sleep 0.1 while process_matches?(pid, identity) && Time.now < deadline
  end

  def owned_processes_alive
    @owned_processes.select { |owned| process_matches?(owned.fetch(:pid), owned.fetch(:identity)) }
  end

  def process_matches?(pid, identity)
    process_identity(pid) == identity
  end

  def process_identity(pid)
    out, status = Open3.capture2e('ps', '-p', pid.to_s, '-o', 'lstart=', '-o', 'command=')
    status.success? && !out.strip.empty? ? out.strip : nil
  end

  def signal_process(signal, pid)
    Process.kill(signal, pid)
  end

  def wait_process(pid)
    Process.wait(pid, Process::WNOHANG)
  end

  def process_pids(name)
    out, status = Open3.capture2e('pgrep', '-x', name)
    return [] unless status.success?

    out.lines.filter_map { |line| Integer(line.strip, exception: false) }
  end

  def write_cleanup_receipt(errors, remaining)
    write_json(File.join(@run_dir, 'cleanup-receipt.json'), {
      app: 'SaneHosts',
      status: errors.empty? ? 'passed' : 'failed',
      generated_at: Time.now.utc.iso8601,
      owned_processes: @owned_processes,
      remaining_owned_processes: remaining,
      remaining_owned_process_count: remaining.length,
      errors: errors
    })
  end

  def write_failure(error, cleanup_error: nil)
    return unless @run_dir

    write_json(File.join(@run_dir, 'execution-failed.json'), {
      app: 'SaneHosts', status: 'failed', execution_mode: 'executed',
      generated_at: Time.now.utc.iso8601, completed_action_ids: @results.keys,
      error: "#{error.class}: #{error.message}",
      cleanup_error: cleanup_error && "#{cleanup_error.class}: #{cleanup_error.message}"
    })
  end

  def capture_launchctl_env(key)
    out, status = Open3.capture2e('launchctl', 'getenv', key)
    status.success? ? out.chomp : nil
  end

  def restore_launchctl_env(key, value)
    value.to_s.empty? ? system('launchctl', 'unsetenv', key) : system('launchctl', 'setenv', key, value)
  end

  def git_sha(path)
    out, status = Open3.capture2e('git', '-C', path, 'rev-parse', 'HEAD')
    raise "Could not resolve Git HEAD: #{path}" unless status.success?
    out.strip
  end

  def system!(*command, chdir: nil)
    options = {}
    options[:chdir] = chdir if chdir
    success = system(*command, **options)
    raise "Command failed: #{command.join(' ')}" unless success
  end

  def capture_with_timeout(*command, timeout:)
    output = error = status = nil
    Open3.popen3(*command) do |stdin, stdout, stderr, wait_thread|
      stdin.close
      unless wait_thread.join(timeout)
        Process.kill('TERM', wait_thread.pid)
        wait_thread.join(1) || Process.kill('KILL', wait_thread.pid)
        raise "Command timed out after #{timeout}s: #{command.join(' ')}"
      end
      output = stdout.read
      error = stderr.read
      status = wait_thread.value
    end
    [output, error, status]
  end

  def evidence(type, detail, path)
    { type: type, detail: detail, path: path }
  end

  def write_json(path, payload)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(payload) + "\n")
  end

  def relative(path)
    path.delete_prefix("#{ROOT}/")
  end
end

SaneHostsUIActionExecutor.new(ARGV).run if __FILE__ == $PROGRAM_NAME
