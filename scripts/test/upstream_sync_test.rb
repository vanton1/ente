# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require_relative "../lib/upstream_sync"

class FakeRunner
  attr_reader :commands

  def initialize(results)
    @results = results
    @commands = []
  end

  def capture(*argv)
    @commands << argv
    value = @results.fetch(argv) { raise "Unexpected command: #{argv.inspect}" }
    value.is_a?(EnteUpstreamSync::CommandResult) ? value : result(value)
  end

  def run(*argv)
    response = capture(*argv)
    raise EnteUpstreamSync::CommandFailure.new(argv, response) unless response.success?

    response.stdout.strip
  end

  private

  def result(stdout, stderr: "", status: 0)
    EnteUpstreamSync::CommandResult.new(stdout: stdout, stderr: stderr, status: status)
  end
end

class GitHubRepositoryTest < Minitest::Test
  def test_extracts_slug_from_supported_git_urls
    assert_equal "vanton1/ente", EnteUpstreamSync::GitHubRepository.slug("https://github.com/vanton1/ente.git")
    assert_equal "vanton1/ente", EnteUpstreamSync::GitHubRepository.slug("git@github.com:vanton1/ente.git")
    assert_equal "ente/ente", EnteUpstreamSync::GitHubRepository.slug("ssh://git@github.com/ente/ente.git")
  end

  def test_rejects_non_github_urls
    assert_nil EnteUpstreamSync::GitHubRepository.slug("https://example.com/vanton1/ente.git")
    assert_nil EnteUpstreamSync::GitHubRepository.slug("DISABLED")
  end
end

class InspectorTest < Minitest::Test
  FORK_SHA = "1" * 40
  OFFICIAL_SHA = "2" * 40
  MERGE_BASE_SHA = "3" * 40

  def test_reports_ready_repository_and_upstream_drift_without_mutation
    runner = FakeRunner.new(healthy_results)
    report = inspector(runner).check(fetch: false)

    assert report.ready?
    assert report.sync_required?
    assert_equal 3, report.fork_only_commits
    assert_equal 5, report.upstream_only_commits
    refute report.official_contained
    refute report.fetched
    refute runner.commands.any? { |command| command[0, 2] == ["git", "fetch"] }
  end

  def test_dirty_worktree_is_not_ready
    results = healthy_results
    results[["git", "status", "--porcelain", "--untracked-files=all"]] = " M README.md\n"
    report = inspector(FakeRunner.new(results)).check(fetch: false)

    refute report.ready?
    assert_includes report.problems, "Working tree is not clean."
  end

  def test_unsafe_upstream_push_url_is_not_ready
    results = healthy_results
    results[["git", "remote", "get-url", "--push", "upstream"]] = "https://github.com/ente/ente.git\n"
    report = inspector(FakeRunner.new(results)).check(fetch: false)

    refute report.ready?
    assert report.problems.any? { |problem| problem.include?("upstream push URL must be DISABLED") }
  end

  private

  def inspector(runner)
    EnteUpstreamSync::Inspector.new(runner: runner, root: Pathname("/tmp/example"))
  end

  def healthy_results
    {
      ["git", "symbolic-ref", "--quiet", "--short", "HEAD"] => "main\n",
      ["git", "status", "--porcelain", "--untracked-files=all"] => "",
      ["git", "remote", "get-url", "origin"] => "https://github.com/vanton1/ente.git\n",
      ["git", "remote", "get-url", "--push", "origin"] => "git@github.com:vanton1/ente.git\n",
      ["git", "remote", "get-url", "upstream"] => "https://github.com/ente/ente.git\n",
      ["git", "remote", "get-url", "--push", "upstream"] => "DISABLED\n",
      ["git", "rev-parse", "--verify", "main^{commit}"] => "#{FORK_SHA}\n",
      ["git", "rev-parse", "--verify", "origin/main^{commit}"] => "#{FORK_SHA}\n",
      ["git", "rev-parse", "--verify", "upstream/main^{commit}"] => "#{OFFICIAL_SHA}\n",
      ["git", "merge-base", FORK_SHA, OFFICIAL_SHA] => "#{MERGE_BASE_SHA}\n",
      ["git", "rev-list", "--left-right", "--count", "#{FORK_SHA}...#{OFFICIAL_SHA}"] => "3\t5\n",
      ["git", "merge-base", "--is-ancestor", OFFICIAL_SHA, FORK_SHA] => EnteUpstreamSync::CommandResult.new(
        stdout: "",
        stderr: "",
        status: 1,
      ),
    }
  end
end
