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
end
