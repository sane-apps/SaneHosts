#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "customer_ui_action_sweep"

class SaneHostsSweepInstanceTest < Minitest::Test
  def test_none_or_the_launched_app_is_fine
    assert_nil SaneHostsCustomerUIActionSweep.competing_instance_error(0)
    assert_nil SaneHostsCustomerUIActionSweep.competing_instance_error(1)
  end

  def test_duplicate_instances_are_refused
    assert_match(/2 SaneHosts instances running/, SaneHostsCustomerUIActionSweep.competing_instance_error(2))
  end

  # A sweep routed from another Mac to the Mini only receives outputs/customer-ui/
  # (SaneMaster route sync); images elsewhere under outputs/ are missing there (18 Nov 2026).
  def test_mapped_screenshots_live_where_a_routed_run_can_see_them
    SaneHostsCustomerUIActionSweep::SCREENSHOT_BY_ACTION.each do |action_id, path|
      assert path.start_with?('outputs/customer-ui/'), "#{action_id} maps to #{path}"
    end
  end
end
