# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "yaml"

class UpstreamSyncWorkflowContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  WORKFLOW_PATH = File.join(ROOT, ".github", "workflows", "upstream-sync-drift.yml")
  RECONCILER_PATH = File.join(ROOT, ".github", "scripts", "upstream-sync-issue.cjs")
  FULL_SHA_ACTION = %r{\A[^\s@]+@[0-9a-f]{40}\z}.freeze

  def setup
    @source = File.read(WORKFLOW_PATH)
    @workflow = YAML.safe_load(@source, aliases: true)
  end

  def test_trigger_and_permissions_are_minimal_and_fork_specific
    triggers = @workflow["on"] || @workflow[true]

    assert_equal ["schedule", "workflow_dispatch"], triggers.keys.sort
    assert_equal({ "contents" => "read", "issues" => "write" }, @workflow.fetch("permissions"))
    assert_equal "github.repository == 'vanton1/ente'", detect_job.fetch("if")
    assert_equal 10, detect_job.fetch("timeout-minutes")
  end

  def test_external_actions_are_sha_pinned_and_checkout_drops_credentials
    action_steps = steps.select { |step| step.key?("uses") }

    refute_empty action_steps
    action_steps.each { |step| assert_match FULL_SHA_ACTION, step.fetch("uses") }
    checkout = action_steps.find { |step| step.fetch("uses").start_with?("actions/checkout@") }
    assert_equal false, checkout.fetch("with").fetch("persist-credentials")
    assert_equal 0, checkout.fetch("with").fetch("fetch-depth")
  end

  def test_source_mutation_is_absent_and_official_push_is_disabled
    shell = steps.map { |step| step["run"] }.compact.join("\n")

    assert_includes shell, "git remote set-url --push upstream DISABLED"
    refute_match(/(^|\s)git\s+push(\s|$)/, shell)
    refute_includes @source, "pull-requests: write"
    refute_includes @source, "contents: write"
  end

  def test_workflow_and_local_publisher_share_one_marker
    reconciler = File.read(RECONCILER_PATH)

    assert_includes reconciler, '<!-- ente-upstream-sync -->'
    assert_includes reconciler, "refusing an ambiguous update"
    assert_includes @source, "upstream-sync-issue.cjs"
  end

  private

  def detect_job
    @workflow.fetch("jobs").fetch("detect")
  end

  def steps
    detect_job.fetch("steps")
  end
end

class UpstreamSyncDocumentationContractTest < Minitest::Test
  ROOT = Pathname(File.expand_path("../..", __dir__))
  DOCUMENTS = [
    ROOT.join("UPSTREAM_SYNC.md"),
    ROOT.join("mobile/apps/photos/SELF_HOSTED_DOCUMENTATION.md"),
    ROOT.join("living_docs/UpstreamEnteSynchronizationArchitecture.md"),
  ].freeze

  def test_local_links_in_current_sync_documents_resolve
    DOCUMENTS.each do |document|
      source = document.read
      source.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |target|
        path = target.split("#", 2).first
        next if path.empty? || path.match?(%r{\A[a-z]+://}i)

        assert document.dirname.join(path).cleanpath.exist?, "Broken link #{target} in #{document}"
      end
    end
  end

  def test_runbook_exposes_every_operator_state_and_hard_boundary
    source = ROOT.join("UPSTREAM_SYNC.md").read

    %w[check start resume validate publish run].each do |command|
      assert_includes source, "sync_upstream.sh #{command}"
    end
    assert_includes source, "never approves or merges"
    assert_includes source, "test_upstream_sync.sh"
    assert_includes source, "https://photos.example.com"
  end
end
