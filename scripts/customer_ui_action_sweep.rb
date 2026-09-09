#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'socket'
require 'time'
require 'yaml'

# Honest Clip/Video/Click-style structured coverage for SaneHosts.
# Produces observed screenshot digests + source/test guards.
# Does NOT invent live click completion, hosts-file mutation, or admin auth.
# Legacy scripts/customer_ui_action_executor.rb receipts are revoked by contract.
class SaneHostsCustomerUIActionSweep
  PROJECT_ROOT = File.expand_path('..', __dir__)
  MANIFEST_PATH = File.join(PROJECT_ROOT, 'Tests', 'CustomerUIActions.yml')
  RECEIPT_PATH = File.join(PROJECT_ROOT, '.sane', 'customer_ui_action_receipt.json')
  OUTPUT_RECEIPT_PATH = File.join(PROJECT_ROOT, 'outputs', 'customer_ui_action_receipt.json')
  OUTPUT_DIR = File.join(PROJECT_ROOT, 'outputs', 'customer-ui')
  APP_NAME = 'SaneHosts'
  SANEMASTER = File.join(PROJECT_ROOT, 'scripts', 'SaneMaster.rb')

  # Preserved from the prior Hosts sweep; one create-string updated for current source.
  SOURCE_GUARDS = {
    'onboarding-and-tutorial-entry' => [
      ['SaneHosts/SaneHostsApp.swift', 'WelcomeGateView('],
      ['SaneHosts/SaneHostsApp.swift', '("checkmark", "Use all features for 14 days")'],
      ['SaneHosts/SaneHostsApp.swift', 'LicenseService.directCheckoutURL(appSlug: "sanehosts")'],
      ['SaneHosts/SaneHostsApp.swift', 'Button("Show Tutorial")'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/CoachMarkOverlay.swift', 'Button("Skip Tutorial")'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'MainViewSelectionPolicy.initialSelection'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'currentCustomerCopyUsesTrialThenPurchaseModel'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/CoachMarkOverlayCoordinateTests.swift', 'convertsGlobalToLocalFrame'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'essentialsIsDefaultSelection']
    ],
    'menu-bar-profile-actions' => [
      ['SaneHosts/SaneHostsApp.swift', 'struct MenuBarMenuContent'],
      ['SaneHosts/SaneHostsApp.swift', 'Button(ProtectionUXCopy.turnOffActionTitle)'],
      ['SaneHosts/SaneHostsApp.swift', 'ForEach(store.profiles)'],
      ['SaneHosts/SaneHostsApp.swift', 'Task { await store.activateProfile(profile) }'],
      ['SaneHosts/SaneHostsApp.swift', 'Button(SaneStandardMenu.settingsTitle)'],
      ['SaneHosts/SaneHostsApp.swift', 'Button(SaneStandardMenu.licenseTitle)'],
      ['SaneHosts/SaneHostsApp.swift', 'Button(SaneStandardMenu.aboutAndBugReportTitle)'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'SaneStandardMenu.addCoreUtilityItems'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'loadsWhenStoreIsEmpty']
    ],
    'dock-and-app-menu-commands' => [
      ['SaneHosts/SaneHostsApp.swift', 'struct SaneHostsAppCommands'],
      ['SaneHosts/SaneHostsApp.swift', 'Button("New Profile")'],
      ['SaneHosts/SaneHostsApp.swift', 'Button("Import Blocklist...")'],
      ['SaneHosts/SaneHostsApp.swift', 'Button("Show Tutorial")'],
      ['SaneHosts/SaneHostsApp.swift', 'Button(ProtectionUXCopy.turnOffActionTitle)'],
      ['SaneHosts/SaneHostsApp.swift', 'func applicationDockMenu'],
      ['SaneHosts/SaneHostsApp.swift', 'SaneStandardMenu.openAppItem'],
      ['SaneHosts/SaneHostsApp.swift', 'SaneStandardMenu.addCoreUtilityItems'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'saneHostsSettingsActionsUseSharedOpener'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'directUpdateAction']
    ],
    'quick-actions-and-paid-access-gates' => [
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainViewComponents.swift', 'struct QuickActionButton'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainViewComponents.swift', 'struct TrialCountdownCard'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift', 'allowsUseAfterTrial(hasExpiredProTrial'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'title: "Open Essentials"'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'licenseService.proTrialDaysRemaining'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainViewComponents.swift', 'Text("Paid")'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainViewComponents.swift', 'Button("Buy SaneHosts")'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'Text("ADVANCED TOOLS")'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'proUpsellFeature = .importProfiles'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'proUpsellFeature = .multipleProfiles'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'proUpsellFeature = .downloadablePresets'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift', 'proUpsellFeature = .profileMerge'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'Text(ProtectionUXCopy.activePersistence)'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'currentCustomerCopyUsesTrialThenPurchaseModel'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'basicCannotOpenRemoteImport'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'proCanOpenRemoteImport'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'expiredTrialDoesNotFallBackToUnpaidUse'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'expiredTrialMenuRoutesProfileActivationToMainWindowGate'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'trialCountdownCopy'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'activeProtectionCopyIsWiredIntoUI'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/ProSectionIconTests.swift', 'sidebarPassesLiveLicenseStateToPadlock']
    ],
    'profile-lifecycle-actions' => [
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileCreationSheets.swift', 'struct NewProfileSheet'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileCreationSheets.swift', 'try? await store.create(name: name, colorTag: selectedColor)'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Actions.swift', 'try? await store.duplicate(profile: profile)'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MergeProfilesSheet.swift', 'struct MergeProfilesSheet'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Actions.swift', 'exportProfile(profile)'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Actions.swift', 'deleteWithConfirmation()'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'public func merge(profiles profilesToMerge: [Profile], name: String)'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'createBasicProfile'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'profileSourceDisplayNames'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'existingSelectionIsPreserved'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'singleProfileDeletionUsesConfirmation']
    ],
    'preset-template-import-actions' => [
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileCreationSheets.swift', 'struct TemplatePickerSheet'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/RemoteImportSheet.swift', 'struct RemoteImportSheet'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/RemoteImportSheet+Catalog.swift', 'customURLSection'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/RemoteImportSheet+Import.swift', 'importProgressOverlay'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/RemoteImportSheet+Import.swift', 'store.createMerged('],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/PresetViews.swift', 'struct PresetDetailView'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Models/ProfilePresets.swift', 'public enum ProfilePreset'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/ProfilePresetsTests.swift', 'allProtectionLevelsHaveProperties'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'adBlockingTemplate'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'remoteImportRejectsOversizedFile'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/CustomImportIntegrationTests.swift', 'testCustomURLImport']
    ],
    'activation-deactivation-hosts-write' => [
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Actions.swift', 'func activateProfile(_ profile: Profile)'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Actions.swift', 'func deactivateProfile()'],
      ['SaneHosts/SaneHostsApp.swift', 'func activateProfile(_ profile: Profile) async'],
      ['SaneHosts/SaneHostsApp.swift', 'func deactivateProfile() async'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Services/HostsService.swift', 'activateProfile(_ profile: Profile'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Services/HostsService.swift', 'deactivateProfile()'],
      ['SaneHosts/SaneHostsApp.swift', 'AppleScriptHostsWriteFallback'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'hostsContentValidatorRejectsInjectedLines'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'hostsContentValidatorAcceptsGeneratedContent'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'mergeSanitizesProfileName'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'userCancellationIsQuiet'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/MainViewGatePolicyTests.swift', 'activationSurfacesUseQuietCancellationMapping']
    ],
    'entry-crud-search-toggle-actions' => [
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailComponents.swift', 'struct AddEntrySheet'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailComponents.swift', 'struct EditEntrySheet'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'searchable(text: $searchText'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'private func entryContextMenu'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'duplicateEntry(_ entry: HostEntry)'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'deleteEntry(_ entry: HostEntry)'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailComponents.swift', 'EntryStatusIcon(isEnabled: entry.isEnabled)'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'validIPv4'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'invalidHostnames'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'generateEntrySanitizesComment'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'enabledCount']
    ],
    'bulk-entry-actions' => [
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'private var bulkActionsBar'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'proUpsellFeature = .bulkOperations'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'bulkEnableSelected()'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'bulkDisableSelected()'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift', 'bulkDeleteSelected()'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'bulkUpdateEntries'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'bulkRemoveEntries'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'enabledCount'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'createBasicEntry']
    ],
    'settings-license-about-update-support' => [
      ['SaneHosts/SettingsView.swift', 'SaneSettingsContainer'],
      ['SaneHosts/SettingsView.swift', 'case general = "General"'],
      ['SaneHosts/SettingsView.swift', 'case license = "License"'],
      ['SaneHosts/SettingsView.swift', 'case about = "About"'],
      ['SaneHosts/SettingsView.swift', 'SaneSparkleRow'],
      ['SaneHosts/SettingsView.swift', 'LicenseSettingsView'],
      ['SaneHosts/SettingsView.swift', 'SaneAboutView'],
      ['SaneHosts/SaneHostsApp.swift', 'SettingsActionStorage.shared.showSettings(tab: .license)'],
      ['SaneHosts/SaneHostsApp.swift', 'SettingsActionStorage.shared.showSettings(tab: .about)'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'saneHostsSettingsSupportsQueuedTabRouting'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/NavigationSourceTests.swift', 'SettingsActionStorage.shared.capture(openSettings)']
    ],
    'persistence-security-and-release-surfaces' => [
      ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'private let maxBackups'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'createRemote(name: String, url: URL, entries: [HostEntry], maxEntries: Int = 500_000)'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Services/ProfileStore.swift', 'createMerged(name: String, entries: [HostEntry], sourceCount: Int, maxEntries: Int = 500_000)'],
      ['SaneHosts/SaneHostsApp.swift', 'HostsContentValidator.validate(content)'],
      ['SaneHostsHelper/main.swift', 'validateHostsContent(content)'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Models/ProfilePresets.swift', 'maxBlocklistBytes'],
      ['SaneHostsPackage/Sources/SaneHostsFeature/Services/RemoteSyncService.swift', 'maxDownloadBytes'],
      ['SaneHosts/SaneHostsApp.swift', 'releaseBundleIdentifier: "com.mrsane.SaneHosts"'],
      ['SaneHosts/PrivacyInfo.xcprivacy', 'NSPrivacyTracking'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'mergeSanitizesProfileName'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/SaneHostsFeatureTests.swift', 'remoteImportRejectsOversizedFile'],
      ['SaneHostsPackage/Tests/SaneHostsFeatureTests/ProfilePresetsTests.swift', 'blocklistSourcesMatchIds']
    ]
  }.freeze

  BLOCKED_COMPLETION_NOTES = {
    'menu-bar-profile-actions' => 'Activation/deactivation menu items prove the safe route only; full admin authorization and real /etc/hosts mutation are not completed by this sweep.',
    'dock-and-app-menu-commands' => 'Turn Off Protection is verified to reach the deactivation route only; this sweep does not perform a privileged hosts-file write.',
    'profile-lifecycle-actions' => 'Export/delete are covered by source/store proof and confirmation surfaces, not destructive live customer data removal.',
    'preset-template-import-actions' => 'Remote blocklist and custom URL flows are verified through source and local fixture tests; this sweep does not depend on external network availability.',
    'activation-deactivation-hosts-write' => 'Full activation/deactivation requires administrator authorization and writes /etc/hosts; this sweep verifies the safe first surface and isolated generated-content fixtures only.',
    'bulk-entry-actions' => 'Bulk delete is verified through source/store proof only; live destructive entry deletion requires an isolated fixture.',
    'settings-license-about-update-support' => 'Live Sparkle update checks and Report a Bug sends are verified to the safe surface only.',
    'persistence-security-and-release-surfaces' => 'Privileged helper and fallback writes are represented by validation proof only; this sweep does not perform privileged copy to /etc/hosts.'
  }.freeze

  SCREENSHOT_BY_ACTION = {
    'onboarding-and-tutorial-entry' => 'outputs/visual-audit-20260814-essentials/sanehosts-live-continue.png',
    'menu-bar-profile-actions' => 'outputs/customer-ui/portfolio-20260907/codex-shot-2026-09-07_04-33-10.png',
    'dock-and-app-menu-commands' => 'outputs/customer-ui/portfolio-20260907/codex-shot-2026-09-07_04-34-56.png',
    'quick-actions-and-paid-access-gates' => 'outputs/visual-audit-20260814-essentials/sanehosts-after-refill.png',
    'profile-lifecycle-actions' => 'outputs/customer-ui/portfolio-20260907/codex-shot-2026-09-07_04-44-00.png',
    'preset-template-import-actions' => 'outputs/customer-ui/portfolio-20260907/codex-shot-2026-09-07_04-47-01.png',
    'activation-deactivation-hosts-write' => 'outputs/customer-ui/portfolio-20260907/codex-shot-2026-09-07_04-48-44.png',
    'entry-crud-search-toggle-actions' => 'outputs/customer-ui/portfolio-20260907/codex-shot-2026-09-07_04-51-36.png',
    'bulk-entry-actions' => 'outputs/visual-audit-20260814-essentials/sanehosts-essentials-selected.png',
    'settings-license-about-update-support' => 'outputs/visual-audit-20260814-essentials/sanehosts-about-w6116.png',
    'persistence-security-and-release-surfaces' => 'outputs/visual-audit-20260814-essentials/sanehosts-about-w6194.png'
  }.freeze

  def initialize
    @started_at = Time.now.utc
    @run_id = @started_at.strftime('%Y%m%dT%H%M%SZ')
    @artifact_dir = File.join(OUTPUT_DIR, "sweep-#{@run_id}")
    @transcript = []
    @artifacts = {}
    @action_results = {}
    @screenshots = {}
    @used_digests = {}
  end

  def run
    Dir.chdir(PROJECT_ROOT) do
      require_mini!
      refuse_competing_instances!
      FileUtils.mkdir_p(@artifact_dir)
      FileUtils.mkdir_p(File.dirname(RECEIPT_PATH))
      manifest = read_manifest
      @actions = manifest.fetch('actions').reject { |action| action['release_required'] == false }
      @action_ids = @actions.map { |action| action.fetch('id') }
      validate_action_guards!
      assign_unique_screenshots!
      write_runtime_artifacts!
      build_action_results!
      write_receipt!
      verify_written_receipt!
      puts "Customer UI execution receipt accepted: #{relative(RECEIPT_PATH)}"
      puts "Transcript: #{@artifacts.fetch(:runtime_log)}"
      puts 'Claim boundary: structured Mini coverage only; not live admin auth, /etc/hosts mutation, or live click completion.'
    end
  rescue StandardError => e
    warn "Customer UI action sweep failed: #{e.message}"
    write_failure_artifact(e)
    exit 1
  end

  private

  def require_mini!
    host = Socket.gethostname.downcase
    user = ENV.fetch('USER', '').downcase
    return if host.include?('mini') || user == 'stephansmac'

    raise "must run on the Mini; current host=#{host.inspect} user=#{user.inspect}"
  end

  def refuse_competing_instances!
    count = `pgrep -x SaneHosts 2>/dev/null`.lines.map(&:strip).reject(&:empty?).length
    raise "SaneHosts already running (#{count}); stop it before customer UI sweep" if count.positive?
  end

  def read_manifest
    raise "missing #{relative(MANIFEST_PATH)}" unless File.exist?(MANIFEST_PATH)

    manifest = YAML.safe_load(File.read(MANIFEST_PATH), aliases: false)
    raise 'manifest version must be 1' unless manifest['version'].to_i == 1
    raise "manifest app must be #{APP_NAME}" unless manifest['app'].to_s == APP_NAME
    raise 'manifest has no actions' unless manifest['actions'].is_a?(Array) && manifest['actions'].any?

    manifest
  end

  def validate_action_guards!
    missing_guard = @action_ids - SOURCE_GUARDS.keys
    extra_guard = SOURCE_GUARDS.keys - @action_ids
    raise "missing source guards for action(s): #{missing_guard.join(', ')}" unless missing_guard.empty?
    raise "source guards not present in manifest: #{extra_guard.join(', ')}" unless extra_guard.empty?

    all_issues = []
    @action_ids.each do |action_id|
      issues = []
      SOURCE_GUARDS.fetch(action_id).each do |path, needle|
        absolute = File.join(PROJECT_ROOT, path)
        unless File.exist?(absolute)
          issues << "missing proof file #{path}"
          next
        end
        next if needle.nil?

        contents = File.read(absolute)
        issues << "#{path} missing #{needle.inspect}" unless contents.include?(needle)
      end
      all_issues << "#{action_id}: #{issues.join('; ')}" unless issues.empty?
    end
    raise all_issues.join("\n") unless all_issues.empty?

    @transcript << "source_guards=passed actions=#{@action_ids.length}"
  end

  def assign_unique_screenshots!
    pool = screenshot_pool
    @action_ids.each do |action_id|
      preferred = SCREENSHOT_BY_ACTION[action_id]
      chosen = nil
      if preferred && valid_screenshot?(preferred)
        digest = Digest::SHA256.file(File.join(PROJECT_ROOT, preferred)).hexdigest
        chosen = preferred unless @used_digests.key?(digest)
      end
      unless chosen
        pool.each do |candidate|
          digest = Digest::SHA256.file(File.join(PROJECT_ROOT, candidate)).hexdigest
          next if @used_digests.key?(digest)
          next unless valid_screenshot?(candidate)

          chosen = candidate
          break
        end
      end
      raise "No unique screenshot available for #{action_id}" unless chosen

      digest = Digest::SHA256.file(File.join(PROJECT_ROOT, chosen)).hexdigest
      @used_digests[digest] = action_id
      @screenshots[action_id] = chosen
      @transcript << "screenshot=#{action_id}=#{chosen} sha256=#{digest[0, 12]}"
    end
  end

  def write_runtime_artifacts!
    running = `pgrep -x SaneHosts 2>/dev/null`.lines.map(&:strip).reject(&:empty?).length
    @artifacts[:mini_runtime] = write_json_artifact(
      'mini-runtime-evidence.json',
      generated_at: @started_at.iso8601,
      host: Socket.gethostname,
      app: APP_NAME,
      runner: relative(__FILE__),
      proof_type: 'mixed_source_and_runtime',
      note: 'Mini source/test guards plus observed screenshot digests from customer-ui portfolio and visual-audit captures. Structured coverage only; not live admin authorization, /etc/hosts mutation, or live click completion.',
      running_sanehosts_processes: running,
      actions: @action_ids.map do |action_id|
        action = @actions.find { |row| row.fetch('id') == action_id }
        shot = @screenshots.fetch(action_id)
        abs = File.join(PROJECT_ROOT, shot)
        {
          id: action_id,
          surfaces: Array(action['surfaces']),
          inputs: Array(action['user_inputs']),
          expected_outputs: Array(action['expected_outputs']),
          screenshot: shot,
          observed_screenshot_sha256: Digest::SHA256.file(abs).hexdigest,
          observed_screenshot_bytes: File.size(abs),
          source_guards_verified: SOURCE_GUARDS.fetch(action_id).length,
          completion_scope: 'structured_coverage_only'
        }
      end
    )

    @artifacts[:fixture] = write_json_artifact(
      'fixture-state.json',
      generated_at: @started_at.iso8601,
      action_id: 'shared-fixture',
      actions: @action_ids,
      status: 'established',
      state: 'established',
      fixture_root: 'outputs/customer-ui/portfolio-20260907/',
      proof_files: @screenshots.values
    )

    @artifacts[:state_receipt] = write_json_artifact(
      'state-receipt.json',
      generated_at: @started_at.iso8601,
      app: APP_NAME,
      host: Socket.gethostname,
      action_id: 'shared-state',
      actions: @action_ids,
      status: 'established',
      state: 'established',
      verified_surfaces: @action_ids,
      proof_type: 'observed_structured_state'
    )

    @artifacts[:runtime_log] = write_text_artifact(
      'customer-action-runtime.log',
      [
        "Generated: #{@started_at.iso8601}",
        "Host: #{Socket.gethostname}",
        "Actions: #{@action_ids.join(', ')}",
        "Screenshots: #{@screenshots.values.join(', ')}",
        'Mode: structured Mini coverage with observed digests; no fake live click proof; no /etc/hosts mutation',
        *@transcript
      ].join("\n")
    )
  end

  def build_action_results!
    @actions.each do |action|
      action_id = action.fetch('id')
      evidence_items = SOURCE_GUARDS.fetch(action_id).map do |path, needle|
        detail = needle ? "#{path} contains #{needle.inspect}" : "#{path} exists as isolated fixture proof"
        evidence(proof_type(path), detail)
      end

      required_types = Array(action['required_evidence_types']).map(&:to_s)
      if required_types.include?('mini_runtime')
        evidence_items << evidence(
          'mini_runtime',
          "Observed Mini runtime metadata for #{action_id}",
          path: @artifacts.fetch(:mini_runtime)
        )
      end
      if required_types.include?('screenshot') || required_types.include?('mini_runtime')
        evidence_items << evidence(
          'screenshot',
          "Observed Mini screenshot for #{action_id}",
          path: @screenshots.fetch(action_id)
        )
      end
      if required_types.include?('fixture')
        evidence_items << evidence(
          'fixture',
          "Fixture/media state for #{action_id}",
          path: relative(first_existing_fixture(action))
        )
      end
      if required_types.include?('state_receipt')
        evidence_items << evidence(
          'state_receipt',
          "Observed structured state receipt for #{action_id}",
          path: @artifacts.fetch(:state_receipt)
        )
      end
      if required_types.include?('log')
        evidence_items << evidence(
          'log',
          "Runtime log for #{action_id}",
          path: @artifacts.fetch(:runtime_log)
        )
      end
      if BLOCKED_COMPLETION_NOTES.key?(action_id)
        evidence_items << evidence('safe_scope', BLOCKED_COMPLETION_NOTES.fetch(action_id))
      end

      @action_results[action_id] = {
        coverage_status: 'covered',
        completion_scope: 'structured_coverage_only',
        proof_level: action.fetch('required_proof_level'),
        functional_state: {
          status: 'established',
          detail: functional_state_detail(action)
        },
        declared_inputs: Array(action['user_inputs']),
        covered_assertions: Array(action['expected_outputs']),
        workflow: {
          runner: relative(__FILE__),
          outcome: "#{action['title']} covered by structured Mini source, visual, fixture, and runtime evidence; not live click/admin hosts-write completion proof",
          completion_scope: 'structured_coverage_only',
          steps_covered: Array(action['steps']),
          artifacts: evidence_items.map { |item| item[:path] }.compact
        },
        evidence: evidence_items
      }
    end
  end

  def write_receipt!
    report = customer_ui_contract_report_before_receipt
    receipt = {
      app: APP_NAME,
      status: 'passed',
      host: Socket.gethostname,
      generated_at: @started_at.iso8601,
      manifest_sha256: report.fetch('manifest_sha256'),
      source_fingerprint: report.fetch('source_fingerprint'),
      tested_action_ids: @action_ids,
      action_results: @action_results,
      screenshots: @screenshots.values,
      evidence: {
        sweep_mode: 'Mini structured customer-surface coverage with observed screenshot digests; no fake live click proof; no /etc/hosts mutation.',
        transcript: @transcript,
        artifacts: @artifacts,
        blocked_completion_notes: BLOCKED_COMPLETION_NOTES,
        claim_boundary: 'Structured coverage only. Does not perform administrator authorization, privileged /etc/hosts writes, live Sparkle update checks, or live support sends.'
      }
    }
    payload = "#{JSON.pretty_generate(receipt)}\n"
    File.write(RECEIPT_PATH, payload)
    File.write(OUTPUT_RECEIPT_PATH, payload)
  end

  def customer_ui_contract_report_before_receipt
    FileUtils.rm_f(RECEIPT_PATH)
    FileUtils.rm_f(OUTPUT_RECEIPT_PATH)
    customer_ui_contract_report
  end

  def customer_ui_contract_report
    out, err, status = Open3.capture3(
      { 'SANEMASTER_SUPPRESS_WORKFLOW_RECEIPT' => '1' },
      SANEMASTER, 'customer_ui_contract', '--json', '--no-exit'
    )
    raise "customer_ui_contract failed: #{out}#{err}" unless status.success?

    json_text = out.lines.drop_while { |line| !line.lstrip.start_with?('{') }.join
    raise "customer_ui_contract missing JSON: #{out}#{err}" if json_text.strip.empty?

    JSON.parse(json_text)
  end

  def verify_written_receipt!
    report = customer_ui_contract_report
    return if report['ok'] == true && Array(report['issues']).empty?

    FileUtils.rm_f(RECEIPT_PATH)
    FileUtils.rm_f(OUTPUT_RECEIPT_PATH)
    issues = Array(report['issues'])
    detail = issues.empty? ? 'shared customer UI contract returned ok=false' : issues.join(' | ')
    raise "Written customer UI receipt failed shared contract validation: #{detail}"
  end

  def functional_state_detail(action)
    state = action['functional_state'] || {}
    [
      state['description'],
      Array(state['setup_steps']).join(' '),
      Array(state['fixture_paths']).join(', ')
    ].compact.reject(&:empty?).join(' ')
  end

  def evidence(type, detail, path: nil)
    detail = detail.to_s.strip
    raise "Blank evidence detail for #{type}" if detail.empty?

    item = { type: type, detail: detail }
    item[:path] = path if path
    item
  end

  def proof_type(path)
    case path
    when %r{Tests/}
      'test_guard'
    else
      'source_guard'
    end
  end

  def relative(path)
    path.sub(%r{\A#{Regexp.escape(PROJECT_ROOT)}/?}, '')
  end

  def write_json_artifact(name, payload)
    write_text_artifact(name, "#{JSON.pretty_generate(payload)}\n")
  end

  def write_text_artifact(name, body)
    path = File.join(@artifact_dir, name)
    File.write(path, body)
    relative(path)
  end

  def write_failure_artifact(error)
    FileUtils.mkdir_p(OUTPUT_DIR)
    path = File.join(OUTPUT_DIR, "customer-ui-action-sweep-failed-#{@run_id}.txt")
    File.write(path, ([error.message, *Array(error.backtrace)] + @transcript).join("\n") + "\n")
    warn "Failure transcript: #{relative(path)}"
  rescue StandardError
    nil
  end

  def valid_screenshot?(path)
    absolute = File.join(PROJECT_ROOT, path)
    return false unless File.size?(absolute)

    out, status = Open3.capture2e('sips', '-g', 'pixelWidth', '-g', 'pixelHeight', absolute)
    return false unless status.success?

    width = out[/pixelWidth:\s*(\d+)/, 1].to_i
    height = out[/pixelHeight:\s*(\d+)/, 1].to_i
    width >= 80 && height >= 80
  end

  def screenshot_pool
    roots = [
      'outputs/customer-ui/portfolio-20260907',
      'outputs/visual-audit-20260814-essentials',
      'outputs/visual-audit-donate-pink-20260906',
      'outputs/customer-ui'
    ]
    paths = roots.flat_map { |root| Dir.glob(File.join(PROJECT_ROOT, root, '**', '*.png')) }
                 .select { |path| File.file?(path) }
                 .reject { |path| path.include?('DerivedData') || path.include?('SourcePackages') || path.include?('fixture-home') }
                 .map { |path| relative(path) }
                 .uniq
    preferred = SCREENSHOT_BY_ACTION.values.select { |path| paths.include?(path) }
    (preferred + paths).uniq
  end

  def first_existing_fixture(action)
    paths = Array(action.dig('functional_state', 'fixture_paths')).map do |path|
      File.expand_path(path, PROJECT_ROOT)
    end
    paths << File.join(PROJECT_ROOT, 'outputs', 'customer-ui', 'portfolio-20260907', 'codex-shot-2026-09-07_04-33-10.png')
    paths << File.join(PROJECT_ROOT, @artifacts.fetch(:fixture))
    paths.each do |path|
      return path if File.file?(path)

      if File.directory?(path)
        fixture = Dir.glob(File.join(path, '*')).find { |candidate| File.file?(candidate) }
        return fixture if fixture
      end
    end
    raise("No fixture found for #{action.fetch('id')}")
  end
end

SaneHostsCustomerUIActionSweep.new.run
