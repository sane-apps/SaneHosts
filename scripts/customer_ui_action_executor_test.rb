#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative 'customer_ui_action_executor'

class SaneHostsUIActionExecutorTest < Minitest::Test
  def setup
    @executor = SaneHostsUIActionExecutor.new(['--plan'])
    @report = @executor.plan_report
  end

  def test_plan_matches_all_eleven_manifest_actions
    assert_equal 11, @report.fetch(:action_count)
    ids = @report.fetch(:actions).map { |action| action.fetch(:id) }
    assert_equal @executor.plans.keys.sort, ids.sort
  end

  def test_every_action_has_ax_mutation_readback_and_unique_artifact_paths
    screenshots = []
    click_receipts = []
    @report.fetch(:actions).each do |action|
      refute_empty action.fetch(:controls)
      refute_empty action.fetch(:ax_actions)
      refute_empty action.fetch(:readbacks)
      assert action.fetch(:ax_actions).any? { |name| name != 'read' }
      assert action.fetch(:readbacks).all? { |groups| !groups.empty? }
      screenshots << action.fetch(:screenshot)
      click_receipts << action.fetch(:click_receipt)
    end
    assert_equal screenshots.length, screenshots.uniq.length
    assert_equal click_receipts.length, click_receipts.uniq.length
  end

  def test_plan_mode_never_claims_execution
    assert_equal 'not_executed', @report.fetch(:execution_mode)
    output, error, status = Open3.capture3(
      RbConfig.ruby,
      File.expand_path('customer_ui_action_executor.rb', __dir__),
      '--plan'
    )
    assert status.success?, error
    parsed = JSON.parse(output)
    assert_equal 'not_executed', parsed.fetch('execution_mode')
    refute parsed.key?('action_results')
  end

  def test_safe_boundary_actions_declare_boundaries
    bounded = @report.fetch(:actions).select { |action| !action.fetch(:safe_boundaries).empty? }
    assert_operator bounded.length, :>=, 8
  end

  def test_status_menu_targets_the_menu_extra_instead_of_the_application_menu
    action = @report.fetch(:actions).find { |item| item.fetch(:id) == 'menu-bar-profile-actions' }

    assert_equal ['network', 'status menu'], action.fetch(:controls).first
    assert_equal ['AXMenuBarItem'], action.fetch(:roles).first
    assert_equal ['AXMenuExtra'], action.fetch(:subroles).first
  end

  def test_ax_driver_queries_supported_actions_and_falls_back_to_press
    source = File.read(File.expand_path('customer_ui_ax_driver.swift', __dir__))

    assert_includes source, 'AXUIElementCopyActionNames'
    assert_includes source, 'actions.contains(kAXShowMenuAction as String)'
    assert_includes source, 'actions.contains(kAXPressAction as String)'
    assert_includes source, 'result == .cannotComplete'
    assert_operator source.index('actions.contains(kAXShowMenuAction as String)'), :<,
                    source.index('actions.contains(kAXPressAction as String)')
  end

  def test_ax_driver_searches_the_application_menu_extra_root
    source = File.read(File.expand_path('customer_ui_ax_driver.swift', __dir__))

    assert_includes source, 'kAXExtrasMenuBarAttribute'
    assert_includes source, 'kAXMenuBarAttribute'
    assert_operator source.scan('searchableElements(of: root)').length, :>=, 2
  end

  def test_ax_driver_prefers_show_menu_candidates_and_limits_press_fallback
    source = File.read(File.expand_path('customer_ui_ax_driver.swift', __dir__))

    assert_includes source, 'supportedActions(of: $0).contains(kAXShowMenuAction as String)'
    assert_includes source, 'request.subroles?.contains("AXMenuExtra") == true'
    assert_includes source, 'supportedActions(of: $0).contains(kAXPressAction as String)'
    assert_includes source, 'let exactCandidates = candidates.filter'
    assert_includes source, 'let orderedCandidates = exactCandidates + candidates.filter'
    assert_includes source, 'let semanticRoles = ["AXButton", "AXMenuItem", "AXCheckBox", "AXRadioButton", "AXPopUpButton"]'
  end

  def test_profile_lifecycle_preserves_the_preselected_duplicate_and_requires_the_exact_merge
    action = @report.fetch(:actions).find { |item| item.fetch(:id) == 'profile-lifecycle-actions' }
    controls = action.fetch(:controls).flatten
    readbacks = action.fetch(:readbacks).flatten

    first_profile = controls.index("Select #{SaneHostsUIActionExecutor::FIXTURE_PROFILE}")
    merge = controls.index('Merge')
    assert_operator first_profile, :<, merge
    refute_includes controls, "Select #{SaneHostsUIActionExecutor::FIXTURE_DUPLICATE}"
    assert_includes readbacks, "Deselect #{SaneHostsUIActionExecutor::FIXTURE_DUPLICATE}"
    assert_includes readbacks, SaneHostsUIActionExecutor::FIXTURE_MERGED_SUMMARY
  end

  def test_command_construction_uses_canonical_launch_log_and_capture_paths
    source = File.read(File.expand_path('customer_ui_action_executor.rb', __dir__))
    assert_includes source, "'test_mode', '--release', '--no-logs'"
    assert_includes source, "'/usr/bin/log', 'stream'"
    assert_includes source, 'capture-mini-screenshot.sh'
    assert_includes source, "'--app', 'SaneHosts', '--mode', 'temp', '--path'"
    assert_includes source, "'customer_ui_sweep', '--execution-evidence'"
    assert_operator source.index('activate_for_screenshot!'), :<, source.index('system!(*screenshot_command')
  end

  def test_executor_reasserts_frontmost_state_before_screenshot_capture
    source = File.read(File.expand_path('customer_ui_action_executor.rb', __dir__))

    assert_includes source, 'set frontmost of candidateProcess to true'
    assert_includes source, 'bundle identifier is "#{APP_BUNDLE_ID}"'
    assert_includes source, "step([], action: 'read', expected: expected)"
    assert_includes source, "capture_with_timeout('/usr/bin/osascript'"
  end

  def test_bounded_frontmost_command_returns_output_and_terminates_hangs
    output, error, status = @executor.send(
      :capture_with_timeout, RbConfig.ruby, '-e', 'puts "SaneHosts"', timeout: 2
    )
    assert status.success?, error
    assert_equal "SaneHosts\n", output

    timeout = assert_raises(RuntimeError) do
      @executor.send(:capture_with_timeout, RbConfig.ruby, '-e', 'sleep 5', timeout: 0.1)
    end
    assert_includes timeout.message, 'Command timed out'
  end

  def test_screenshot_command_routes_locally_through_canonical_mini_wrapper
    destination = '/tmp/sanehosts-proof.png'
    command = @executor.send(:screenshot_command, destination)

    assert_equal SaneHostsUIActionExecutor::SCREENSHOT_WRAPPER, command.first
    assert_equal ['--app', 'SaneHosts', '--mode', 'temp', '--path', destination], command.drop(1)
    refute_includes command, 'ssh'
    refute command.any? { |argument| argument.include?('/usr/sbin/screencapture') }
  end

  def test_screenshot_route_preflight_requires_wrapper_runner_and_helpers
    source = File.read(File.expand_path('customer_ui_action_executor.rb', __dir__))

    assert_includes source, 'SCREENSHOT_WRAPPER'
    assert_includes source, 'MINI_GUI_RUNNER'
    assert_includes source, "File.join(SCREENSHOT_HELPER_DIR, 'ensure_macos_permissions.sh')"
    assert_includes source, "File.join(SCREENSHOT_HELPER_DIR, 'take_screenshot.py')"
    assert_includes source, 'validate_screenshot_route!'
  end

  def test_cleanup_terminates_only_exact_owned_app_and_log_processes
    app_identity = "Mon Jul 30 12:00:00 2026 #{SaneHostsUIActionExecutor::APP_EXECUTABLE}"
    log_identity = 'Mon Jul 30 11:59:59 2026 /usr/bin/log stream --predicate process == "SaneHosts"'
    unrelated_identity = "Mon Jul 30 11:00:00 2026 #{SaneHostsUIActionExecutor::APP_EXECUTABLE}"
    identities = { 101 => log_identity, 202 => app_identity, 303 => unrelated_identity }
    signals = []

    @executor.instance_variable_set(:@owned_processes, [
                                      { kind: :log, pid: 101, identity: log_identity },
                                      { kind: :app, pid: 202, identity: app_identity }
                                    ])
    @executor.define_singleton_method(:process_identity) { |pid| identities[pid] }
    @executor.define_singleton_method(:signal_process) do |signal, pid|
      signals << [signal, pid]
      identities.delete(pid)
    end
    @executor.define_singleton_method(:wait_process) { |_pid| nil }
    @executor.define_singleton_method(:restore_gui_environment!) {}

    assert_nil @executor.send(:cleanup_after_execution)
    assert_equal [['TERM', 202], ['TERM', 101]], signals
    assert_equal unrelated_identity, identities.fetch(303)
  end

  def test_cleanup_runs_after_execution_failure_and_records_zero_owned_processes
    app_identity = "Mon Jul 30 12:00:00 2026 #{SaneHostsUIActionExecutor::APP_EXECUTABLE}"
    identities = { 404 => app_identity }
    signals = []

    Dir.mktmpdir do |run_dir|
      executor = SaneHostsUIActionExecutor.new(['--execute'])
      executor.instance_variable_set(:@actions, [{ 'id' => 'simulated-failure' }])
      executor.define_singleton_method(:require_mini!) {}
      executor.define_singleton_method(:require_clean_checkout!) {}
      executor.define_singleton_method(:refuse_competing_gui!) {}
      executor.define_singleton_method(:prepare_paths!) do
        @run_dir = run_dir
        @results = {}
        @owned_processes = []
      end
      executor.define_singleton_method(:prepare_isolated_fixture!) {}
      executor.define_singleton_method(:compile_ax_driver!) {}
      executor.define_singleton_method(:validate_screenshot_route!) {}
      executor.define_singleton_method(:start_live_log!) do
        @owned_processes << { kind: :app, pid: 404, identity: app_identity }
      end
      executor.define_singleton_method(:launch_app!) {}
      executor.define_singleton_method(:load_contract_identity!) {}
      executor.define_singleton_method(:execute_action!) { |_action| raise 'simulated action failure' }
      executor.define_singleton_method(:restore_gui_environment!) {}
      executor.define_singleton_method(:process_identity) { |pid| identities[pid] }
      executor.define_singleton_method(:signal_process) do |signal, pid|
        signals << [signal, pid]
        identities.delete(pid)
      end
      executor.define_singleton_method(:wait_process) { |_pid| nil }

      error = assert_raises(RuntimeError) { executor.run }

      assert_equal 'simulated action failure', error.message
      assert_equal [['TERM', 404]], signals
      cleanup = JSON.parse(File.read(File.join(run_dir, 'cleanup-receipt.json')))
      assert_equal 'passed', cleanup.fetch('status')
      assert_equal 0, cleanup.fetch('remaining_owned_process_count')
      recorded_failure = JSON.parse(File.read(File.join(run_dir, 'execution-failed.json')))
      assert_equal 'RuntimeError: simulated action failure', recorded_failure.fetch('error')
      assert_nil recorded_failure.fetch('cleanup_error')
    end
  end

  def test_cleanup_receipt_records_zero_owned_processes
    app_identity = "Mon Jul 30 12:00:00 2026 #{SaneHostsUIActionExecutor::APP_EXECUTABLE}"
    identities = { 404 => app_identity }
    signals = []

    Dir.mktmpdir do |run_dir|
      @executor.instance_variable_set(:@run_dir, run_dir)
      @executor.instance_variable_set(:@results, {})
      @executor.instance_variable_set(:@owned_processes, [
                                        { kind: :app, pid: 404, identity: app_identity }
                                      ])
      @executor.define_singleton_method(:process_identity) { |pid| identities[pid] }
      @executor.define_singleton_method(:signal_process) do |signal, pid|
        signals << [signal, pid]
        identities.delete(pid)
      end
      @executor.define_singleton_method(:wait_process) { |_pid| nil }
      @executor.define_singleton_method(:restore_gui_environment!) {}

      cleanup_error = @executor.send(:cleanup_after_execution)

      assert_nil cleanup_error
      assert_equal [['TERM', 404]], signals
      cleanup = JSON.parse(File.read(File.join(run_dir, 'cleanup-receipt.json')))
      assert_equal 'passed', cleanup.fetch('status')
      assert_equal 0, cleanup.fetch('remaining_owned_process_count')
    end
  end

  def test_cleanup_does_not_signal_reused_pid_with_different_identity
    original_identity = "Mon Jul 30 12:00:00 2026 #{SaneHostsUIActionExecutor::APP_EXECUTABLE}"
    reused_identity = 'Mon Jul 30 12:01:00 2026 /Applications/Other.app/Contents/MacOS/Other'
    signals = []

    @executor.instance_variable_set(:@owned_processes, [
                                      { kind: :app, pid: 505, identity: original_identity }
                                    ])
    @executor.define_singleton_method(:process_identity) { |_pid| reused_identity }
    @executor.define_singleton_method(:signal_process) { |signal, pid| signals << [signal, pid] }
    @executor.define_singleton_method(:wait_process) { |_pid| nil }
    @executor.define_singleton_method(:restore_gui_environment!) {}

    assert_nil @executor.send(:cleanup_after_execution)
    assert_empty signals
  end

  def test_no_passed_execution_evidence_is_prefilled_in_plan
    @report.fetch(:actions).each do |action|
      refute action.key?(:status)
      refute action.key?(:steps_completed)
    end
  end
end
