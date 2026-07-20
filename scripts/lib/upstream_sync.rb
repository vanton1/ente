# frozen_string_literal: true

require "json"
require "open3"
require "pathname"

module EnteUpstreamSync
  EXIT_NOT_READY = 2
  EXIT_USAGE = 64
  EXIT_COMMAND_FAILED = 70

  CommandResult = Struct.new(:stdout, :stderr, :status, keyword_init: true) do
    def success?
      status.zero?
    end
  end

  class CommandFailure < StandardError
    attr_reader :argv, :result

    def initialize(argv, result)
      @argv = argv
      @result = result
      detail = result.stderr.strip
      detail = result.stdout.strip if detail.empty?
      super("Command failed (#{argv.join(" ")}): #{detail}")
    end
  end

  class Runner
    def initialize(root:, env: {})
      @root = Pathname(root).expand_path
      @env = env
    end

    def capture(*argv)
      stdout, stderr, status = Open3.capture3(
        @env,
        *argv,
        chdir: @root.to_s,
      )
      CommandResult.new(stdout: stdout, stderr: stderr, status: status.exitstatus)
    end

    def run(*argv)
      result = capture(*argv)
      raise CommandFailure.new(argv, result) unless result.success?

      result.stdout.strip
    end
  end

  module GitHubRepository
    module_function

    def slug(url)
      value = url.to_s.strip
      return nil if value.empty?

      match = value.match(%r{\Ahttps?://github\.com/([^/]+/[^/]+?)(?:\.git)?/?\z}i)
      match ||= value.match(%r{\Agit@github\.com:([^/]+/[^/]+?)(?:\.git)?\z}i)
      match ||= value.match(%r{\Assh://git@github\.com/([^/]+/[^/]+?)(?:\.git)?/?\z}i)
      match && match[1].sub(/\.git\z/i, "").downcase
    end
  end

  CheckReport = Struct.new(
    :repository_root,
    :branch,
    :base_branch,
    :origin_fetch_url,
    :origin_push_url,
    :upstream_fetch_url,
    :upstream_push_url,
    :local_base_sha,
    :fork_sha,
    :official_sha,
    :merge_base_sha,
    :fork_only_commits,
    :upstream_only_commits,
    :official_contained,
    :fetched,
    :problems,
    keyword_init: true,
  ) do
    def ready?
      problems.empty?
    end

    def sync_required?
      ready? && upstream_only_commits.to_i.positive?
    end

    def to_h
      {
        schemaVersion: 1,
        ready: ready?,
        syncRequired: sync_required?,
        fetched: fetched,
        repositoryRoot: repository_root,
        branch: branch,
        baseBranch: base_branch,
        remotes: {
          origin: { fetch: origin_fetch_url, push: origin_push_url },
          upstream: { fetch: upstream_fetch_url, push: upstream_push_url },
        },
        commits: {
          localBase: local_base_sha,
          fork: fork_sha,
          official: official_sha,
          mergeBase: merge_base_sha,
          forkOnly: fork_only_commits,
          upstreamOnly: upstream_only_commits,
          officialContained: official_contained,
        },
        problems: problems,
      }
    end
  end

  class Inspector
    DEFAULT_ORIGIN = "origin"
    DEFAULT_UPSTREAM = "upstream"
    DEFAULT_BASE_BRANCH = "main"
    DEFAULT_FORK_REPOSITORY = "vanton1/ente"
    DEFAULT_OFFICIAL_REPOSITORY = "ente/ente"
    DISABLED_PUSH_URL = "DISABLED"

    def initialize(
      runner:,
      root:,
      origin: DEFAULT_ORIGIN,
      upstream: DEFAULT_UPSTREAM,
      base_branch: DEFAULT_BASE_BRANCH,
      fork_repository: DEFAULT_FORK_REPOSITORY,
      official_repository: DEFAULT_OFFICIAL_REPOSITORY
    )
      @runner = runner
      @root = Pathname(root).expand_path
      @origin = origin
      @upstream = upstream
      @base_branch = base_branch
      @fork_repository = fork_repository.downcase
      @official_repository = official_repository.downcase
    end

    def check(fetch: true)
      problems = []
      branch = command_value(problems, "read current branch") do
        @runner.run("git", "symbolic-ref", "--quiet", "--short", "HEAD")
      end
      status = command_value(problems, "read worktree status") do
        @runner.run("git", "status", "--porcelain", "--untracked-files=all")
      end

      problems << "Run from #{@base_branch}; current branch is #{branch}." if branch && branch != @base_branch
      problems << "Working tree is not clean." unless status.nil? || status.empty?

      origin_fetch_url = remote_url(problems, @origin, push: false)
      origin_push_url = remote_url(problems, @origin, push: true)
      upstream_fetch_url = remote_url(problems, @upstream, push: false)
      upstream_push_url = remote_url(problems, @upstream, push: true)

      validate_remote(
        problems,
        name: @origin,
        direction: "fetch",
        url: origin_fetch_url,
        expected_slug: @fork_repository,
      )
      validate_remote(
        problems,
        name: @origin,
        direction: "push",
        url: origin_push_url,
        expected_slug: @fork_repository,
      )
      validate_remote(
        problems,
        name: @upstream,
        direction: "fetch",
        url: upstream_fetch_url,
        expected_slug: @official_repository,
      )
      if upstream_push_url && upstream_push_url != DISABLED_PUSH_URL
        problems << "#{@upstream} push URL must be #{DISABLED_PUSH_URL}, found #{upstream_push_url}."
      end

      remote_safe = problems.none? { |problem| problem.include?(" URL ") || problem.include?("remote") }
      fetched = false
      if fetch && remote_safe
        command_value(problems, "fetch #{@origin}/#{@base_branch}") do
          @runner.run("git", "fetch", @origin, @base_branch, "--prune")
        end
        command_value(problems, "fetch #{@upstream}/#{@base_branch}") do
          @runner.run("git", "fetch", @upstream, @base_branch)
        end
        fetched = problems.none? { |problem| problem.start_with?("Unable to fetch ") }
      end

      local_base_sha = revision(problems, @base_branch)
      fork_sha = revision(problems, "#{@origin}/#{@base_branch}")
      official_sha = revision(problems, "#{@upstream}/#{@base_branch}")

      if local_base_sha && fork_sha && local_base_sha != fork_sha
        problems << "Local #{@base_branch} does not match #{@origin}/#{@base_branch}."
      end

      merge_base_sha = nil
      fork_only_commits = nil
      upstream_only_commits = nil
      official_contained = nil

      if fork_sha && official_sha
        merge_base_sha = command_value(problems, "calculate merge base") do
          @runner.run("git", "merge-base", fork_sha, official_sha)
        end
        counts = command_value(problems, "calculate divergence") do
          @runner.run("git", "rev-list", "--left-right", "--count", "#{fork_sha}...#{official_sha}")
        end
        if counts
          values = counts.split.map { |value| Integer(value, 10) }
          if values.length == 2
            fork_only_commits, upstream_only_commits = values
          else
            problems << "Git returned an invalid divergence count: #{counts}."
          end
        end

        ancestor = @runner.capture("git", "merge-base", "--is-ancestor", official_sha, fork_sha)
        if ancestor.status == 0
          official_contained = true
        elsif ancestor.status == 1
          official_contained = false
        else
          problems << "Unable to determine whether official history is already contained."
        end
      end

      CheckReport.new(
        repository_root: @root.to_s,
        branch: branch,
        base_branch: @base_branch,
        origin_fetch_url: origin_fetch_url,
        origin_push_url: origin_push_url,
        upstream_fetch_url: upstream_fetch_url,
        upstream_push_url: upstream_push_url,
        local_base_sha: local_base_sha,
        fork_sha: fork_sha,
        official_sha: official_sha,
        merge_base_sha: merge_base_sha,
        fork_only_commits: fork_only_commits,
        upstream_only_commits: upstream_only_commits,
        official_contained: official_contained,
        fetched: fetched,
        problems: problems.uniq,
      )
    rescue ArgumentError => error
      problems << "Unable to parse Git output: #{error.message}."
      CheckReport.new(
        repository_root: @root.to_s,
        branch: branch,
        base_branch: @base_branch,
        fetched: fetched,
        problems: problems.uniq,
      )
    end

    private

    def command_value(problems, description)
      yield
    rescue CommandFailure => error
      detail = error.result.stderr.strip
      detail = error.result.stdout.strip if detail.empty?
      problems << "Unable to #{description}: #{detail}."
      nil
    end

    def remote_url(problems, remote, push:)
      args = ["git", "remote", "get-url"]
      args << "--push" if push
      args << remote
      command_value(problems, "read #{remote} #{push ? "push" : "fetch"} URL") do
        @runner.run(*args)
      end
    end

    def validate_remote(problems, name:, direction:, url:, expected_slug:)
      return unless url

      actual_slug = GitHubRepository.slug(url)
      if actual_slug != expected_slug
        problems << "#{name} #{direction} URL must identify #{expected_slug}, found #{url}."
      end
    end

    def revision(problems, ref)
      command_value(problems, "resolve #{ref}") do
        @runner.run("git", "rev-parse", "--verify", "#{ref}^{commit}")
      end
    end
  end

  module TextReport
    module_function

    def render(report)
      lines = []
      lines << "Upstream synchronization readiness"
      lines << "Repository: #{report.repository_root}"
      lines << "Branch: #{report.branch || "unknown"} (required: #{report.base_branch})"
      lines << "Fetch performed: #{report.fetched ? "yes" : "no"}"
      lines << "Fork SHA: #{report.fork_sha || "unavailable"}"
      lines << "Official SHA: #{report.official_sha || "unavailable"}"
      lines << "Merge base: #{report.merge_base_sha || "unavailable"}"
      lines << "Divergence: #{report.fork_only_commits || "?"} fork-only, #{report.upstream_only_commits || "?"} upstream-only"
      lines << "Official contained: #{boolean_text(report.official_contained)}"
      lines << "Readiness: #{report.ready? ? "READY" : "NOT READY"}"
      if report.ready?
        lines << (report.sync_required? ? "Result: synchronization required" : "Result: already synchronized")
      else
        lines << "Problems:"
        report.problems.each { |problem| lines << "- #{problem}" }
      end
      lines.join("\n")
    end

    def boolean_text(value)
      return "yes" if value == true
      return "no" if value == false

      "unknown"
    end
  end
end
