#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative 'customer_ui_action_sweep'

class SaneHostsExecutionEvidenceValidatorTest < Minitest::Test
  APP_SHA = 'a' * 40
  SANEUI_SHA = 'b' * 40
  MANIFEST_SHA = 'manifest-sha'
  SOURCE_FINGERPRINT = 'source-fingerprint'

  def setup
    @project_root = Dir.mktmpdir('sanehosts-execution-evidence')
    @action_ids = %w[first-action bounded-action]
    @manifest_actions = @action_ids.to_h do |action_id|
      [
        action_id,
        {
          'required_proof_level' => 'live_ui',
          'steps' => ["Click #{action_id}", "Observe #{action_id}"],
          'user_inputs' => ["input-#{action_id}"],
          'expected_outputs' => ["output-#{action_id}"],
          'required_evidence_types' => %w[mini_click screenshot fixture log state_receipt]
        }
      ]
    end

    write_file('outputs/live-logs/customer-ui.log', "attached before launch\nworkflow complete\n")
    @payload = {
      'app' => 'SaneHosts',
      'host' => 'sane-mini.local',
      'status' => 'passed',
      'execution_mode' => 'executed',
      'generated_at' => Time.now.utc.iso8601,
      'manifest_sha256' => MANIFEST_SHA,
      'source_fingerprint' => SOURCE_FINGERPRINT,
      'app_git_sha' => APP_SHA,
      'saneui_git_sha' => SANEUI_SHA,
      'live_log' => 'outputs/live-logs/customer-ui.log',
      'screenshots' => [],
      'action_results' => {}
    }

    @action_ids.each do |action_id|
      screenshot = "outputs/customer-ui/#{action_id}.png"
      click = "outputs/customer-ui/#{action_id}-click.json"
      fixture = "outputs/customer-ui/#{action_id}-fixture.json"
      state = "outputs/customer-ui/#{action_id}-state.json"
      write_file(screenshot, "png-#{action_id}")
      write_json(
        click,
        'app' => 'SaneHosts',
        'host' => 'sane-mini.local',
        'status' => 'passed',
        'execution_mode' => 'executed',
        'action_id' => action_id,
        'screenshot' => screenshot,
        'clicks' => [
          {
            'control' => "control-#{action_id}",
            'action' => 'click',
            'observed_result' => "observed-#{action_id}",
            'performed_at' => Time.now.utc.iso8601
          }
        ]
      )
      write_json(fixture, 'status' => 'established', 'action_id' => action_id)
      write_json(state, 'state' => 'passed', 'actions' => [action_id])

      evidence = [
        { 'type' => 'mini_click', 'detail' => "Clicked #{action_id}", 'path' => click },
        { 'type' => 'screenshot', 'detail' => "Observed #{action_id}", 'path' => screenshot },
        { 'type' => 'fixture', 'detail' => "Fixture for #{action_id}", 'path' => fixture },
        { 'type' => 'log', 'detail' => "Live log for #{action_id}", 'path' => @payload.fetch('live_log') },
        { 'type' => 'state_receipt', 'detail' => "State for #{action_id}", 'path' => state }
      ]
      @payload['screenshots'] << screenshot
      @payload['action_results'][action_id] = {
        'status' => 'passed',
        'proof_level' => 'live_ui',
        'workflow' => {
          'executed' => true,
          'runner' => 'mini-ui-executor',
          'outcome' => "#{action_id} completed",
          'steps_completed' => @manifest_actions.fetch(action_id).fetch('steps'),
          'artifacts' => evidence.map { |item| item.fetch('path') }
        },
        'functional_state' => {
          'status' => 'established',
          'detail' => "#{action_id} fixture loaded"
        },
        'inputs' => @manifest_actions.fetch(action_id).fetch('user_inputs'),
        'output_assertions' => @manifest_actions.fetch(action_id).fetch('expected_outputs'),
        'live_log' => @payload.fetch('live_log'),
        'safe_boundaries' => action_id == 'bounded-action' ? ['Stopped before privileged write'] : [],
        'evidence' => evidence
      }
    end
  end

  def teardown
    FileUtils.remove_entry(@project_root) if @project_root && File.exist?(@project_root)
  end

  def test_accepts_fresh_complete_executed_evidence
    assert_same @payload, validator.validate!(@payload)
  end

  def test_rejects_synthetic_completed_step_claim
    @payload['action_results']['first-action']['workflow']['executed'] = false

    error = assert_raises(RuntimeError) { validator.validate!(@payload) }
    assert_match(/workflow must declare executed=true/, error.message)
  end

  def test_rejects_click_receipt_without_real_clicks
    write_json(
      'outputs/customer-ui/first-action-click.json',
      'app' => 'SaneHosts',
      'host' => 'sane-mini.local',
      'status' => 'passed',
      'execution_mode' => 'executed',
      'action_id' => 'first-action',
      'screenshot' => 'outputs/customer-ui/first-action.png',
      'clicks' => []
    )

    error = assert_raises(RuntimeError) { validator.validate!(@payload) }
    assert_match(/has no executed clicks/, error.message)
  end

  def test_rejects_missing_action_result
    @payload['action_results'].delete('bounded-action')

    error = assert_raises(RuntimeError) { validator.validate!(@payload) }
    assert_match(/misses action.*bounded-action/, error.message)
  end

  def test_rejects_click_receipt_bound_to_another_screenshot
    write_json(
      'outputs/customer-ui/first-action-click.json',
      'app' => 'SaneHosts',
      'host' => 'sane-mini.local',
      'status' => 'passed',
      'execution_mode' => 'executed',
      'action_id' => 'first-action',
      'screenshot' => 'outputs/customer-ui/bounded-action.png',
      'clicks' => [
        {
          'control' => 'first-control',
          'action' => 'click',
          'observed_result' => 'first result',
          'performed_at' => Time.now.utc.iso8601
        }
      ]
    )

    error = assert_raises(RuntimeError) { validator.validate!(@payload) }
    assert_match(/does not bind its screenshot/, error.message)
  end

  def test_rejects_reused_screenshot
    reused = @payload['action_results']['first-action']['evidence'].find { |item| item['type'] == 'screenshot' }.fetch('path')
    bounded = @payload['action_results']['bounded-action']
    bounded['evidence'].find { |item| item['type'] == 'screenshot' }['path'] = reused
    bounded['workflow']['artifacts'] = bounded['evidence'].map { |item| item.fetch('path') }
    click_path = bounded['evidence'].find { |item| item['type'] == 'mini_click' }.fetch('path')
    click_receipt = JSON.parse(File.read(File.join(@project_root, click_path)))
    click_receipt['screenshot'] = reused
    write_json(click_path, click_receipt)
    @payload['screenshots'] = [reused]

    error = assert_raises(RuntimeError) { validator.validate!(@payload) }
    assert_match(/screenshot is reused/, error.message)
  end

  def test_rejects_stale_source_binding
    @payload['source_fingerprint'] = 'different-source'

    error = assert_raises(RuntimeError) { validator.validate!(@payload) }
    assert_match(/source fingerprint is stale/, error.message)
  end

  def test_rejects_missing_safe_boundary
    @payload['action_results']['bounded-action']['safe_boundaries'] = []

    error = assert_raises(RuntimeError) { validator.validate!(@payload) }
    assert_match(/missing explicit safe-boundary/, error.message)
  end

  def test_runner_requires_external_execution_evidence
    assert_raises(OptionParser::MissingArgument) { CustomerUIActionSweep.new([]) }
  end

  def test_command_line_passes_argv_to_the_runner
    script = File.expand_path('customer_ui_action_sweep.rb', __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, script, '--help')

    assert status.success?, stderr
    assert_includes stdout, '--execution-evidence PATH'
  end

  private

  def validator
    SaneHostsExecutionEvidenceValidator.new(
      project_root: @project_root,
      action_ids: @action_ids,
      manifest_actions: @manifest_actions,
      manifest_sha256: MANIFEST_SHA,
      source_fingerprint: SOURCE_FINGERPRINT,
      app_git_sha: APP_SHA,
      saneui_git_sha: SANEUI_SHA,
      safe_boundary_action_ids: ['bounded-action']
    )
  end

  def write_json(path, payload)
    write_file(path, JSON.pretty_generate(payload))
  end

  def write_file(path, content)
    full_path = File.join(@project_root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end
end
