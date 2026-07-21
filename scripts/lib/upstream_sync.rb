# frozen_string_literal: true

require "json"
require "date"
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

  class SafetyFailure < StandardError; end

  class NotReady < SafetyFailure
    attr_reader :report

    def initialize(report)
      @report = report
      super("Repository is not ready for upstream synchronization.")
    end
  end

  class MergeStopped < SafetyFailure
    attr_reader :branch, :official_sha, :result, :conflicts

    def initialize(branch:, official_sha:, result:, conflicts:)
      @branch = branch
      @official_sha = official_sha
      @result = result
      @conflicts = conflicts
      super("Upstream merge stopped on #{branch}.")
    end
  end

  class Runner
    def initialize(root:, env: {})
      @root = Pathname(root).expand_path
      @env = env
    end

    def capture(*argv, chdir: @root, env: {})
      directory = Pathname(chdir).expand_path.to_s
      stdout, stderr, status = Open3.capture3(
        @env.merge(env).merge("PWD" => directory),
        *argv,
        chdir: directory,
      )
      CommandResult.new(stdout: stdout, stderr: stderr, status: status.exitstatus)
    end

    def run(*argv, chdir: @root, env: {})
      result = capture(*argv, chdir: chdir, env: env)
      raise CommandFailure.new(argv, result) unless result.success?

      result.stdout.strip
    end

    def execute(*argv, chdir: @root, env: {}, output: $stdout)
      recent = []
      status = nil
      directory = Pathname(chdir).expand_path.to_s
      Open3.popen2e(
        @env.merge(env).merge("PWD" => directory),
        *argv,
        chdir: directory,
      ) do |stdin, combined, wait_thread|
        stdin.close
        combined.each_line do |line|
          output.write(line)
          recent << line
          recent.shift while recent.length > 200
        end
        status = wait_thread.value.exitstatus
      end
      result = CommandResult.new(stdout: recent.join, stderr: "", status: status)
      raise CommandFailure.new(argv, result) unless result.success?

      result
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

  StartResult = Struct.new(
    :status,
    :branch,
    :fork_sha,
    :official_sha,
    :merge_commit,
    keyword_init: true,
  )

  IntegrationState = Struct.new(
    :merge_commit,
    :fork_parent,
    :official_sha,
    keyword_init: true,
  ) do
    MESSAGE_PATTERN = /\AMerge official Ente main at ([0-9a-f]{40})\z/.freeze

    def self.current(runner)
      history = runner.run(
        "git",
        "log",
        "--first-parent",
        "--merges",
        "-n",
        "50",
        "--format=%H%x09%P%x09%s",
      )
      history.each_line do |line|
        commit, raw_parents, subject = line.strip.split("\t", 3)
        match = subject&.match(MESSAGE_PATTERN)
        next unless match

        parents = raw_parents.to_s.split
        next unless parents.length == 2
        next unless parents[1] == match[1]

        return new(
          merge_commit: commit,
          fork_parent: parents[0],
          official_sha: match[1],
        )
      end
      raise SafetyFailure,
            "No verified 'Merge official Ente main at <SHA>' commit exists on the first-parent history."
    end
  end

  class Synchronizer
    BRANCH_PREFIX = "sync/upstream-"

    def initialize(runner:, inspector:, root:)
      @runner = runner
      @inspector = inspector
      @root = Pathname(root).expand_path
    end

    def start(fetch: true, expected_official_sha: nil, date: Date.today)
      report = @inspector.check(fetch: fetch)
      raise NotReady, report unless report.ready?

      unless report.sync_required?
        return StartResult.new(
          status: :already_synchronized,
          fork_sha: report.fork_sha,
          official_sha: report.official_sha,
        )
      end

      if expected_official_sha && expected_official_sha != report.official_sha
        raise SafetyFailure,
              "Requested official SHA #{expected_official_sha} does not match fetched upstream/#{report.base_branch} #{report.official_sha}."
      end

      branch = branch_name(date, report.official_sha)
      branch_ref = "refs/heads/#{branch}"
      branch_check = @runner.capture("git", "show-ref", "--verify", "--quiet", branch_ref)
      if branch_check.status.zero?
        raise SafetyFailure,
              "Integration branch #{branch} already exists. Inspect it and run resume instead of overwriting it."
      end
      unless branch_check.status == 1
        raise SafetyFailure, "Unable to determine whether #{branch} already exists."
      end

      @runner.run("git", "switch", "-c", branch, report.fork_sha)
      message = "Merge official Ente main at #{report.official_sha}"
      merge = @runner.capture(
        "git",
        "merge",
        "--no-ff",
        "--no-edit",
        "-m",
        message,
        report.official_sha,
      )
      unless merge.success?
        conflicts = lines(
          @runner.capture("git", "diff", "--name-only", "--diff-filter=U").stdout,
        )
        raise MergeStopped.new(
          branch: branch,
          official_sha: report.official_sha,
          result: merge,
          conflicts: conflicts,
        )
      end

      verify_official_ancestry(report.official_sha)
      StartResult.new(
        status: :merged,
        branch: branch,
        fork_sha: report.fork_sha,
        official_sha: report.official_sha,
        merge_commit: @runner.run("git", "rev-parse", "HEAD"),
      )
    end

    def resume
      branch = @runner.run("git", "symbolic-ref", "--quiet", "--short", "HEAD")
      unless branch.start_with?(BRANCH_PREFIX)
        raise SafetyFailure, "Resume requires a #{BRANCH_PREFIX}* branch; current branch is #{branch}."
      end

      merge_head = @runner.capture("git", "rev-parse", "--verify", "MERGE_HEAD^{commit}")
      if merge_head.success?
        official_sha = merge_head.stdout.strip
        conflicts = lines(
          @runner.capture("git", "diff", "--name-only", "--diff-filter=U").stdout,
        )
        unless conflicts.empty?
          raise SafetyFailure,
                "Merge still has unresolved files: #{conflicts.join(", ")}. Resolve and stage them before resume."
        end

        unstaged = @runner.capture("git", "diff", "--quiet")
        unless unstaged.status.zero?
          raise SafetyFailure, "Merge resolution has unstaged changes. Stage the complete resolution before resume."
        end
        cached = @runner.capture("git", "diff", "--cached", "--quiet")
        if cached.status.zero?
          raise SafetyFailure, "Merge resolution has no staged changes to commit."
        end

        @runner.run("git", "diff", "--check")
        @runner.run("git", "diff", "--cached", "--check")
        @runner.run("git", "commit", "--no-edit")
        verify_official_ancestry(official_sha)
        return StartResult.new(
          status: :merged,
          branch: branch,
          official_sha: official_sha,
          merge_commit: @runner.run("git", "rev-parse", "HEAD"),
        )
      end

      state = IntegrationState.current(@runner)
      verify_official_ancestry(state.official_sha)
      status = @runner.run("git", "status", "--porcelain", "--untracked-files=all")
      raise SafetyFailure, "Integration branch is not clean; inspect changes before validation." unless status.empty?

      StartResult.new(
        status: :ready_for_validation,
        branch: branch,
        official_sha: state.official_sha,
        merge_commit: @runner.run("git", "rev-parse", "HEAD"),
      )
    end

    private

    def branch_name(date, official_sha)
      "#{BRANCH_PREFIX}#{date.iso8601}-#{official_sha[0, 10]}"
    end

    def verify_official_ancestry(official_sha)
      result = @runner.capture("git", "merge-base", "--is-ancestor", official_sha, "HEAD")
      return if result.status.zero?

      raise SafetyFailure, "Merged branch does not contain recorded official SHA #{official_sha}."
    end

    def lines(value)
      value.lines.map(&:strip).reject(&:empty?)
    end
  end

  class ToolResolver
    def initialize(env: ENV)
      @env = env
    end

    def resolve(with_builds: false, with_github: false)
      flutter = executable("FLUTTER_BIN", ["flutter"])
      dart_candidates = []
      dart_candidates << File.join(File.dirname(flutter), "dart") if flutter
      dart_candidates << "dart"

      tools = {
        git: executable(nil, ["git"]),
        flutter: flutter,
        dart: executable("DART_BIN", dart_candidates),
        cargo: executable("CARGO_BIN", [File.join(home, ".cargo", "bin", "cargo"), "cargo"]),
        pod: executable("POD_BIN", ["pod"]),
      }
      tools[:gh] = executable("GH_BIN", ["gh"]) if with_github
      if with_builds
        tools[:java] = executable(nil, ["java"])
        tools[:xcodebuild] = executable(nil, ["xcodebuild"])
      end

      missing = tools.select { |_name, path| path.nil? }.keys
      unless missing.empty?
        raise SafetyFailure,
              "Required tools are unavailable: #{missing.join(", ")}. Configure the pinned toolchain before validation."
      end

      tools
    end

    private

    def executable(env_name, candidates)
      configured = env_name && @env[env_name]
      return expand_executable(configured) if configured && !configured.empty?

      candidates.each do |candidate|
        resolved = expand_executable(candidate)
        return resolved if resolved
      end
      nil
    end

    def expand_executable(value)
      return nil if value.nil? || value.empty?

      if value.include?(File::SEPARATOR)
        path = File.expand_path(value)
        return path if File.file?(path) && File.executable?(path)

        return nil
      end

      @env.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
        path = File.join(directory, value)
        return path if File.file?(path) && File.executable?(path)
      end
      nil
    end

    def home
      @env.fetch("HOME", Dir.home)
    end
  end

  ValidationResult = Struct.new(
    :branch,
    :commit,
    :official_sha,
    :with_builds,
    :steps,
    keyword_init: true,
  )

  class Validator
    PUBLIC_ENDPOINT = "https://photos.example.com"
    FOCUSED_TESTS = %w[
      test/core/network/endpoint_policy_test.dart
      test/core/network/endpoint_switcher_test.dart
      test/ui/settings/developer_settings_lock_test.dart
      test/ui/settings/server_settings_page_test.dart
      test/scripts/build_self_hosted_ios_adhoc_test.dart
      test/scripts/prepare_self_hosted_android_release_test.dart
      test/scripts/prepare_self_hosted_ios_release_test.dart
      test/scripts/publish_self_hosted_android_release_test.dart
      test/scripts/publish_self_hosted_ios_release_test.dart
      test/scripts/self_hosted_ios_identity_test.dart
    ].freeze
    ENDPOINT_TESTS = %w[
      test/core/network/endpoint_policy_test.dart
      test/core/network/endpoint_switcher_test.dart
      test/ui/settings/developer_settings_lock_test.dart
      test/ui/settings/server_settings_page_test.dart
    ].freeze

    def initialize(runner:, root:, tools:, output: $stdout)
      @runner = runner
      @root = Pathname(root).expand_path
      @mobile = @root.join("mobile")
      @photos = @mobile.join("apps", "photos")
      @rust = @root.join("rust")
      @tools = tools
      @output = output
      @steps = []
    end

    def validate(with_builds: false)
      branch = @runner.run("git", "symbolic-ref", "--quiet", "--short", "HEAD")
      unless branch.start_with?(Synchronizer::BRANCH_PREFIX)
        raise SafetyFailure,
              "Validation requires a #{Synchronizer::BRANCH_PREFIX}* branch; current branch is #{branch}."
      end
      merge_head = @runner.capture("git", "rev-parse", "--verify", "MERGE_HEAD")
      raise SafetyFailure, "Complete or abort the in-progress merge before validation." if merge_head.success?

      ensure_clean("before validation")
      state = IntegrationState.current(@runner)
      official_sha = state.official_sha
      verify_ancestor(official_sha)

      step("Initialize recursive submodules") do
        execute(@tools[:git], "submodule", "update", "--init", "--recursive")
      end
      ensure_clean("after submodule initialization")

      step("Restore locked Flutter workspace") do
        execute(@tools[:flutter], "pub", "get", "--enforce-lockfile", chdir: @mobile)
      end
      ensure_clean("after Flutter dependency restoration")

      step("Generate Rust bindings") do
        execute(@tools[:cargo], "codegen", "frb", chdir: @rust, env: rust_env)
      end
      ensure_clean("after first Rust binding generation")
      step("Verify Rust binding generation is stable") do
        execute(@tools[:cargo], "codegen", "frb", chdir: @rust, env: rust_env)
      end
      ensure_clean("after second Rust binding generation")

      step("Verify Photos CocoaPods lock") do
        execute(@tools[:pod], "install", "--deployment", chdir: @photos.join("ios"))
      end
      ensure_clean("after CocoaPods verification")

      step("Run combined self-hosted regression tests") do
        execute(@tools[:flutter], "test", "--no-pub", *FOCUSED_TESTS, chdir: @photos)
      end
      step("Run configurable endpoint tests") do
        execute(
          @tools[:flutter],
          "test",
          "--no-pub",
          "--dart-define=configurableEndpoint=true",
          "--dart-define=endpoint=#{PUBLIC_ENDPOINT}",
          *ENDPOINT_TESTS,
          chdir: @photos,
        )
      end
      step("Run locked endpoint compatibility tests") do
        execute(
          @tools[:flutter],
          "test",
          "--no-pub",
          "--dart-define=lockedEndpoint=true",
          "--dart-define=endpoint=#{PUBLIC_ENDPOINT}",
          *ENDPOINT_TESTS,
          chdir: @photos,
        )
      end

      step("Check formatting of tracked Dart sources") do
        tracked_dart_files.each_slice(200) do |files|
          execute(
            @tools[:dart],
            "format",
            "--output=none",
            "--set-exit-if-changed",
            *files,
          )
        end
      end
      ensure_clean("after formatting verification")

      step("Analyze complete mobile workspace") do
        execute(@tools[:flutter], "analyze", "--no-pub", chdir: @mobile)
      end

      if with_builds
        step("Build guarded Android debug APK") do
          execute(
            @photos.join("scripts", "build_self_hosted_android.sh").to_s,
            "--debug",
            chdir: @photos,
            env: build_env,
          )
        end
        ensure_clean("after Android debug build")
        step("Build guarded iOS Simulator app") do
          execute(
            @photos.join("scripts", "build_self_hosted_ios.sh").to_s,
            "--simulator",
            chdir: @photos,
            env: build_env,
          )
        end
        ensure_clean("after iOS Simulator build")
      end

      ensure_clean("after validation")
      ValidationResult.new(
        branch: branch,
        commit: @runner.run("git", "rev-parse", "HEAD"),
        official_sha: official_sha,
        with_builds: with_builds,
        steps: @steps.dup,
      )
    rescue CommandFailure => error
      raise SafetyFailure, "Validation command failed: #{error.message}"
    end

    private

    def step(name)
      @output.puts("\n==> #{name}")
      yield
      @steps << name
      @output.puts("Passed: #{name}")
    end

    def execute(*argv, chdir: @root, env: {})
      @runner.execute(*argv, chdir: chdir, env: env, output: @output)
    end

    def ensure_clean(context)
      status = @runner.run("git", "status", "--porcelain", "--untracked-files=all")
      return if status.empty?

      raise SafetyFailure,
            "Tracked or untracked source drift detected #{context}:\n#{status}\nInspect and commit intentional repairs before resuming."
    end

    def verify_ancestor(official_sha)
      result = @runner.capture("git", "merge-base", "--is-ancestor", official_sha, "HEAD")
      return if result.status.zero?

      raise SafetyFailure, "Validation branch does not contain official SHA #{official_sha}."
    end

    def tracked_dart_files
      raw = @runner.run("git", "ls-files", "-z", "*.dart")
      files = raw.split("\0").reject(&:empty?)
      raise SafetyFailure, "No tracked Dart files were found." if files.empty?

      files
    end

    def rust_env
      path = [File.dirname(@tools[:cargo]), ENV.fetch("PATH", "")].reject(&:empty?).join(File::PATH_SEPARATOR)
      { "PATH" => path }
    end

    def build_env
      {
        "ENTE_SELF_HOSTED_ENDPOINT" => PUBLIC_ENDPOINT,
        "FLUTTER_BIN" => @tools[:flutter],
        "DART_BIN" => @tools[:dart],
        "PATH" => [
          File.dirname(@tools[:cargo]),
          File.dirname(@tools[:flutter]),
          ENV.fetch("PATH", ""),
        ].reject(&:empty?).join(File::PATH_SEPARATOR),
      }
    end
  end

  module UpstreamIssue
    MARKER = "<!-- ente-upstream-sync -->"
  end

  PublicationResult = Struct.new(
    :status,
    :branch,
    :commit,
    :official_sha,
    :issue_number,
    :pull_request_number,
    :pull_request_url,
    keyword_init: true,
  )

  PublicationContext = Struct.new(
    :branch,
    :commit,
    :official_sha,
    :fork_sha,
    :issue,
    :remote_branch_sha,
    :pull_request,
    keyword_init: true,
  )

  class Publisher
    DEFAULT_REPOSITORY = Inspector::DEFAULT_FORK_REPOSITORY
    DEFAULT_ORIGIN = Inspector::DEFAULT_ORIGIN
    DEFAULT_UPSTREAM = Inspector::DEFAULT_UPSTREAM
    DEFAULT_BASE_BRANCH = Inspector::DEFAULT_BASE_BRANCH
    SHA_PATTERN = /\A[0-9a-f]{40}\z/.freeze

    def initialize(
      runner:,
      root:,
      tools:,
      input: $stdin,
      output: $stdout,
      repository: DEFAULT_REPOSITORY,
      origin: DEFAULT_ORIGIN,
      upstream: DEFAULT_UPSTREAM,
      base_branch: DEFAULT_BASE_BRANCH
    )
      @runner = runner
      @root = Pathname(root).expand_path
      @tools = tools
      @input = input
      @output = output
      @repository = repository.downcase
      @origin = origin
      @upstream = upstream
      @base_branch = base_branch
    end

    def publish(validation:, issue_number: nil)
      first = preflight(validation: validation, issue_number: issue_number)
      if first.pull_request
        return existing_pull_request_result(first)
      end

      print_confirmation(first, validation)
      answer = @input.gets&.strip
      unless answer == "PUSH #{first.branch}"
        raise SafetyFailure, "Confirmation did not match. Nothing was pushed and no pull request was created."
      end

      second = preflight(validation: validation, issue_number: issue_number)
      ensure_unchanged(first, second)
      if second.pull_request
        return existing_pull_request_result(second)
      end

      pushed = false
      unless second.remote_branch_sha == second.commit
        push_branch(second)
        pushed = true
      end
      verify_remote_branch(second.branch, second.commit)

      pull_request = create_pull_request(second, validation)
      PublicationResult.new(
        status: pushed ? :published : :pull_request_created,
        branch: second.branch,
        commit: second.commit,
        official_sha: second.official_sha,
        issue_number: second.issue && second.issue.fetch("number"),
        pull_request_number: pull_request.fetch("number"),
        pull_request_url: pull_request.fetch("url"),
      )
    rescue CommandFailure => error
      raise SafetyFailure, "Publication command failed: #{error.message}"
    end

    private

    def preflight(validation:, issue_number:)
      branch = @runner.run("git", "symbolic-ref", "--quiet", "--short", "HEAD")
      unless branch.start_with?(Synchronizer::BRANCH_PREFIX)
        raise SafetyFailure,
              "Publication requires a #{Synchronizer::BRANCH_PREFIX}* branch; current branch is #{branch}."
      end

      merge_head = @runner.capture("git", "rev-parse", "--verify", "MERGE_HEAD")
      raise SafetyFailure, "Complete or abort the in-progress merge before publication." if merge_head.success?

      status = @runner.run("git", "status", "--porcelain", "--untracked-files=all")
      raise SafetyFailure, "Publication branch is not clean." unless status.empty?

      commit = @runner.run("git", "rev-parse", "HEAD")
      unless validation.branch == branch && validation.commit == commit
        raise SafetyFailure,
              "Validation evidence does not match current branch and commit. Run validation again."
      end

      state = IntegrationState.current(@runner)
      unless validation.official_sha == state.official_sha
        raise SafetyFailure, "Validation evidence records a different official SHA. Run validation again."
      end

      validate_remotes
      @runner.run("git", "fetch", @origin, @base_branch, "--prune")
      fork_sha = @runner.run("git", "rev-parse", "--verify", "#{@origin}/#{@base_branch}^{commit}")
      unless fork_sha == state.fork_parent
        raise SafetyFailure,
              "#{@origin}/#{@base_branch} changed after integration began. Preserve this branch and start a new synchronization."
      end
      verify_ancestor(fork_sha, commit, "fork main")
      verify_ancestor(state.official_sha, commit, "official main")

      @runner.run(@tools.fetch(:gh), "auth", "status", "--hostname", "github.com")
      remote_branch_sha = remote_branch_sha(branch)
      if remote_branch_sha && remote_branch_sha != commit
        raise SafetyFailure,
              "Remote branch #{branch} exists at #{remote_branch_sha}, not validated commit #{commit}."
      end

      pull_requests = github_json(
        @tools.fetch(:gh),
        "pr",
        "list",
        "--repo",
        @repository,
        "--head",
        branch,
        "--state",
        "all",
        "--json",
        "number,state,url,headRefOid",
      )
      raise SafetyFailure, "GitHub returned multiple pull requests for #{branch}." if pull_requests.length > 1

      pull_request = pull_requests.first
      if pull_request
        unless pull_request.fetch("state") == "OPEN" && pull_request.fetch("headRefOid") == commit
          raise SafetyFailure,
                "A non-open or mismatched pull request already exists for #{branch}; use a new synchronization branch."
        end
        unless remote_branch_sha == commit
          raise SafetyFailure, "GitHub reports an open pull request but the fork branch is absent or mismatched."
        end
      end

      issue = resolve_issue(issue_number)
      PublicationContext.new(
        branch: branch,
        commit: commit,
        official_sha: state.official_sha,
        fork_sha: fork_sha,
        issue: issue,
        remote_branch_sha: remote_branch_sha,
        pull_request: pull_request,
      )
    end

    def validate_remotes
      origin_fetch = remote_urls(@origin, push: false)
      origin_push = remote_urls(@origin, push: true)
      upstream_fetch = remote_urls(@upstream, push: false)
      upstream_push = remote_urls(@upstream, push: true)

      validate_github_urls(@origin, "fetch", origin_fetch, @repository)
      validate_github_urls(@origin, "push", origin_push, @repository)
      validate_github_urls(@upstream, "fetch", upstream_fetch, Inspector::DEFAULT_OFFICIAL_REPOSITORY)
      unless upstream_push == [Inspector::DISABLED_PUSH_URL]
        raise SafetyFailure,
              "#{@upstream} push URLs must contain only #{Inspector::DISABLED_PUSH_URL}."
      end
    end

    def remote_urls(remote, push:)
      args = ["git", "remote", "get-url", "--all"]
      args << "--push" if push
      args << remote
      @runner.run(*args).lines.map(&:strip).reject(&:empty?)
    end

    def validate_github_urls(remote, direction, urls, expected)
      if urls.empty? || urls.any? { |url| GitHubRepository.slug(url) != expected }
        raise SafetyFailure,
              "Every #{remote} #{direction} URL must identify #{expected}; found #{urls.join(", ")}."
      end
    end

    def verify_ancestor(ancestor, descendant, label)
      result = @runner.capture("git", "merge-base", "--is-ancestor", ancestor, descendant)
      return if result.status.zero?

      raise SafetyFailure, "Validated commit does not contain #{label} SHA #{ancestor}."
    end

    def remote_branch_sha(branch)
      output = @runner.run("git", "ls-remote", "--heads", @origin, "refs/heads/#{branch}")
      return nil if output.empty?

      lines = output.lines.map(&:strip).reject(&:empty?)
      unless lines.length == 1
        raise SafetyFailure, "Unable to identify one exact remote branch for #{branch}."
      end
      sha, ref = lines.first.split(/\s+/, 2)
      unless sha&.match?(SHA_PATTERN) && ref == "refs/heads/#{branch}"
        raise SafetyFailure, "Git returned an invalid remote branch record for #{branch}."
      end
      sha
    end

    def verify_remote_branch(branch, expected_sha)
      actual_sha = remote_branch_sha(branch)
      return if actual_sha == expected_sha

      raise SafetyFailure,
            "Push verification failed: #{branch} is #{actual_sha || "absent"}, expected #{expected_sha}."
    end

    def resolve_issue(issue_number)
      if issue_number
        issue = github_json(
          @tools.fetch(:gh),
          "issue",
          "view",
          issue_number.to_s,
          "--repo",
          @repository,
          "--json",
          "number,title,body,url,state",
        )
        unless issue.fetch("state") == "OPEN" && issue.fetch("body").include?(UpstreamIssue::MARKER)
          raise SafetyFailure, "Issue ##{issue_number} is not the open upstream-drift tracking issue."
        end
        return issue
      end

      issues = github_json(
        @tools.fetch(:gh),
        "issue",
        "list",
        "--repo",
        @repository,
        "--state",
        "open",
        "--limit",
        "100",
        "--json",
        "number,title,body,url,state",
      ).select { |item| item.fetch("body").include?(UpstreamIssue::MARKER) }
      if issues.length > 1
        raise SafetyFailure, "Multiple open upstream-drift issues contain the automation marker."
      end
      issues.first
    end

    def github_json(*argv)
      raw = @runner.run(*argv)
      JSON.parse(raw)
    rescue JSON::ParserError => error
      raise SafetyFailure, "GitHub returned invalid JSON: #{error.message}"
    end

    def print_confirmation(context, validation)
      @output.puts("\nPublication is ready.")
      @output.puts("Fork repository: #{@repository}")
      @output.puts("Target: #{@base_branch}")
      @output.puts("Branch: #{context.branch}")
      @output.puts("Validated commit: #{context.commit}")
      @output.puts("Official SHA: #{context.official_sha}")
      @output.puts("Platform builds: #{validation.with_builds ? "passed" : "not requested"}")
      @output.puts("Tracking issue: #{context.issue ? "##{context.issue.fetch("number")}" : "none"}")
      @output.puts("Remote branch: #{context.remote_branch_sha ? "already uploaded at the validated commit" : "will be created"}")
      @output.puts("No command will merge the pull request.")
      @output.puts("Type exactly: PUSH #{context.branch}")
      @output.print("> ")
    end

    def ensure_unchanged(first, second)
      fields = %i[branch commit official_sha fork_sha remote_branch_sha]
      changed = fields.any? { |field| first.public_send(field) != second.public_send(field) }
      first_issue = first.issue && first.issue.fetch("number")
      second_issue = second.issue && second.issue.fetch("number")
      if changed || first_issue != second_issue
        raise SafetyFailure, "Repository or GitHub state changed during confirmation. Nothing was pushed."
      end
    end

    def push_branch(context)
      ssh_url = "git@github.com:#{@repository}.git"
      @runner.execute(
        @tools.fetch(:git),
        "push",
        ssh_url,
        "HEAD:refs/heads/#{context.branch}",
        chdir: @root,
        env: {},
        output: @output,
      )
      @runner.run("git", "fetch", @origin, context.branch)
      @runner.run("git", "branch", "--set-upstream-to=#{@origin}/#{context.branch}", context.branch)
    end

    def create_pull_request(context, validation)
      title = "Sync fork with official Ente #{context.official_sha[0, 10]}"
      body = pull_request_body(context, validation)
      url = @runner.run(
        @tools.fetch(:gh),
        "pr",
        "create",
        "--repo",
        @repository,
        "--base",
        @base_branch,
        "--head",
        context.branch,
        "--title",
        title,
        "--body",
        body,
      ).lines.map(&:strip).find { |line| line.start_with?("https://github.com/") }
      raise SafetyFailure, "GitHub did not return a pull-request URL." unless url

      number = Integer(url.split("/").last, 10)
      { "number" => number, "url" => url }
    rescue ArgumentError
      raise SafetyFailure, "GitHub returned an invalid pull-request URL: #{url}."
    end

    def pull_request_body(context, validation)
      lines = [
        "## Upstream synchronization",
        "",
        "- Fork base: `#{context.fork_sha}`",
        "- Official Ente: `#{context.official_sha}`",
        "- Validated commit: `#{context.commit}`",
        "- Validation gates: #{validation.steps.length} passed",
        "- Platform builds: #{validation.with_builds ? "passed" : "not requested"}",
        "",
        "This pull request was created by the guarded local upstream synchronizer. It was not merged automatically.",
      ]
      lines += ["", "Closes ##{context.issue.fetch("number")}"] if context.issue
      lines.join("\n")
    end

    def existing_pull_request_result(context)
      @output.puts("Existing open pull request: #{context.pull_request.fetch("url")}")
      PublicationResult.new(
        status: :existing_pull_request,
        branch: context.branch,
        commit: context.commit,
        official_sha: context.official_sha,
        issue_number: context.issue && context.issue.fetch("number"),
        pull_request_number: context.pull_request.fetch("number"),
        pull_request_url: context.pull_request.fetch("url"),
      )
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
