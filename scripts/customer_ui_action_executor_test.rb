#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'

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

  def test_command_construction_uses_canonical_launch_log_and_capture_paths
    source = File.read(File.expand_path('customer_ui_action_executor.rb', __dir__))
    assert_includes source, "'test_mode', '--release', '--no-logs'"
    assert_includes source, "'/usr/bin/log', 'stream'"
    assert_includes source, 'capture-mini-screenshot.sh'
    assert_includes source, "'--app', 'SaneHosts', '--mode', 'temp', '--path'"
    assert_includes source, "'customer_ui_sweep', '--execution-evidence'"
  end

  def test_no_passed_execution_evidence_is_prefilled_in_plan
    @report.fetch(:actions).each do |action|
      refute action.key?(:status)
      refute action.key?(:steps_completed)
    end
  end
end
