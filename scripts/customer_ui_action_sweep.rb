#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'optparse'
require 'pathname'
require 'socket'
require 'time'
require 'yaml'

class SaneHostsExecutionEvidenceValidator
  MAX_AGE_SECONDS = 12 * 60 * 60
  IMAGE_EXTENSIONS = %w[.png .jpg .jpeg].freeze
  ACCEPTED_STATES = %w[passed pass established].freeze

  def initialize(project_root:, action_ids:, manifest_actions:, manifest_sha256:, source_fingerprint:, app_git_sha:, saneui_git_sha:, safe_boundary_action_ids:)
    @project_root = File.realpath(project_root)
    @action_ids = action_ids
    @manifest_actions = manifest_actions
    @manifest_sha256 = manifest_sha256
    @source_fingerprint = source_fingerprint
    @app_git_sha = app_git_sha
    @saneui_git_sha = saneui_git_sha
    @safe_boundary_action_ids = safe_boundary_action_ids
  end

  def validate!(payload)
    raise 'Execution evidence must be a JSON object' unless payload.is_a?(Hash)
    raise 'Execution evidence app does not match SaneHosts' unless payload['app'].to_s == 'SaneHosts'
    raise 'Execution evidence must come from the Mini' unless payload['host'].to_s.downcase.include?('mini')
    raise 'Execution evidence status must be passed' unless payload['status'].to_s == 'passed'
    raise 'Execution evidence must declare execution_mode=executed' unless payload['execution_mode'].to_s == 'executed'
    raise 'Execution evidence manifest hash is stale' unless payload['manifest_sha256'].to_s == @manifest_sha256
    raise 'Execution evidence source fingerprint is stale' unless payload['source_fingerprint'].to_s == @source_fingerprint
    raise 'Execution evidence app Git SHA does not match the checkout' unless payload['app_git_sha'].to_s == @app_git_sha
    raise 'Execution evidence SaneUI Git SHA does not match the dependency checkout' unless payload['saneui_git_sha'].to_s == @saneui_git_sha

    validate_fresh_timestamp!(payload.fetch('generated_at'))
    live_log = validate_artifact_path!(payload.fetch('live_log'), expected_prefix: 'outputs/live-logs/')
    raise 'Execution evidence live log is empty' unless File.size?(live_log)

    action_results = payload['action_results']
    raise 'Execution evidence is missing per-action results' unless action_results.is_a?(Hash)
    result_ids = action_results.keys.map(&:to_s)
    missing = @action_ids - result_ids
    extra = result_ids - @action_ids
    raise "Execution evidence misses action(s): #{missing.join(', ')}" unless missing.empty?
    raise "Execution evidence has unknown action(s): #{extra.join(', ')}" unless extra.empty?

    screenshot_paths = {}
    @action_ids.each do |action_id|
      screenshot = validate_action!(action_id, action_results.fetch(action_id), payload.fetch('live_log'))
      if screenshot_paths.key?(screenshot)
        raise "#{action_id}: screenshot is reused from #{screenshot_paths.fetch(screenshot)}: #{screenshot}"
      end
      screenshot_paths[screenshot] = action_id
    end

    declared_screenshots = Array(payload['screenshots']).map(&:to_s).sort
    expected_screenshots = screenshot_paths.keys.sort
    raise 'Execution evidence screenshots must exactly match per-action screenshot evidence' unless declared_screenshots == expected_screenshots

    payload
  end

  private

  def validate_action!(action_id, result, expected_live_log)
    raise "#{action_id}: action result must be an object" unless result.is_a?(Hash)

    action = @manifest_actions.fetch(action_id)
    raise "#{action_id}: status must be passed" unless result['status'].to_s == 'passed'
    raise "#{action_id}: proof level does not match the manifest" unless result['proof_level'].to_s == action.fetch('required_proof_level').to_s
    raise "#{action_id}: workflow must declare executed=true" unless result.dig('workflow', 'executed') == true

    steps_completed = Array(result.dig('workflow', 'steps_completed'))
    expected_steps = Array(action['steps'])
    raise "#{action_id}: completed steps do not exactly match the manifest" unless steps_completed == expected_steps
    raise "#{action_id}: functional state must be established" unless result.dig('functional_state', 'status').to_s == 'established'
    raise "#{action_id}: functional state detail is blank" if result.dig('functional_state', 'detail').to_s.strip.empty?
    raise "#{action_id}: inputs do not exactly match the manifest" unless Array(result['inputs']) == Array(action['user_inputs'])
    raise "#{action_id}: output assertions do not exactly match the manifest" unless Array(result['output_assertions']) == Array(action['expected_outputs'])
    raise "#{action_id}: live log does not match the run-level log" unless result['live_log'].to_s == expected_live_log.to_s
    raise "#{action_id}: workflow runner is blank" if result.dig('workflow', 'runner').to_s.strip.empty?
    raise "#{action_id}: workflow outcome is blank" if result.dig('workflow', 'outcome').to_s.strip.empty?

    safe_boundaries = Array(result['safe_boundaries']).map(&:to_s).reject(&:empty?)
    if @safe_boundary_action_ids.include?(action_id) && safe_boundaries.empty?
      raise "#{action_id}: missing explicit safe-boundary result"
    end

    evidence = Array(result['evidence'])
    raise "#{action_id}: evidence must be path-backed objects" if evidence.empty? || evidence.any? { |item| !item.is_a?(Hash) }

    evidence_by_type = evidence.group_by { |item| item['type'].to_s }
    required_types = Array(action['required_evidence_types']).map(&:to_s)
    missing_types = required_types.reject { |type| evidence_by_type.key?(type) }
    raise "#{action_id}: missing evidence type(s): #{missing_types.join(', ')}" unless missing_types.empty?

    screenshot_items = Array(evidence_by_type['screenshot'])
    raise "#{action_id}: exactly one screenshot is required" unless screenshot_items.length == 1

    screenshot_path = screenshot_items.first.fetch('path').to_s
    workflow_artifacts = Array(result.dig('workflow', 'artifacts')).map(&:to_s)
    evidence_paths = evidence.map { |item| item['path'].to_s }
    missing_workflow_paths = evidence_paths - workflow_artifacts
    unless missing_workflow_paths.empty?
      raise "#{action_id}: workflow omits evidence artifact(s): #{missing_workflow_paths.join(', ')}"
    end

    evidence.each do |item|
      type = item['type'].to_s
      path = item['path'].to_s
      raise "#{action_id}: #{type} evidence detail is blank" if item['detail'].to_s.strip.empty?
      raise "#{action_id}: #{type} evidence path is blank" if path.empty?

      full_path = validate_artifact_path!(path)
      case type
      when 'mini_click'
        validate_click_artifact!(action_id, full_path, screenshot_path)
      when 'screenshot'
        validate_screenshot!(action_id, full_path)
      when 'fixture', 'state_receipt'
        validate_state_artifact!(action_id, type, full_path)
      when 'log'
        raise "#{action_id}: log evidence is empty" unless File.size?(full_path)
      end
    end

    screenshot_path
  end

  def validate_click_artifact!(action_id, path, expected_screenshot)
    click_receipt = JSON.parse(File.read(path, encoding: Encoding::UTF_8))
    raise "#{action_id}: mini-click receipt app mismatch" unless click_receipt['app'].to_s == 'SaneHosts'
    raise "#{action_id}: mini-click receipt must come from the Mini" unless click_receipt['host'].to_s.downcase.include?('mini')
    raise "#{action_id}: mini-click receipt status must be passed" unless click_receipt['status'].to_s == 'passed'
    raise "#{action_id}: mini-click receipt must declare execution_mode=executed" unless click_receipt['execution_mode'].to_s == 'executed'
    raise "#{action_id}: mini-click receipt action mismatch" unless click_receipt['action_id'].to_s == action_id
    raise "#{action_id}: mini-click receipt does not bind its screenshot" unless click_receipt['screenshot'].to_s == expected_screenshot

    clicks = click_receipt['clicks']
    raise "#{action_id}: mini-click receipt has no executed clicks" unless clicks.is_a?(Array) && !clicks.empty?
    clicks.each_with_index do |click, index|
      unless click.is_a?(Hash) &&
             !click['control'].to_s.strip.empty? &&
             !click['action'].to_s.strip.empty? &&
             !click['observed_result'].to_s.strip.empty? &&
             fresh_timestamp?(click['performed_at'])
        raise "#{action_id}: click ##{index + 1} lacks control, action, observed result, or timestamp"
      end
    end
  rescue JSON::ParserError => e
    raise "#{action_id}: mini-click receipt is invalid JSON: #{e.message}"
  end

  def validate_screenshot!(action_id, path)
    extension = File.extname(path).downcase
    raise "#{action_id}: screenshot extension is not supported" unless IMAGE_EXTENSIONS.include?(extension)
    raise "#{action_id}: screenshot is empty" unless File.size?(path)
  end

  def validate_state_artifact!(action_id, type, path)
    receipt = JSON.parse(File.read(path, encoding: Encoding::UTF_8))
    status = (receipt['status'] || receipt['state']).to_s.downcase
    raise "#{action_id}: #{type} status is not established/passed" unless ACCEPTED_STATES.include?(status)

    receipt_action = receipt['action_id'].to_s
    receipt_actions = Array(receipt['actions']).map(&:to_s)
    unless receipt_action == action_id || receipt_actions.include?(action_id)
      raise "#{action_id}: #{type} does not bind the action"
    end
  rescue JSON::ParserError => e
    raise "#{action_id}: #{type} is invalid JSON: #{e.message}"
  end

  def validate_artifact_path!(relative_path, expected_prefix: nil)
    path = relative_path.to_s
    raise 'Artifact path is blank' if path.empty?
    raise "Artifact path must be relative: #{path}" if Pathname.new(path).absolute?
    raise "Artifact path is outside the project: #{path}" if path.split(File::SEPARATOR).include?('..')
    raise "Artifact path must start with #{expected_prefix}: #{path}" if expected_prefix && !path.start_with?(expected_prefix)

    expanded = File.expand_path(path, @project_root)
    stat = File.lstat(expanded)
    raise "Artifact must be a regular non-symlink file: #{path}" if stat.symlink? || !stat.file?

    real = File.realpath(expanded)
    unless real.start_with?("#{@project_root}/")
      raise "Artifact resolves outside the project: #{path}"
    end

    expanded
  rescue Errno::ENOENT
    raise "Artifact file does not exist: #{path}"
  end

  def validate_fresh_timestamp!(value)
    generated_at = Time.iso8601(value.to_s)
    age = Time.now.utc - generated_at.utc
    raise 'Execution evidence timestamp is in the future' if age < -300
    raise 'Execution evidence is older than 12 hours' if age > MAX_AGE_SECONDS
  rescue ArgumentError
    raise 'Execution evidence generated_at is invalid'
  end

  def fresh_timestamp?(value)
    timestamp = Time.iso8601(value.to_s)
    age = Time.now.utc - timestamp.utc
    age >= -300 && age <= MAX_AGE_SECONDS
  rescue ArgumentError
    false
  end
end

class CustomerUIActionSweep
  PROJECT_ROOT = File.expand_path('..', __dir__)
  OUTPUT_DIR = File.join(PROJECT_ROOT, 'outputs', 'customer-ui')
  RECEIPT_PATH = File.join(PROJECT_ROOT, '.sane', 'customer_ui_action_receipt.json')
  MIRROR_RECEIPT_PATH = File.join(PROJECT_ROOT, 'outputs', 'customer_ui_action_receipt.json')
  MANIFEST_PATH = File.join(PROJECT_ROOT, 'Tests', 'CustomerUIActions.yml')
  SANEMASTER = File.join(PROJECT_ROOT, 'scripts', 'SaneMaster.rb')
  APP_NAME = 'SaneHosts'

  ACTION_GUARDS = {
    'onboarding-and-tutorial-entry' => {
      source: [
        ['SaneHosts/SaneHostsApp.swift', 'WelcomeGateView('],
        ['SaneHosts/SaneHostsApp.swift', '("checkmark", "Use all features for 14 days")'],
        ['SaneHosts/SaneHostsApp.swift', 'LicenseService.directCheckoutURL(appSlug: "sanehosts")'],
        ['SaneHosts/SaneHostsApp.swift', 'Button("Show Tutorial")'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/CoachMarkOverlay.swift', 'Button("Skip Tutorial")'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'MainViewSelectionPolicy.initialSelection']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'currentCustomerCopyUsesTrialThenPurchaseModel'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/CoachMarkOverlayCoordinateTests.swift', 'convertsGlobalToLocalFrame'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'essentialsIsDefaultSelection']
      ]
    },
    'menu-bar-profile-actions' => {
      source: [
        ['SaneHosts/SaneHostsApp.swift', 'struct MenuBarMenuContent'],
        ['SaneHosts/SaneHostsApp.swift', 'Button(ProtectionUXCopy.turnOffActionTitle)'],
        ['SaneHosts/SaneHostsApp.swift', 'ForEach(store.profiles)'],
        ['SaneHosts/SaneHostsApp.swift', 'Task { await store.activateProfile(profile) }'],
        ['SaneHosts/SaneHostsApp.swift', 'Button(SaneStandardMenu.settingsTitle)'],
        ['SaneHosts/SaneHostsApp.swift', 'Button(SaneStandardMenu.licenseTitle)'],
        ['SaneHosts/SaneHostsApp.swift', 'Button(SaneStandardMenu.aboutAndBugReportTitle)']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'SaneStandardMenu.addCoreUtilityItems'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'loadsWhenStoreIsEmpty']
      ],
      blocked_completion: [
        'Activation/deactivation menu items prove the safe route only; full admin authorization and real /etc/hosts mutation are not completed by this sweep.',
        'Check for Updates, Report a Bug, and Quit are verified as surfaces only.'
      ]
    },
    'dock-and-app-menu-commands' => {
      source: [
        ['SaneHosts/SaneHostsApp.swift', 'struct SaneHostsAppCommands'],
        ['SaneHosts/SaneHostsApp.swift', 'Button("New Profile")'],
        ['SaneHosts/SaneHostsApp.swift', 'Button("Import Blocklist...")'],
        ['SaneHosts/SaneHostsApp.swift', 'Button("Show Tutorial")'],
        ['SaneHosts/SaneHostsApp.swift', 'Button(ProtectionUXCopy.turnOffActionTitle)'],
        ['SaneHosts/SaneHostsApp.swift', 'func applicationDockMenu'],
        ['SaneHosts/SaneHostsApp.swift', 'SaneStandardMenu.openAppItem'],
        ['SaneHosts/SaneHostsApp.swift', 'SaneStandardMenu.addCoreUtilityItems']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'saneHostsSettingsActionsUseSharedOpener'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'directUpdateAction']
      ],
      blocked_completion: [
        'Turn Off Protection is verified to reach the deactivation route only; this sweep does not perform a privileged hosts-file write.',
        'Update checks are verified as safe surfaces only.'
      ]
    },
    'quick-actions-and-paid-access-gates' => {
      source: [
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainViewComponents.swift', 'struct QuickActionButton'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainViewComponents.swift', 'struct TrialCountdownCard'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'allowsUseAfterTrial(hasExpiredProTrial: Bool)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'title: "Open Essentials"'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'licenseService.proTrialDaysRemaining'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainViewComponents.swift', 'Text("Paid")'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainViewComponents.swift', 'Button("Buy SaneHosts")'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'Text("ADVANCED TOOLS")'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'proUpsellFeature = .importProfiles'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'proUpsellFeature = .multipleProfiles'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'proUpsellFeature = .downloadablePresets'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'proUpsellFeature = .profileMerge'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'Text(ProtectionUXCopy.activePersistence)']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'currentCustomerCopyUsesTrialThenPurchaseModel'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'basicCannotOpenRemoteImport'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'proCanOpenRemoteImport'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'expiredTrialDoesNotFallBackToUnpaidUse'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'expiredTrialMenuRoutesProfileActivationToMainWindowGate'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'trialCountdownCopy'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'activeProtectionCopyIsWiredIntoUI'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/ProSectionIconTests.swift', 'sidebarPassesLiveLicenseStateToPadlock']
      ]
    },
    'profile-lifecycle-actions' => {
      source: [
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileCreationSheets.swift', 'struct NewProfileSheet'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileCreationSheets.swift', 'try? await store.create(name: name)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Actions.swift', 'try? await store.duplicate(profile: profile)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MergeProfilesSheet.swift', 'struct MergeProfilesSheet'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Actions.swift', 'exportProfile(profile)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Actions.swift', 'deleteWithConfirmation()'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'public func merge(profiles profilesToMerge: [Profile], name: String)']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'createBasicProfile'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'profileSourceDisplayNames'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'existingSelectionIsPreserved'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'singleProfileDeletionUsesConfirmation']
      ],
      blocked_completion: [
        'Export is verified to the save/open panel surface only; this sweep does not write customer-selected files outside an isolated destination.',
        'Profile delete is covered by source/store proof and confirmation surfaces, not destructive live customer data removal.'
      ]
    },
    'preset-template-import-actions' => {
      source: [
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileCreationSheets.swift', 'struct TemplatePickerSheet'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/RemoteImportSheet.swift', 'struct RemoteImportSheet'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/RemoteImportSheet+Catalog.swift', 'customURLSection'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/RemoteImportSheet+Import.swift', 'importProgressOverlay'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/RemoteImportSheet+Import.swift', 'store.createMerged('],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/PresetViews.swift', 'struct PresetDetailView'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Models/ProfilePresets.swift', 'public enum ProfilePreset']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/ProfilePresetsTests.swift', 'allProtectionLevelsHaveProperties'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'adBlockingTemplate'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'remoteImportRejectsOversizedFile'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/CustomImportIntegrationTests.swift', 'testCustomURLImport']
      ],
      blocked_completion: [
        'Remote blocklist and custom URL flows are verified through source and local fixture tests; this sweep does not depend on external network availability.'
      ]
    },
    'activation-deactivation-hosts-write' => {
      source: [
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Actions.swift', 'func activateProfile(_ profile: Profile)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Actions.swift', 'func deactivateProfile()'],
        ['SaneHosts/SaneHostsApp.swift', 'func activateProfile(_ profile: Profile) async'],
        ['SaneHosts/SaneHostsApp.swift', 'func deactivateProfile() async'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Services/HostsService.swift', 'activateProfile(_ profile: Profile'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Services/HostsService.swift', 'deactivateProfile()'],
        ['SaneHosts/SaneHostsApp.swift', 'AppleScriptHostsWriteFallback']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'hostsContentValidatorRejectsInjectedLines'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'hostsContentValidatorAcceptsGeneratedContent'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'mergeSanitizesProfileName'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'userCancellationIsQuiet'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'activationSurfacesUseQuietCancellationMapping']
      ],
      blocked_completion: [
        'Full activation/deactivation requires administrator authorization and writes /etc/hosts; this sweep verifies the safe first surface and isolated generated-content fixtures only.'
      ]
    },
    'entry-crud-search-toggle-actions' => {
      source: [
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'struct AddEntrySheet'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'struct EditEntrySheet'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'searchable(text: $searchText'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'private func entryContextMenu'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'duplicateEntry(_ entry: HostEntry)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'deleteEntry(_ entry: HostEntry)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'EntryStatusIcon(isEnabled: entry.isEnabled)']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'validIPv4'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'invalidHostnames'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'generateEntrySanitizesComment'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'enabledCount']
      ]
    },
    'bulk-entry-actions' => {
      source: [
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'private var bulkActionsBar'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'proUpsellFeature = .bulkOperations'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'bulkEnableSelected()'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'bulkDisableSelected()'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'bulkDeleteSelected()'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'bulkUpdateEntries'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'bulkRemoveEntries']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'enabledCount'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'createBasicEntry']
      ],
      blocked_completion: [
        'Bulk delete is verified through source/store proof only; live destructive entry deletion requires an isolated fixture.'
      ]
    },
    'settings-license-about-update-support' => {
      source: [
        ['SaneHosts/SettingsView.swift', 'SaneSettingsContainer'],
        ['SaneHosts/SettingsView.swift', 'case general = "General"'],
        ['SaneHosts/SettingsView.swift', 'case license = "License"'],
        ['SaneHosts/SettingsView.swift', 'case about = "About"'],
        ['SaneHosts/SettingsView.swift', 'SaneSparkleRow'],
        ['SaneHosts/SettingsView.swift', 'LicenseSettingsView'],
        ['SaneHosts/SettingsView.swift', 'SaneAboutView'],
        ['SaneHosts/SaneHostsApp.swift', 'SettingsActionStorage.shared.showSettings(tab: .license)'],
        ['SaneHosts/SaneHostsApp.swift', 'SettingsActionStorage.shared.showSettings(tab: .about)']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'saneHostsSettingsSupportsQueuedTabRouting'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'SettingsActionStorage.shared.capture(openSettings)']
      ],
      blocked_completion: [
        'Live Sparkle update checks and Report a Bug sends are verified to the safe surface only.'
      ]
    },
    'persistence-security-and-release-surfaces' => {
      source: [
        ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'private let maxBackups'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'createRemote(name: String, url: URL, entries: [HostEntry], maxEntries: Int = 500_000)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'createMerged(name: String, entries: [HostEntry], sourceCount: Int, maxEntries: Int = 500_000)'],
        ['SaneHosts/SaneHostsApp.swift', 'HostsContentValidator.validate(content)'],
        ['SaneHostsHelper/main.swift', 'validateHostsContent(content)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Models/ProfilePresets.swift', 'maxBlocklistBytes'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Services/RemoteSyncService.swift', 'maxDownloadBytes'],
        ['SaneHosts/SaneHostsApp.swift', 'releaseBundleIdentifier: "com.mrsane.SaneHosts"'],
        ['SaneHosts/PrivacyInfo.xcprivacy', 'NSPrivacyTracking']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'mergeSanitizesProfileName'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'remoteImportRejectsOversizedFile'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/ProfilePresetsTests.swift', 'blocklistSourcesMatchIds']
      ],
      blocked_completion: [
        'Privileged helper and fallback writes are represented by validation proof only; this sweep does not perform privileged copy to /etc/hosts.'
      ]
    }
  }.freeze

  def initialize(argv = [])
    @execution_evidence_path = nil
    parse_options!(argv.dup)
    @started_at = Time.now.utc
    @timestamp = @started_at.strftime('%Y%m%dT%H%M%SZ')
    @transcript = []
    @action_results = {}
    @blockers = {}
    @manifest_actions = {}
  end

  def run
    Dir.chdir(PROJECT_ROOT) do
      require_mini!
      FileUtils.mkdir_p(OUTPUT_DIR)
      load_manifest!
      report = customer_ui_contract_report_before_receipt
      load_execution_evidence!(report)
      verify_manifest_guards!
      write_receipt(report)
      write_transcript
      verify_written_receipt!
      puts "Customer UI action sweep passed: #{relative(RECEIPT_PATH)}"
    end
  rescue StandardError => e
    warn "Customer UI action sweep failed: #{e.message}"
    write_failure_artifact(e)
    exit 1
  end

  private

  def parse_options!(argv)
    parser = OptionParser.new do |options|
      options.banner = 'Usage: customer_ui_action_sweep.rb --execution-evidence PATH'
      options.on('--execution-evidence PATH', 'Ingest a real Mini per-action execution receipt') do |path|
        @execution_evidence_path = path
      end
      options.on_tail('-h', '--help', 'Show this help without changing receipts') do
        puts options
        exit 0
      end
    end
    parser.parse!(argv)
    raise OptionParser::InvalidOption, argv.join(' ') unless argv.empty?
    raise OptionParser::MissingArgument, '--execution-evidence is required; synthetic source/screenshot receipts are not accepted' if @execution_evidence_path.to_s.empty?
  end

  def require_mini!
    host = Socket.gethostname.to_s.downcase
    user = ENV.fetch('USER', '').downcase
    return if host.include?('mini') || user == 'stephansmac'

    raise 'Customer UI action sweep must run on the Mini'
  end

  def load_manifest!
    raise "Missing #{MANIFEST_PATH}" unless File.exist?(MANIFEST_PATH)

    manifest = YAML.safe_load(File.read(MANIFEST_PATH), aliases: false) || {}
    raise 'Customer UI action manifest version must be 1' unless manifest['version'].to_i == 1
    raise "Manifest app #{manifest['app'].inspect} does not match #{APP_NAME}" unless manifest['app'].to_s == APP_NAME

    @manifest_actions = Array(manifest['actions']).each_with_object({}) do |action, memo|
      next if action['release_required'] == false

      id = action['id'].to_s
      memo[id] = action unless id.empty?
    end
    @action_ids = @manifest_actions.keys
    raise 'Customer UI action manifest has no release-required actions' if @action_ids.empty?

    missing = @action_ids - ACTION_GUARDS.keys
    extra = ACTION_GUARDS.keys - @action_ids
    raise "Missing sweep guard(s): #{missing.join(', ')}" unless missing.empty?
    raise "Sweep guard(s) not in manifest: #{extra.join(', ')}" unless extra.empty?

    @transcript << "manifest=#{relative(MANIFEST_PATH)} actions=#{@action_ids.length}"
  end

  def load_execution_evidence!(report)
    path = File.expand_path(@execution_evidence_path, PROJECT_ROOT)
    payload = JSON.parse(File.read(path, encoding: Encoding::UTF_8))
    safe_boundary_action_ids = ACTION_GUARDS.filter_map do |action_id, spec|
      action_id unless Array(spec[:blocked_completion]).empty?
    end
    validator = SaneHostsExecutionEvidenceValidator.new(
      project_root: PROJECT_ROOT,
      action_ids: @action_ids,
      manifest_actions: @manifest_actions,
      manifest_sha256: report.fetch('manifest_sha256'),
      source_fingerprint: report.fetch('source_fingerprint'),
      app_git_sha: git_sha(PROJECT_ROOT),
      saneui_git_sha: git_sha(File.expand_path('../../infra/SaneUI', PROJECT_ROOT)),
      safe_boundary_action_ids: safe_boundary_action_ids
    )
    @execution_evidence = validator.validate!(payload)
    @execution_evidence['source_path'] = relative(path)
    @transcript << "execution_evidence=#{relative(path)} status=passed actions=#{@action_ids.length}"
  rescue JSON::ParserError => e
    raise "Execution evidence is invalid JSON: #{e.message}"
  end

  def git_sha(path)
    out, status = Open3.capture2e('git', '-C', path, 'rev-parse', 'HEAD')
    sha = out.to_s.strip
    raise "Could not resolve Git HEAD for #{path}" unless status.success? && sha.match?(/\A[0-9a-f]{40}\z/i)

    sha
  end

  def verify_manifest_guards!
    @action_ids.each do |action_id|
      guard_spec = ACTION_GUARDS.fetch(action_id)
      source_evidence = verify_expected_strings(action_id, 'source_guard', guard_spec.fetch(:source))
      test_evidence = verify_expected_strings(action_id, 'test_guard', guard_spec.fetch(:tests))
      blocked_completion = Array(guard_spec[:blocked_completion])

      @blockers[action_id] = blocked_completion unless blocked_completion.empty?
      result = JSON.parse(JSON.generate(@execution_evidence.fetch('action_results').fetch(action_id)))
      result['evidence'] = Array(result['evidence']) +
                           source_evidence +
                           test_evidence +
                           blocked_completion.map { |detail| evidence('blocked_completion', detail) }
      @action_results[action_id] = result
      @transcript << "action=#{action_id} source_checks=#{source_evidence.length} test_checks=#{test_evidence.length} blocked_completion=#{blocked_completion.length}"
    end
  end

  def verify_expected_strings(action_id, type, checks)
    checks.map do |path, expected|
      full_path = File.join(PROJECT_ROOT, path)
      raise "#{action_id}: missing #{type} file #{path}" unless File.exist?(full_path)

      content = File.read(full_path)
      raise "#{action_id}: #{path} missing #{expected.inspect}" unless content.include?(expected)

      evidence(type, "#{path} contains #{expected.inspect}")
    end
  end

  def write_receipt(report)
    receipt = {
      app: APP_NAME,
      status: 'passed',
      host: @execution_evidence.fetch('host'),
      generated_at: @execution_evidence.fetch('generated_at'),
      manifest_sha256: report.fetch('manifest_sha256'),
      source_fingerprint: report.fetch('source_fingerprint'),
      app_git_sha: @execution_evidence.fetch('app_git_sha'),
      saneui_git_sha: @execution_evidence.fetch('saneui_git_sha'),
      execution_mode: 'executed',
      execution_source: @execution_evidence.fetch('source_path'),
      tested_action_ids: @action_ids,
      action_results: @action_results,
      screenshots: @execution_evidence.fetch('screenshots'),
      evidence: {
        sweep: relative(File.join(OUTPUT_DIR, "customer-ui-action-sweep-#{@timestamp}.txt")),
        live_log: @execution_evidence.fetch('live_log'),
        mode: 'Executed Mini action proof plus source/test guards',
        limitation: 'This sweep verifies customer-visible safe surfaces and isolated source/test fixtures. It does not perform real admin authorization, /etc/hosts mutation, live support sends, live update checks, or live external network imports.',
        blocked_completion_by_action: @blockers
      }
    }

    FileUtils.mkdir_p(File.dirname(RECEIPT_PATH))
    File.write(RECEIPT_PATH, JSON.pretty_generate(receipt) + "\n")
    File.write(MIRROR_RECEIPT_PATH, JSON.pretty_generate(receipt) + "\n")
  end

  def write_transcript
    @transcript_path = File.join(OUTPUT_DIR, "customer-ui-action-sweep-#{@timestamp}.txt")
    File.write(@transcript_path, @transcript.join("\n") + "\n")
  end

  def write_failure_artifact(error)
    FileUtils.mkdir_p(OUTPUT_DIR)
    path = File.join(OUTPUT_DIR, "customer-ui-action-sweep-failed-#{@timestamp}.txt")
    body = @transcript + ["#{error.class}: #{error.message}", *Array(error.backtrace)]
    File.write(path, body.join("\n") + "\n")
    warn "Failure transcript: #{relative(path)}"
  rescue StandardError
    nil
  end

  def customer_ui_contract_report_before_receipt
    FileUtils.rm_f(RECEIPT_PATH)
    FileUtils.rm_f(MIRROR_RECEIPT_PATH)
    customer_ui_contract_report
  end

  def customer_ui_contract_report
    # stdout only: SaneMaster prints bootstrap notices on stderr (e.g. the
    # Ruby re-exec line under a system-Ruby PATH such as the Mini GUI
    # session), and merging them corrupts the JSON payload.
    out, err, status = Open3.capture3(SANEMASTER, 'customer_ui_contract', '--json', '--no-exit')
    raise "Could not read customer UI contract report: #{out}#{err}" unless status.success?

    JSON.parse(out)
  end

  def verify_written_receipt!
    report = customer_ui_contract_report
    return if report['ok'] == true && Array(report['issues']).empty?

    FileUtils.rm_f(RECEIPT_PATH)
    FileUtils.rm_f(MIRROR_RECEIPT_PATH)
    issues = Array(report['issues'])
    detail = issues.empty? ? 'shared customer UI contract returned ok=false' : issues.join(' | ')
    raise "Written customer UI receipt failed shared contract validation: #{detail}"
  end

  def evidence(type, detail, path: nil)
    detail = detail.to_s.strip
    raise "Blank evidence detail for #{type}" if detail.empty?

    item = { type: type, detail: detail }
    item[:path] = path if path
    item
  end

  def relative(path)
    path.to_s.start_with?(PROJECT_ROOT) ? path.to_s.delete_prefix("#{PROJECT_ROOT}/") : path.to_s
  end
end

CustomerUIActionSweep.new(ARGV).run if __FILE__ == $PROGRAM_NAME
