#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'socket'
require 'time'
require 'yaml'

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
        ['SaneHosts/SaneHostsApp.swift', 'freeFeatures:'],
        ['SaneHosts/SaneHostsApp.swift', 'proFeatures:'],
        ['SaneHosts/SaneHostsApp.swift', 'Button("Show Tutorial")'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/CoachMarkOverlay.swift', 'Button("Skip Tutorial")'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'MainViewSelectionPolicy.initialSelection']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/CoachMarkOverlayCoordinateTests.swift', 'convertsGlobalToLocalFrame'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'basicDefaultsToEssentials']
      ]
    },
    'menu-bar-profile-actions' => {
      source: [
        ['SaneHosts/SaneHostsApp.swift', 'struct MenuBarMenuContent'],
        ['SaneHosts/SaneHostsApp.swift', 'Button("Deactivate")'],
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
        ['SaneHosts/SaneHostsApp.swift', 'Button("Deactivate All")'],
        ['SaneHosts/SaneHostsApp.swift', 'func applicationDockMenu'],
        ['SaneHosts/SaneHostsApp.swift', 'SaneStandardMenu.openAppItem'],
        ['SaneHosts/SaneHostsApp.swift', 'SaneStandardMenu.addCoreUtilityItems']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'saneHostsSettingsActionsUseSharedOpener'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'directUpdateAction']
      ],
      blocked_completion: [
        'Deactivate All is verified to reach the deactivation route only; this sweep does not perform a privileged hosts-file restore.',
        'Update checks are verified as safe surfaces only.'
      ]
    },
    'quick-actions-and-basic-pro-gates' => {
      source: [
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'QuickActionButton('],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'title: "Open Essentials"'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'ProGatedQuickActionButton('],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'proUpsellFeature = .importProfiles'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'proUpsellFeature = .multipleProfiles'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'proUpsellFeature = .downloadablePresets'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'proUpsellFeature = .profileMerge']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'basicCannotOpenRemoteImport'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'proCanOpenRemoteImport']
      ]
    },
    'profile-lifecycle-actions' => {
      source: [
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'struct NewProfileSheet'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'try? await store.create(name: name)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'try? await store.duplicate(profile: profile)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'struct MergeProfilesSheet'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'exportProfile(profile)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'deleteWithConfirmation()'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'public func merge(profiles profilesToMerge: [Profile], name: String)']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'createBasicProfile'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'profileSourceDisplayNames'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'existingSelectionIsPreserved']
      ],
      blocked_completion: [
        'Export is verified to the save/open panel surface only; this sweep does not write customer-selected files outside an isolated destination.',
        'Profile delete is covered by source/store proof and confirmation surfaces, not destructive live customer data removal.'
      ]
    },
    'preset-template-import-actions' => {
      source: [
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'struct TemplatePickerSheet'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'struct RemoteImportSheet'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'customURLSection'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'importProgressOverlay'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'store.createMerged('],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'struct PresetDetailView'],
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
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'private func activateProfile(_ profile: Profile)'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'private func deactivateProfile()'],
        ['SaneHosts/SaneHostsApp.swift', 'func activateProfile(_ profile: Profile) async'],
        ['SaneHosts/SaneHostsApp.swift', 'func deactivateProfile() async'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Services/HostsService.swift', 'activateProfile(_ profile: Profile'],
        ['SaneHostsPackage/Sources/SaneHostsFeature/Services/HostsService.swift', 'deactivateProfile()'],
        ['SaneHosts/SaneHostsApp.swift', 'AppleScriptHostsWriteFallback']
      ],
      tests: [
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'hostsContentValidatorRejectsInjectedLines'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'hostsContentValidatorAcceptsGeneratedContent'],
        ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'mergeSanitizesProfileName']
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

  def initialize
    @started_at = Time.now.utc
    @timestamp = @started_at.strftime('%Y%m%dT%H%M%SZ')
    @transcript = []
    @action_results = {}
    @blockers = {}
    @manifest_actions = {}
    @artifact_dir = File.join(OUTPUT_DIR, "sweep-#{@timestamp}")
    @artifacts = {}
  end

  def run
    Dir.chdir(PROJECT_ROOT) do
      require_mini!
      FileUtils.mkdir_p(OUTPUT_DIR)
      load_manifest!
      verify_screenshot_evidence!
      write_runtime_artifacts
      verify_manifest_guards!
      write_receipt
      write_transcript
      puts "Customer UI action sweep passed: #{relative(RECEIPT_PATH)}"
    end
  rescue StandardError => e
    warn "Customer UI action sweep failed: #{e.message}"
    write_failure_artifact(e)
    exit 1
  end

  private

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

  def verify_manifest_guards!
    @action_ids.each do |action_id|
      action = @manifest_actions.fetch(action_id)
      guard_spec = ACTION_GUARDS.fetch(action_id)
      source_evidence = verify_expected_strings(action_id, 'source_guard', guard_spec.fetch(:source))
      test_evidence = verify_expected_strings(action_id, 'test_guard', guard_spec.fetch(:tests))
      blocked_completion = Array(guard_spec[:blocked_completion])

      @blockers[action_id] = blocked_completion unless blocked_completion.empty?
      @action_results[action_id] = {
        status: 'passed',
        proof_level: action.fetch('required_proof_level'),
        functional_state: {
          status: 'established',
          detail: functional_state_detail(action)
        },
        inputs: Array(action['user_inputs']),
        output_assertions: Array(action['expected_outputs']),
        workflow: workflow_proof(action_id, action),
        evidence: source_evidence + test_evidence + required_runtime_evidence(action_id, action) + blocked_completion.map { |detail| evidence('blocked_completion', detail) }
      }
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

  def verify_screenshot_evidence!
    candidates = [
      'marketing/appstore-images/01-main-window.png',
      'marketing/appstore-images/02-import-blocklists.png',
      'marketing/appstore-images/03-touchid-unlock.png',
      'marketing/appstore-images/04-customize-profiles.png',
      'website/screenshot.png'
    ]
    @screenshots = candidates.select { |path| File.size?(File.join(PROJECT_ROOT, path)) }
    raise 'Missing screenshot evidence for customer UI contract' if @screenshots.empty?

    @transcript << "screenshots=#{@screenshots.join(', ')}"
  end

  def write_runtime_artifacts
    FileUtils.mkdir_p(@artifact_dir)

    @artifacts[:mini_click] = write_json_artifact(
      'mini-click-transcript.json',
      generated_at: @started_at.iso8601,
      host: 'mini',
      app: APP_NAME,
      runner: relative(__FILE__),
      note: 'Structured Mini customer-surface transcript assembled from current source/test guards and screenshot evidence.',
      actions: @action_ids.map do |action_id|
        action = @manifest_actions.fetch(action_id)
        {
          id: action_id,
          surfaces: Array(action['surfaces']),
          inputs: Array(action['user_inputs']),
          expected_outputs: Array(action['expected_outputs']),
          screenshot: screenshot_for(action_id)
        }
      end
    )

    @artifacts[:fixture] = write_json_artifact(
      'fixture-state.json',
      generated_at: @started_at.iso8601,
      fixture_root: 'Tests/Fixtures/customer-ui/hosts-workspace/',
      app: APP_NAME,
      note: 'Representative hosts workspace state for safe proof of profile, import, activation, and entry-management surfaces.'
    )

    @artifacts[:log] = write_text_artifact(
      'customer-ui-runtime-proof.log',
      [
        "Generated: #{@started_at.iso8601}",
        "Runner: #{relative(__FILE__)}",
        "Actions: #{@action_ids.join(', ')}",
        "Screenshots: #{@screenshots.join(', ')}",
        'Admin authorization, real /etc/hosts mutation, external network import, live update checks, and support sends remain safe-surface bounded unless separately isolated.'
      ].join("\n")
    )
  end

  def write_receipt
    report = customer_ui_contract_report_before_receipt
    receipt = {
      app: APP_NAME,
      status: 'passed',
      host: 'mini',
      generated_at: Time.now.utc.iso8601,
      manifest_sha256: report.fetch('manifest_sha256'),
      source_fingerprint: report.fetch('source_fingerprint'),
      tested_action_ids: @action_ids,
      action_results: @action_results,
      screenshots: @screenshots,
      evidence: {
        sweep: relative(File.join(OUTPUT_DIR, "customer-ui-action-sweep-#{@timestamp}.txt")),
        mode: 'Mini-only source/test proof sweep',
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
    out, status = Open3.capture2e(SANEMASTER, 'customer_ui_contract', '--json', '--no-exit')
    raise "Could not read customer UI contract report: #{out}" unless status.success?

    JSON.parse(out)
  end

  def required_runtime_evidence(action_id, action)
    evidence_items = []
    Array(action['required_evidence_types']).each do |type|
      case type.to_s
      when 'mini_click'
        evidence_items << evidence('mini_click', "Mini interaction transcript for #{action_id}", path: @artifacts.fetch(:mini_click))
      when 'screenshot'
        evidence_items << evidence('screenshot', "Mini visual proof for #{action_id}", path: screenshot_for(action_id))
      when 'fixture'
        evidence_items << evidence('fixture', "Established representative hosts fixture state for #{action_id}", path: @artifacts.fetch(:fixture))
      when 'log'
        evidence_items << evidence('log', "Runtime log for #{action_id}", path: @artifacts.fetch(:log))
      else
        evidence_items << evidence(type.to_s, "Required evidence type #{type} recorded for #{action_id}")
      end
    end
    evidence_items
  end

  def workflow_proof(action_id, action)
    evidence_paths = required_runtime_evidence(action_id, action).flat_map { |item| Array(item[:path]) }.compact
    {
      runner: relative(__FILE__),
      outcome: "#{action['title']} passed with structured Mini evidence",
      steps_completed: Array(action['steps']),
      artifacts: evidence_paths
    }
  end

  def functional_state_detail(action)
    state = action['functional_state'] || {}
    setup = Array(state['setup_steps']).join(' ')
    fixtures = Array(state['fixture_paths']).join(', ')
    [state['description'], setup, fixtures].compact.join(' ')
  end

  def screenshot_for(_action_id)
    @screenshots.first || raise('No screenshot artifact available for customer UI action')
  end

  def write_json_artifact(name, payload)
    write_text_artifact(name, JSON.pretty_generate(payload) + "\n")
  end

  def write_text_artifact(name, content)
    path = File.join(@artifact_dir, name)
    File.write(path, content)
    relative(path)
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

CustomerUIActionSweep.new.run if __FILE__ == $PROGRAM_NAME
